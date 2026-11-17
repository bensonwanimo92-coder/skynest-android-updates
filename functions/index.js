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


const { onCall, onRequest, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const crypto = require("node:crypto");
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


// Live Daraja collection. Each landlord connects credentials approved for their
// own PayBill or Buy Goods merchant shortcode. Secrets are encrypted at rest;
// consumer credentials and passkeys are never returned to the mobile client.
const MPESA_CONFIG_ENCRYPTION_KEY = defineSecret("MPESA_CONFIG_ENCRYPTION_KEY");
const DARAJA_API_BASE = "https://api.safaricom.co.ke";

function mpesaEncryptionKey() {
  const raw = MPESA_CONFIG_ENCRYPTION_KEY.value().trim();
  let key;
  if (/^[0-9a-fA-F]{64}$/.test(raw)) key = Buffer.from(raw, "hex");
  else key = Buffer.from(raw, "base64");
  if (key.length !== 32) {
    throw new Error("MPESA_CONFIG_ENCRYPTION_KEY must encode exactly 32 bytes (64 hex characters or base64).");
  }
  return key;
}

function encryptMpesaConfig(value) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", mpesaEncryptionKey(), iv);
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(value), "utf8"), cipher.final()]);
  return {
    version: 1,
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    ciphertext: encrypted.toString("base64"),
  };
}

function decryptMpesaConfig(value) {
  if (!value || value.version !== 1) throw new Error("Unsupported encrypted M-Pesa configuration.");
  const decipher = crypto.createDecipheriv(
    "aes-256-gcm", mpesaEncryptionKey(), Buffer.from(value.iv, "base64")
  );
  decipher.setAuthTag(Buffer.from(value.tag, "base64"));
  const clear = Buffer.concat([
    decipher.update(Buffer.from(value.ciphertext, "base64")),
    decipher.final(),
  ]).toString("utf8");
  return JSON.parse(clear);
}

function normalizeKenyanPhone(value) {
  const digits = String(value || "").replace(/\D/g, "");
  if (/^0[17]\d{8}$/.test(digits)) return "254" + digits.slice(1);
  if (/^254[17]\d{8}$/.test(digits)) return digits;
  if (/^[17]\d{8}$/.test(digits)) return "254" + digits;
  return null;
}

function darajaTimestamp(date = new Date()) {
  const pad = (n) => String(n).padStart(2, "0");
  return date.getFullYear() + pad(date.getMonth() + 1) + pad(date.getDate()) +
    pad(date.getHours()) + pad(date.getMinutes()) + pad(date.getSeconds());
}

function darajaPassword(shortcode, passkey, timestamp) {
  return Buffer.from(String(shortcode) + String(passkey) + timestamp).toString("base64");
}

async function darajaAccessToken(config) {
  const auth = Buffer.from(config.consumerKey + ":" + config.consumerSecret).toString("base64");
  const response = await fetch(DARAJA_API_BASE +
    "/oauth/v1/generate?grant_type=client_credentials", {
      method: "GET",
      headers: { Authorization: "Basic " + auth },
      signal: AbortSignal.timeout(15000),
    });
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.access_token) {
    throw new Error("Safaricom Daraja authentication failed: " +
      String(body.errorMessage || body.error_description || response.status));
  }
  return body.access_token;
}

