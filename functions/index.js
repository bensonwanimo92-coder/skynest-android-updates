const { onSchedule } = require("firebase-functions/v2/scheduler");
const { onDocumentCreated, onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();

exports.notifyGroupMessage = onDocumentCreated(
  "groups/{groupId}/messages/{messageId}",
  async (event) => {
    const message = event.data && event.data.data();
    if (!message || !message.senderId || message.encryptionVersion !== 1) return;

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
    // Never place chat plaintext in push notifications. Message content is
    // encrypted on-device; notifications reveal only that a secure message arrived.
    const body = "sent an encrypted message.";

    for (let offset = 0; offset < tokenOwners.length; offset += 500) {
      const batch = tokenOwners.slice(offset, offset + 500);
      const response = await getMessaging().sendEachForMulticast({
        tokens: batch.map((entry) => entry.token),
        notification: { title: groupName, body: senderName + " " + body },
        data: {
          type: "group_message",
          groupId: event.params.groupId,
          messageId: event.params.messageId,
        },
        android: {
          priority: "high",
          notification: { channelId: "skynest_messages_v2", sound: "pop" },
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

exports.notifyIncomingCall = onDocumentUpdated("calls/{callId}", async (event) => {
  const before = event.data && event.data.before.data();
  const after = event.data && event.data.after.data();
  if (!before || !after || before.status === "ringing" || after.status !== "ringing") return;
  if (!after.calleeId || !after.callerId) return;

  const db = getFirestore();
  const devicesSnapshot = await db.collection("users").doc(after.calleeId)
    .collection("devices").get();
  const devices = devicesSnapshot.docs.map((doc) => ({
    token: doc.get("token"),
    ref: doc.ref,
  })).filter((device) => typeof device.token === "string" && device.token.length > 0);
  if (!devices.length) return;

  const callType = after.type === "video" ? "video" : "voice";
  const senderName = String(after.callerName || "A SkyNest member");
  const response = await getMessaging().sendEachForMulticast({
    tokens: devices.map((device) => device.token),
    notification: {
      title: callType === "video" ? "Incoming SkyNest video call" : "Incoming SkyNest voice call",
      body: senderName + " is calling you.",
    },
    data: {
      type: "incoming_call",
      callId: event.params.callId,
      callerName: senderName,
      callType,
    },
    android: {
      priority: "high",
      ttl: 60 * 1000,
      notification: {
        channelId: "skynest_calls",
        sound: "default",
        priority: "max",
        visibility: "public",
      },
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
      notification: { channelId: "skynest_messages_v2", sound: "pop" },
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

exports.requestTenantAccess = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in before requesting tenant access.");
  }
  const uid = request.auth.uid;
  const landlordEmail = String((request.data && request.data.landlordEmail) || "").trim().toLowerCase();
  if (!/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(landlordEmail)) {
    throw new HttpsError("invalid-argument", "Enter a valid landlord email address.");
  }
  const db = getFirestore();
  const authUser = await require("firebase-admin/auth").getAuth().getUser(uid);
  const matches = await db.collection("users").where("role", "==", "landlord")
    .where("status", "==", "active").get();
  const landlords = matches.docs.filter((doc) =>
    String(doc.get("email") || "").trim().toLowerCase() === landlordEmail);
  if (!landlords.length) {
    throw new HttpsError("not-found", "No active SkyNest landlord account uses that email. Check the address with your landlord.");
  }
  if (landlords.length !== 1) {
    throw new HttpsError("failed-precondition", "That email is linked to more than one landlord account. Contact SkyNest support.");
  }
  const landlord = landlords[0];
  if (landlord.id === uid) {
    throw new HttpsError("failed-precondition", "A landlord cannot request tenant access to their own account.");
  }
  const userRef = db.collection("users").doc(uid);
  await db.runTransaction(async (transaction) => {
    const existing = await transaction.get(userRef);
    if (existing.exists) {
      throw new HttpsError("already-exists", "A SkyNest profile already exists for this account. Sign in instead of registering again.");
    }
    transaction.create(userRef, {
      displayName: authUser.displayName || "Tenant",
      email: String(authUser.email || "").trim(),
      role: "tenant",
      status: "pending",
      landlordId: landlord.id,
      propertyIds: [],
      registrationMethod: "landlord_email",
      createdAt: FieldValue.serverTimestamp(),
    });
  });
  return { role: "tenant", status: "pending", landlordId: landlord.id };
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


// User-managed reminders. The scheduled worker runs in Nairobi time and sends
// reminders to the owning Landlord's registered devices only.
exports.runScheduledAutomations = onSchedule({
  schedule: "every 5 minutes",
  timeZone: "Africa/Nairobi",
  region: "africa-south1",
  maxInstances: 1,
}, async () => {
  const db = getFirestore();
  const now = new Date();
  const due = await db.collection("automations")
    .where("enabled", "==", true)
    .where("nextRunAt", "<=", now)
    .limit(100)
    .get();

  const nextOccurrence = (date, frequency) => {
    const next = new Date(date.getTime());
    if (frequency === "daily") next.setUTCDate(next.getUTCDate() + 1);
    else if (frequency === "weekly") next.setUTCDate(next.getUTCDate() + 7);
    else if (frequency === "monthly") {
      const day = next.getUTCDate();
      next.setUTCDate(1);
      next.setUTCMonth(next.getUTCMonth() + 1);
      const lastDay = new Date(Date.UTC(next.getUTCFullYear(), next.getUTCMonth() + 1, 0)).getUTCDate();
      next.setUTCDate(Math.min(day, lastDay));
    }
    return next;
  };

  for (const snapshot of due.docs) {
    const ref = snapshot.ref;
    const claimed = await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(ref);
      if (!fresh.exists) return null;
      const data = fresh.data();
      const dueAt = data.nextRunAt && data.nextRunAt.toDate();
      if (data.enabled !== true || !dueAt || dueAt.getTime() > Date.now()) return null;
      const frequency = ["once", "daily", "weekly", "monthly"].includes(data.frequency)
        ? data.frequency : "once";
      const nextRunAt = frequency === "once"
        ? null : nextOccurrence(dueAt, frequency);
      transaction.update(ref, {
        enabled: frequency === "once" ? false : true,
        nextRunAt: nextRunAt,
        lastStatus: "sending",
        lastAttemptAt: FieldValue.serverTimestamp(),
        attemptCount: FieldValue.increment(1),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return {
        ownerId: data.ownerId,
        title: String(data.title || "SkyNest reminder").slice(0, 100),
        message: String(data.message || "").slice(0, 500),
        dueAt,
        frequency,
        retryDeviceIds: Array.isArray(data.retryDeviceIds) ? data.retryDeviceIds : null,
        retryAttempts: Number.isInteger(data.retryAttempts) ? data.retryAttempts : 0,
      };
    });
    if (!claimed || !claimed.ownerId) continue;

    let status = "sent";
    let errorMessage = null;
    let failedDeviceIds = [];
    let terminalFailureCount = 0;
    let successCount = 0;
    const retryAttempt = claimed.retryAttempts + 1;
    try {
      const devices = await db.collection("users").doc(claimed.ownerId)
        .collection("devices").get();
      const registered = devices.docs.map((device) => ({
        id: device.id,
        token: device.get("token"),
        ref: device.ref,
      })).filter((device) => typeof device.token === "string" && device.token.length > 0);
      const targets = claimed.retryDeviceIds
        ? registered.filter((device) => claimed.retryDeviceIds.includes(device.id))
        : registered;
      if (!targets.length) throw new Error("No registered devices are available for this account or retry.");

      for (let offset = 0; offset < targets.length; offset += 500) {
        const batch = targets.slice(offset, offset + 500);
        const result = await getMessaging().sendEachForMulticast({
          tokens: batch.map((item) => item.token),
          notification: { title: claimed.title, body: claimed.message },
          data: { type: "automation_reminder", automationId: ref.id },
          android: { priority: "high", notification: { channelId: "skynest_messages_v2", sound: "pop" } },
        });

        const stale = [];
        result.responses.forEach((response, index) => {
          if (response.success) {
            successCount += 1;
          } else if (response.error &&
              ["messaging/registration-token-not-registered", "messaging/invalid-registration-token"].includes(response.error.code)) {
            terminalFailureCount += 1;
            stale.push(batch[index].ref.delete());
          } else {
            failedDeviceIds.push(batch[index].id);
          }
        });
        if (stale.length) await Promise.all(stale);
      }

      if (failedDeviceIds.length) {
        status = successCount > 0 ? "partial" : "failed";
        errorMessage = failedDeviceIds.length + " device(s) did not accept the reminder; retry scheduled.";
        if (retryAttempt < 3) {
          await ref.set({
            enabled: true,
            nextRunAt: claimed.dueAt,
            retryDeviceIds: failedDeviceIds,
            retryAttempts: retryAttempt,
          }, { merge: true });
        } else {
          await ref.set({
            enabled: claimed.frequency !== "once",
            retryDeviceIds: FieldValue.delete(),
            retryAttempts: 0,
          }, { merge: true });
          errorMessage = failedDeviceIds.length + " device(s) still failed after three attempts.";
        }
      } else {
        if (terminalFailureCount > 0) {
          status = successCount > 0 ? "partial" : "failed";
          errorMessage = terminalFailureCount + " stale device token(s) were removed.";
        }
        await ref.set({
          retryDeviceIds: FieldValue.delete(),
          retryAttempts: 0,
        }, { merge: true });
      }
    } catch (error) {
      status = "failed";
      errorMessage = String(error && error.message ? error.message : error).slice(0, 500);
      if (retryAttempt < 3) {
        await ref.set({
          enabled: true,
          nextRunAt: claimed.dueAt,
          retryAttempts: retryAttempt,
        }, { merge: true });
      } else {
        await ref.set({
          enabled: claimed.frequency !== "once",
          retryDeviceIds: FieldValue.delete(),
          retryAttempts: 0,
        }, { merge: true });
        errorMessage = "Stopped after three attempts: " + errorMessage;
      }
    }

    const completedAt = FieldValue.serverTimestamp();
    await ref.set({
      lastStatus: status,
      lastRunAt: completedAt,
      lastError: errorMessage,
      updatedAt: completedAt,
    }, { merge: true });
    await ref.collection("runs").add({
      status,
      error: errorMessage,
      scheduledFor: claimed.dueAt,
      completedAt,
      createdAt: completedAt,
      retryAttempt,
      deliveredDeviceCount: successCount,
      failedDeviceCount: failedDeviceIds.length + terminalFailureCount,
    });
  }
});
