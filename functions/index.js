const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
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


const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { FieldValue } = require("firebase-admin/firestore");

exports.notifyAccountDecision = onDocumentUpdated("users/{userId}", async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!before || !after || before.status !== "pending" ||
      !["active", "rejected"].includes(after.status) ||
      before.status === after.status) return;

  const db = getFirestore();
  const deviceSnapshot = await db.collection("users").doc(event.params.userId)
    .collection("devices").get();
  const devices = deviceSnapshot.docs.map((doc) => ({
    token: doc.get("token"),
    ref: doc.ref,
  })).filter((device) => typeof device.token === "string" && device.token.length > 0);
  if (!devices.length) return;

  const approved = after.status === "active";
  const response = await getMessaging().sendEachForMulticast({
    tokens: devices.map((device) => device.token),
    notification: {
      title: approved ? "SkyNest account approved" : "SkyNest application update",
      body: approved
        ? "Your account has been approved. You can now sign in and continue."
        : "Your account application was not approved. Contact the property manager for details.",
    },
    data: {
      type: "account_decision",
      status: after.status,
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
      stale.push(devices[index].ref.delete());
    }
  });
  if (stale.length) await Promise.all(stale);
});

exports.changeAccountRole = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in before changing your account role.");
  }

  const uid = request.auth.uid;
  const targetRole = request.data && request.data.targetRole;
  const invitationCode = String((request.data && request.data.invitationCode) || "")
    .trim().toUpperCase();

  if (!["landlord", "tenant"].includes(targetRole)) {
    throw new HttpsError("invalid-argument", "Choose either Landlord or Tenant.");
  }

  const db = getFirestore();
  const userRef = db.collection("users").doc(uid);

  return db.runTransaction(async (transaction) => {
    const userSnapshot = await transaction.get(userRef);
    if (!userSnapshot.exists) {
      throw new HttpsError("not-found", "Your SkyNest account profile was not found.");
    }

    const user = userSnapshot.data();
    const currentRole = user.role;
    if (currentRole === targetRole) {
      throw new HttpsError("failed-precondition", "Your account already has this role.");
    }
    if (currentRole === "caretaker") {
      throw new HttpsError("failed-precondition",
        "Caretaker access is managed by your Landlord. Ask them to remove your assignment first.");
    }

    if (targetRole === "tenant" && currentRole === "landlord") {
      if (user.status !== "active") {
        throw new HttpsError("failed-precondition", "Only an active Landlord account can switch to Tenant.");
      }
      if (invitationCode.length < 6) {
        throw new HttpsError("invalid-argument", "Enter the Tenant invitation code supplied by your new landlord.");
      }

      const ownedByCreator = await transaction.get(
        db.collection("houses").where("createdBy", "==", uid)
      );
      const ownedByLandlord = await transaction.get(
        db.collection("houses").where("landlordId", "==", uid)
      );
      const linkedUsers = await transaction.get(
        db.collection("users").where("landlordId", "==", uid)
      );
      const openInvitations = await transaction.get(
        db.collection("invitations").where("landlordId", "==", uid).where("status", "==", "open")
      );

      const activeLinkedUsers = linkedUsers.docs.filter((doc) => {
        const linked = doc.data();
        return ["tenant", "caretaker"].includes(linked.role) &&
          ["active", "pending"].includes(linked.status);
      });

      if (!ownedByCreator.empty || !ownedByLandlord.empty) {
        throw new HttpsError("failed-precondition",
          "You still own property records. Transfer or remove those properties before switching to Tenant.");
      }
      if (activeLinkedUsers.length) {
        throw new HttpsError("failed-precondition",
          "Your account still has active or pending tenants/caretakers linked to it. Resolve those relationships before switching.");
      }

      const invitationRef = db.collection("invitations").doc(invitationCode);
      const invitationSnapshot = await transaction.get(invitationRef);
      if (!invitationSnapshot.exists) {
        throw new HttpsError("not-found", "That Tenant invitation code was not found.");
      }
      const invitation = invitationSnapshot.data();
      const expiry = invitation.expiresAt;
      if (invitation.role !== "tenant" || invitation.status !== "open" ||
          !invitation.landlordId || invitation.landlordId === uid ||
          !expiry || typeof expiry.toDate !== "function" || !expiry.toDate().getTime() ||
          expiry.toDate().getTime() <= Date.now()) {
        throw new HttpsError("failed-precondition",
          "That invitation is expired, already used, or is not a valid Tenant invitation.");
      }

      const newLandlordRef = db.collection("users").doc(invitation.landlordId);
      const newLandlordSnapshot = await transaction.get(newLandlordRef);
      const newLandlord = newLandlordSnapshot.data();
      if (!newLandlordSnapshot.exists || !newLandlord ||
          newLandlord.role !== "landlord" || newLandlord.status !== "active") {
        throw new HttpsError("failed-precondition", "The account that issued this invitation is not an active Landlord.");
      }

      transaction.update(userRef, {
        role: "tenant",
        status: "pending",
        landlordId: invitation.landlordId,
        propertyIds: Array.isArray(invitation.propertyIds) ? invitation.propertyIds : [],
        invitationCode,
        previousRole: "landlord",
        roleChangedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        houseId: FieldValue.delete(),
        houseNo: FieldValue.delete(),
      });
      transaction.update(invitationRef, {
        status: "used",
        usedBy: uid,
        usedAt: FieldValue.serverTimestamp(),
      });
      for (const openInvite of openInvitations.docs) {
        transaction.update(openInvite.ref, {
          status: "revoked",
          revokedAt: FieldValue.serverTimestamp(),
          revokedReason: "landlord_role_changed",
        });
      }
      return { role: "tenant", status: "pending" };
    }

    if (targetRole === "landlord" && currentRole === "tenant") {
      const assignedHouses = await transaction.get(
        db.collection("houses").where("assignedTenantId", "==", uid)
      );
      const pendingRequests = await transaction.get(
        db.collection("houseRequests").where("tenantId", "==", uid).where("status", "==", "pending")
      );
      if ((user.houseId && String(user.houseId).trim()) ||
          !assignedHouses.empty || !pendingRequests.empty) {
        throw new HttpsError("failed-precondition",
          "You still have an assigned house or a pending house request. End or resolve that tenancy first.");
      }

      transaction.update(userRef, {
        role: "landlord",
        status: "active",
        previousRole: "tenant",
        roleChangedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        landlordId: FieldValue.delete(),
        propertyIds: FieldValue.delete(),
        invitationCode: FieldValue.delete(),
        houseId: FieldValue.delete(),
        houseNo: FieldValue.delete(),
        approvedAt: FieldValue.delete(),
        approvedBy: FieldValue.delete(),
      });
      return { role: "landlord", status: "active" };
    }

    throw new HttpsError("failed-precondition",
      "This account type cannot be changed through self-service. Contact your property administrator.");
  });
});