async function darajaPost(path, token, payload) {
  const response = await fetch(DARAJA_API_BASE + path, {
    method: "POST",
    headers: {
      Authorization: "Bearer " + token,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
    signal: AbortSignal.timeout(20000),
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error("Safaricom Daraja request failed: " +
      String(body.errorMessage || body.ResponseDescription || response.status));
  }
  return body;
}

async function getLandlordMpesaConfig(db, landlordId) {
  const snap = await db.collection("mpesaMerchantConfigs").doc(landlordId).get();
  if (!snap.exists || snap.get("status") !== "active") {
    throw new Error("This landlord has not completed live M-Pesa collection setup.");
  }
  return decryptMpesaConfig(snap.get("encryptedCredentials"));
}

exports.saveLandlordMpesaConfig = onCall({
  secrets: [MPESA_CONFIG_ENCRYPTION_KEY],
  timeoutSeconds: 30,
}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const db = getFirestore();
  const uid = request.auth.uid;
  const profile = await db.collection("users").doc(uid).get();
  if (!profile.exists || profile.get("role") !== "landlord" ||
      profile.get("status") !== "active") {
    throw new HttpsError("permission-denied", "Only an active landlord can configure rent collection.");
  }

  const input = request.data || {};
  const type = String(input.type || "").toLowerCase();
  const shortcode = String(input.shortcode || "").trim();
  const storeShortcode = String(input.storeShortcode || "").trim();
  const tillNumber = String(input.tillNumber || "").trim();
  const consumerKey = String(input.consumerKey || "").trim();
  const consumerSecret = String(input.consumerSecret || "").trim();
  const passkey = String(input.passkey || "").trim();

  if (!["paybill", "till"].includes(type) ||
      !/^\d{5,7}$/.test(shortcode) ||
      (type === "till" && (!/^\d{5,7}$/.test(storeShortcode) ||
        !/^\d{5,7}$/.test(tillNumber))) ||
      consumerKey.length < 16 || consumerSecret.length < 16 ||
      !/^[0-9a-fA-F]{64}$/.test(passkey)) {
    throw new HttpsError("invalid-argument",
      "Enter valid live Daraja credentials, a 5–7 digit shortcode and a 64-character Lipa Na M-Pesa passkey. Till setup also requires Store/Head Office and Till numbers.");
  }

  const credentials = {
    type, shortcode, storeShortcode, tillNumber,
    consumerKey, consumerSecret, passkey,
  };
  const token = await darajaAccessToken(credentials);
  if (!token) throw new HttpsError("failed-precondition", "Daraja credentials could not be verified.");

  await db.collection("mpesaMerchantConfigs").doc(uid).set({
    landlordId: uid,
    type,
    displayShortcode: type === "till" ? tillNumber : shortcode,
    status: "active",
    encryptedCredentials: encryptMpesaConfig(credentials),
    credentialsUpdatedAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  }, { merge: true });

  return {
    configured: true,
    type,
    displayShortcode: type === "till" ? tillNumber : shortcode,
    message: "Live Daraja credentials authenticated and stored securely.",
  };
});

exports.getLandlordMpesaConfigStatus = onCall(async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first.");
  const uid = request.auth.uid;
  const profile = await getFirestore().collection("users").doc(uid).get();
  if (!profile.exists || profile.get("role") !== "landlord" ||
      profile.get("status") !== "active") {
    throw new HttpsError("permission-denied", "Only an active landlord can view collection setup.");
  }
  const snap = await getFirestore().collection("mpesaMerchantConfigs").doc(uid).get();
  return {
    configured: snap.exists && snap.get("status") === "active",
    type: snap.exists ? snap.get("type") || null : null,
    displayShortcode: snap.exists ? snap.get("displayShortcode") || null : null,
  };
});

