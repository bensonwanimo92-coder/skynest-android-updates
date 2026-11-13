const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.notifyGroupMessage = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data && event.data.data();
    if (!message || !message.senderId || !message.text) return;

    const db = getFirestore();
    const groupRef = db.collection("groups").doc(event.params.groupId);
    const groupSnap = await groupRef.get();
    if (!groupSnap.exists) return;

    const group = groupSnap.data();
    const memberIds = Array.isArray(group.memberIds) ? group.memberIds : [];
    const recipients = memberIds.filter((uid) => uid && uid !== message.senderId);
    if (!recipients.length) return;

    const deviceSnapshots = await Promise.all(
      recipients.map((uid) => db.collection("users").doc(uid).collection("devices").get())
    );
    const tokenOwners = [];
    for (const snapshot of deviceSnapshots) {
      for (const device of snapshot.docs) {
        const token = device.get("token");
        if (typeof token === "string" && token.length > 0) {
          tokenOwners.push({ token, ref: device.ref });
        }
      }
    }
    if (!tokenOwners.length) return;

    const senderSnap = await db.collection("users").doc(message.senderId).get();
    const senderName = message.senderName || senderSnap.get("displayName") || "A group member";
    const groupName = group.name || "SkyNest group";
    const body = String(message.text).length > 140
      ? String(message.text).slice(0, 137) + "..."
      : String(message.text);

    for (let offset = 0; offset < tokenOwners.length; offset += 500) {
      const batch = tokenOwners.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: batch.map((entry) => entry.token),
        notification: { title: groupName, body: senderName + ": " + body },
        data: {
          type: "group_message",
          groupId: event.params.groupId,
          messageId: event.params.messageId,
        },
        android: {
          priority: "high",
          notification: { channelId: "skynest_messages" },
        },
      });

      const stale = [];
      response.responses.forEach((result, index) => {
        if (!result.success && result.error &&
            ["messaging/registration-token-not-registered",
             "messaging/invalid-registration-token"].includes(result.error.code)) {
          stale.push(batch[index].ref.delete());
        }
      });
      if (stale.length) await Promise.all(stale);
    }
  }
);