exports.requestTenantMpesaStk = onCall({
  secrets: [MPESA_CONFIG_ENCRYPTION_KEY],
  timeoutSeconds: 60,
}, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign in before paying rent.");
  const uid = request.auth.uid;
  const input = request.data || {};
  const amount = Number(input.amount);
  const phone = normalizeKenyanPhone(input.phoneNumber);
  if (!Number.isSafeInteger(amount) || amount < 1 || amount > 250000 ||
      !phone || !/^[A-Za-z0-9_-]{2,12}$/.test(String(input.accountReference || ""))) {
    throw new HttpsError("invalid-argument",
      "Enter a whole KSh amount, a valid Kenyan M-Pesa number and a valid house/account reference.");
  }

  const db = getFirestore();
  const tenantSnap = await db.collection("users").doc(uid).get();
  const tenant = tenantSnap.data() || {};
  if (!tenantSnap.exists || tenant.role !== "tenant" || tenant.status !== "active" ||
      typeof tenant.landlordId !== "string" || !tenant.landlordId) {
    throw new HttpsError("permission-denied", "An active tenant linked to a landlord is required.");
  }
  const landlordId = tenant.landlordId;
  const landlordSnap = await db.collection("users").doc(landlordId).get();
  if (!landlordSnap.exists || landlordSnap.get("role") !== "landlord" ||
      landlordSnap.get("status") !== "active") {
    throw new HttpsError("failed-precondition", "The linked landlord account is not active.");
  }

  let config;
  try { config = await getLandlordMpesaConfig(db, landlordId); }
  catch (error) { throw new HttpsError("failed-precondition", error.message); }

  const intentRef = db.collection("mpesaPaymentIntents").doc();
  const reference = String(input.accountReference).trim();
  await intentRef.set({
    tenantId: uid,
    tenantName: String(tenant.displayName || "Tenant").slice(0, 100),
    landlordId,
    houseId: tenant.houseId || null,
    houseNo: String(tenant.houseNo || reference).slice(0, 40),
    amount,
    phoneNumber: phone,
    accountReference: reference,
    status: "initiating",
    createdAt: FieldValue.serverTimestamp(),
  });

  try {
    const shortcode = config.type === "till" ? config.storeShortcode : config.shortcode;
    const partyB = config.type === "till" ? config.tillNumber : config.shortcode;
    const timestamp = darajaTimestamp();
    const token = await darajaAccessToken(config);
    const callbackUrl = "https://us-central1-" + process.env.GCLOUD_PROJECT +
      ".cloudfunctions.net/mpesaStkCallback";
    const response = await darajaPost("/mpesa/stkpush/v1/processrequest", token, {
      BusinessShortCode: shortcode,
      Password: darajaPassword(shortcode, config.passkey, timestamp),
      Timestamp: timestamp,
      TransactionType: config.type === "till"
        ? "CustomerBuyGoodsOnline" : "CustomerPayBillOnline",
      Amount: amount,
      PartyA: phone,
      PartyB: partyB,
      PhoneNumber: phone,
      CallBackURL: callbackUrl,
      AccountReference: reference,
      TransactionDesc: "SkyNest rent",
    });

    if (String(response.ResponseCode) !== "0" ||
        !response.CheckoutRequestID || !response.MerchantRequestID) {
      throw new Error(response.ResponseDescription || "Safaricom did not accept the STK request.");
    }
    await intentRef.update({
      status: "pending",
      checkoutRequestId: response.CheckoutRequestID,
      merchantRequestId: response.MerchantRequestID,
      darajaResponseDescription: String(response.ResponseDescription || ""),
      updatedAt: FieldValue.serverTimestamp(),
    });
    return {
      accepted: true,
      paymentIntentId: intentRef.id,
      checkoutRequestId: response.CheckoutRequestID,
      customerMessage: response.CustomerMessage || "Check your phone for the M-Pesa PIN prompt.",
    };
  } catch (error) {
    await intentRef.update({
      status: "failed",
      failureReason: String(error.message || error).slice(0, 300),
      updatedAt: FieldValue.serverTimestamp(),
    });
    throw new HttpsError("unavailable",
      "Could not start the M-Pesa prompt: " + String(error.message || error));
  }
});

// Safaricom calls this endpoint asynchronously. The callback alone is not
// trusted: query Daraja again, then reconcile amount/phone/receipt and write
// the Ledger record atomically. Duplicate callbacks are idempotent.
exports.mpesaStkCallback = onRequest({
  timeoutSeconds: 60,
  secrets: [MPESA_CONFIG_ENCRYPTION_KEY],
}, async (req, res) => {
  if (req.method !== "POST") return res.status(405).send("Method not allowed");
  const callback = req.body && req.body.Body && req.body.Body.stkCallback;
  if (!callback || !callback.CheckoutRequestID) {
    return res.status(200).json({ ResultCode: 0, ResultDesc: "Callback received." });
  }

  const db = getFirestore();
  let callbackIntentRef = null;
  try {
    const matches = await db.collection("mpesaPaymentIntents")
      .where("checkoutRequestId", "==", String(callback.CheckoutRequestID)).limit(1).get();
    if (matches.empty) return res.status(200).json({ ResultCode: 0, ResultDesc: "Unknown checkout ignored." });
    const intentRef = matches.docs[0].ref;
    callbackIntentRef = intentRef;
    const intent = matches.docs[0].data();
    if (intent.status === "paid") {
      return res.status(200).json({ ResultCode: 0, ResultDesc: "Already processed." });
    }
    if (intent.status !== "pending") {
      return res.status(200).json({ ResultCode: 0, ResultDesc: "Payment is not pending." });
    }

    const config = await getLandlordMpesaConfig(db, intent.landlordId);
    const shortcode = config.type === "till" ? config.storeShortcode : config.shortcode;
    const timestamp = darajaTimestamp();
    const token = await darajaAccessToken(config);
    const query = await darajaPost("/mpesa/stkpushquery/v1/query", token, {
      BusinessShortCode: shortcode,
      Password: darajaPassword(shortcode, config.passkey, timestamp),
      Timestamp: timestamp,
      CheckoutRequestID: String(callback.CheckoutRequestID),
    });

    const resultCode = Number(callback.ResultCode);
    const metadata = callback.CallbackMetadata && callback.CallbackMetadata.Item;
    const item = (name) => Array.isArray(metadata)
      ? metadata.find((entry) => entry.Name === name)?.Value : undefined;
    const callbackAmount = Number(item("Amount"));
    const callbackPhone = normalizeKenyanPhone(item("PhoneNumber"));
    const receipt = String(item("MpesaReceiptNumber") || "").trim().toUpperCase();
    const confirmed = resultCode === 0 && Number(query.ResultCode) === 0 &&
      callbackAmount === Number(intent.amount) &&
      callbackPhone === intent.phoneNumber && /^[A-Z0-9]{8,16}$/.test(receipt);

    if (!confirmed) {
      await intentRef.update({
        status: resultCode === 0 ? "review_required" : "failed",
        darajaResultCode: resultCode,
        darajaResultDescription: String(callback.ResultDesc || query.ResultDesc || "").slice(0, 300),
        updatedAt: FieldValue.serverTimestamp(),
      });
      return res.status(200).json({ ResultCode: 0, ResultDesc: "Payment result recorded." });
    }

    const paymentRef = db.collection("payments").doc("mpesa_" + receipt);
    await db.runTransaction(async (transaction) => {
      const fresh = await transaction.get(intentRef);
      if (!fresh.exists || fresh.get("status") === "paid") return;
      const existingPayment = await transaction.get(paymentRef);
      if (existingPayment.exists) {
        transaction.update(intentRef, {
          status: "review_required",
          failureReason: "M-Pesa receipt already exists on another payment.",
          updatedAt: FieldValue.serverTimestamp(),
        });
        return;
      }
      transaction.create(paymentRef, {
        tenantName: intent.tenantName,
        tenantId: intent.tenantId,
        houseNo: intent.houseNo,
        houseId: intent.houseId,
        amount: intent.amount,
        method: "MPESA",
        transactionCode: receipt,
        status: "Paid",
        createdBy: intent.landlordId,
        landlordId: intent.landlordId,
        mpesaPaymentIntentId: intentRef.id,
        phoneNumber: intent.phoneNumber,
        createdAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
        paidAt: FieldValue.serverTimestamp(),
      });
      transaction.update(intentRef, {
        status: "paid",
        mpesaReceiptNumber: receipt,
        paymentId: paymentRef.id,
        confirmedAt: FieldValue.serverTimestamp(),
        updatedAt: FieldValue.serverTimestamp(),
      });
    });
    return res.status(200).json({ ResultCode: 0, ResultDesc: "Payment processed." });
  } catch (error) {
    console.error("M-Pesa callback processing failed:", error);
    if (callbackIntentRef) {
      try {
        await db.runTransaction(async (transaction) => {
          const current = await transaction.get(callbackIntentRef);
          if (current.exists && current.get("status") === "pending") {
            transaction.update(callbackIntentRef, {
              status: "review_required",
              failureReason: "Safaricom result could not be independently reconciled. " +
                String(error.message || error).slice(0, 220),
              updatedAt: FieldValue.serverTimestamp(),
            });
          }
        });
      } catch (recordError) {
        console.error("Could not mark M-Pesa intent for reconciliation:", recordError);
      }
    }
    return res.status(200).json({ ResultCode: 0, ResultDesc: "Callback received; reconciliation required." });
  }
});
