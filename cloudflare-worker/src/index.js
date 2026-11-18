import { validateSuccessfulCallback } from "./payment_validation.js";

// SkyNest M-Pesa Cloudflare Worker.
// Sandbox-first per-landlord Daraja STK Push. Do not enable production until Safaricom onboarding and end-to-end tests pass.

const darajaTokens = new Map();
let googleToken = null;
let googleTokenExpiry = 0;

class HttpError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}
const json = (data, status = 200) => new Response(JSON.stringify(data), {
  status,
  headers: {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,POST,OPTIONS",
    "access-control-allow-headers": "authorization,content-type",
  },
});
const nowIso = () => new Date().toISOString();
const timestampValue = (date = new Date()) => ({ timestampValue: date.toISOString() });

function b64url(value) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value;
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/=/g, "").replace(/\+/g, "-").replace(/\//g, "_");
}
function privateKeyBytes(pem) {
  const body = String(pem || "").replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "");
  if (!body) throw new HttpError("Firebase service account private key is missing.", 500);
  return Uint8Array.from(atob(body), c => c.charCodeAt(0));
}
function encodeValue(value) {
  if (value === null || value === undefined) return { nullValue: null };
  if (value && value.__firestoreTimestamp) return timestampValue(value.__firestoreTimestamp);
  if (typeof value === "string") return { stringValue: value };
  if (typeof value === "boolean") return { booleanValue: value };
  if (Number.isInteger(value)) return { integerValue: String(value) };
  if (typeof value === "number" && Number.isFinite(value)) return { doubleValue: value };
  return { stringValue: String(value) };
}
function encodeFields(values) {
  const fields = {};
  for (const [key, value] of Object.entries(values)) fields[key] = encodeValue(value);
  return fields;
}
function decodeFields(fields = {}) {
  const result = {};
  for (const [key, value] of Object.entries(fields)) {
    if ("stringValue" in value) result[key] = value.stringValue;
    else if ("integerValue" in value) result[key] = Number(value.integerValue);
    else if ("doubleValue" in value) result[key] = value.doubleValue;
    else if ("booleanValue" in value) result[key] = value.booleanValue;
    else if ("timestampValue" in value) result[key] = value.timestampValue;
    else if ("nullValue" in value) result[key] = null;
  }
  return result;
}
async function googleAccessToken(env) {
  if (googleToken && Date.now() < googleTokenExpiry) return googleToken;
  let account;
  try { account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON || "{}"); }
  catch { throw new HttpError("Firebase service-account JSON is invalid.", 500); }
  if (!account.client_email || !account.private_key) throw new HttpError("Firebase service account is not configured.", 500);
  const tokenUri = account.token_uri || "https://oauth2.googleapis.com/token";
  const issuedAt = Math.floor(Date.now() / 1000);
  const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claim = b64url(JSON.stringify({
    iss: account.client_email,
    scope: "https://www.googleapis.com/auth/datastore",
    aud: tokenUri,
    iat: issuedAt,
    exp: issuedAt + 3600,
  }));
  const unsigned = header + "." + claim;
  const key = await crypto.subtle.importKey(
    "pkcs8", privateKeyBytes(account.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const response = await fetch(tokenUri, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: unsigned + "." + b64url(new Uint8Array(signature)),
    }),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token) throw new HttpError("Firebase server authentication failed.", 502);
  googleToken = data.access_token;
  googleTokenExpiry = Date.now() + Math.max(60, Number(data.expires_in || 3600) - 120) * 1000;
  return googleToken;
}
async function firestore(env, path, init = {}) {
  if (!env.FIREBASE_PROJECT_ID) throw new HttpError("Firebase project ID is not configured.", 500);
  const token = await googleAccessToken(env);
  const url = "https://firestore.googleapis.com/v1/projects/" +
    encodeURIComponent(env.FIREBASE_PROJECT_ID) + "/databases/(default)/documents/" + path;
  const response = await fetch(url, {
    ...init,
    headers: {
      authorization: "Bearer " + token,
      "content-type": "application/json",
      ...(init.headers || {}),
    },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok && response.status !== 404 && response.status !== 409) {
    throw new HttpError(data.error?.message || "Firestore request failed.", 502);
  }
  return { status: response.status, data };
}
async function createDocument(env, collection, id, fields) {
  return firestore(env, collection + "?documentId=" + encodeURIComponent(id), {
    method: "POST", body: JSON.stringify({ fields: encodeFields(fields) }),
  });
}
async function patchDocument(env, path, fields) {
  const mask = Object.keys(fields).map(key => "updateMask.fieldPaths=" + encodeURIComponent(key)).join("&");
  return firestore(env, path + (mask ? "?" + mask : ""), {
    method: "PATCH", body: JSON.stringify({ fields: encodeFields(fields) }),
  });
}
async function verifyFirebaseUser(request, env) {
  const authorization = request.headers.get("authorization") || "";
  const idToken = authorization.startsWith("Bearer ") ? authorization.slice(7) : "";
  if (!idToken) throw new HttpError("Sign in to SkyNest first.", 401);
  if (!env.FIREBASE_WEB_API_KEY) throw new HttpError("Firebase web API key is not configured.", 500);
  const response = await fetch(
    "https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=" + encodeURIComponent(env.FIREBASE_WEB_API_KEY),
    {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ idToken }),
    },
  );
  const data = await response.json().catch(() => ({}));
  const user = data.users?.[0];
  if (!response.ok || !user || user.disabled) throw new HttpError("Your SkyNest session is invalid. Sign in again.", 401);
  return user.localId;
}
async function darajaAccessToken(env, credentials = {}) {
  const consumerKey = credentials.consumerKey || env.DARAJA_CONSUMER_KEY;
  const consumerSecret = credentials.consumerSecret || env.DARAJA_CONSUMER_SECRET;
  if (!consumerKey || !consumerSecret) throw new HttpError("This landlord's Daraja API credentials are not configured.", 500);
  const cacheKey = consumerKey;
  const cached = darajaTokens.get(cacheKey);
  if (cached && Date.now() < cached.expiresAt) return cached.token;
  const host = env.DARAJA_ENV === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
  const basic = btoa(consumerKey + ":" + consumerSecret);
  const response = await fetch(host + "/oauth/v1/generate?grant_type=client_credentials", {
    headers: { authorization: "Basic " + basic },
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || !data.access_token) throw new HttpError("Daraja authentication failed. Check this landlord's credentials and environment.", 502);
  const token = data.access_token;
  darajaTokens.set(cacheKey, { token, expiresAt: Date.now() + Math.max(60, Number(data.expires_in || 3600) - 120) * 1000 });
  return token;
}
function normalizePhone(value) {
  let phone = String(value || "").replace(/[\s+()\-]/g, "");
  if (phone.startsWith("0")) phone = "254" + phone.slice(1);
  else if (/^[17]\d{8}$/.test(phone)) phone = "254" + phone;
  if (!/^254[17]\d{8}$/.test(phone)) throw new HttpError("Enter a valid Kenyan M-Pesa number, e.g. 07XXXXXXXX or 2547XXXXXXXX.");
  return phone;
}
async function mpesaEncryptionKey(env) {
  const secret = String(env.MPESA_ENCRYPTION_KEY || "");
  if (!secret) throw new HttpError("MPESA_ENCRYPTION_KEY is not configured in Cloudflare.", 500);
  const raw = new TextEncoder().encode(secret);
  if (raw.length !== 32) throw new HttpError("MPESA_ENCRYPTION_KEY must be exactly 32 ASCII characters generated by a password manager.", 500);
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}
async function encryptLandlordConfig(env, config) {
  const key = await mpesaEncryptionKey(env);
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const plain = new TextEncoder().encode(JSON.stringify(config));
  const cipher = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, plain);
  return JSON.stringify({ v: 1, iv: b64url(iv), data: b64url(new Uint8Array(cipher)) });
}
async function decryptLandlordConfig(env, envelope) {
  try {
    const item = JSON.parse(String(envelope || ""));
    if (item.v !== 1 || !item.iv || !item.data) throw new Error("Invalid envelope");
    const key = await mpesaEncryptionKey(env);
    const fromUrl = value => Uint8Array.from(atob(value.replace(/-/g, "+").replace(/_/g, "/") + "=".repeat((4 - value.length % 4) % 4)), c => c.charCodeAt(0));
    const plain = await crypto.subtle.decrypt({ name: "AES-GCM", iv: fromUrl(item.iv) }, key, fromUrl(item.data));
    return JSON.parse(new TextDecoder().decode(plain));
  } catch (error) {
    if (error instanceof HttpError) throw error;
    throw new HttpError("Could not decrypt this landlord's M-Pesa configuration. Ask the landlord to save it again.", 500);
  }
}
async function saveLandlordPaymentAccount(request, env) {
  const uid = await verifyFirebaseUser(request, env);
  const profileResult = await firestore(env, "users/" + encodeURIComponent(uid));
  if (profileResult.status === 404) throw new HttpError("Landlord profile not found.", 403);
  const profile = decodeFields(profileResult.data.fields);
  if (String(profile.role || "").toLowerCase() !== "landlord" ||
      String(profile.status || "").toLowerCase() !== "active") {
    throw new HttpError("Only an active landlord can configure a receiving account.", 403);
  }
  let input;
  try { input = await request.json(); } catch { throw new HttpError("Request body must be valid JSON."); }
  const type = String(input.accountType || "").toLowerCase();
  const businessName = String(input.registeredBusinessName || "").trim();
  const shortcode = String(input.businessShortCode || "").trim();
  const tillNumber = String(input.tillNumber || "").trim();
  const consumerKey = String(input.consumerKey || "").trim();
  const consumerSecret = String(input.consumerSecret || "").trim();
  const passkey = String(input.passkey || "").trim();
  if (!["paybill", "till"].includes(type)) throw new HttpError("Choose PayBill or Buy Goods Till.");
  if (!businessName || businessName.length > 120) throw new HttpError("Enter the registered business name.");
  if (!/^\d{5,7}$/.test(shortcode)) throw new HttpError("Enter a valid 5–7 digit Daraja business shortcode.");
  if (type === "till" && !/^\d{5,20}$/.test(tillNumber)) throw new HttpError("Enter a valid Buy Goods Till number.");
  if (type === "paybill" && tillNumber) throw new HttpError("A Till number is not used for PayBill.");
  if (consumerKey.length < 8 || consumerSecret.length < 8 || passkey.length < 8) {
    throw new HttpError("Enter the Daraja Consumer Key, Consumer Secret and Lipa Na M-Pesa Passkey.");
  }
  const envelope = await encryptLandlordConfig(env, {
    accountType: type, businessName, businessShortCode: shortcode,
    tillNumber: type === "till" ? tillNumber : "",
    consumerKey, consumerSecret, passkey,
  });
  const accountFields = {
    landlordId: uid,
    accountType: type,
    registeredBusinessName: businessName,
    maskedAccount: (type === "till" ? tillNumber : shortcode).slice(-4).padStart(8, "•"),
    encryptedConfig: envelope,
    status: "pending_verification",
    environment: String(env.DARAJA_ENV || "sandbox"),
    updatedAt: { __firestoreTimestamp: new Date() },
  };
  const saved = await createDocument(env, "landlordPaymentAccounts", uid, accountFields);
  if (saved.status === 409) await patchDocument(env, "landlordPaymentAccounts/" + encodeURIComponent(uid), accountFields);
  return json({ ok: true, status: "pending_verification", message: "Receiving account saved securely. Verification is still required before tenants can pay." });
}
async function getLandlordPaymentAccount(request, env) {
  const uid = await verifyFirebaseUser(request, env);
  const profileResult = await firestore(env, "users/" + encodeURIComponent(uid));
  if (profileResult.status === 404) throw new HttpError("Profile not found.", 403);
  const profile = decodeFields(profileResult.data.fields);
  if (String(profile.role || "").toLowerCase() !== "landlord" ||
      String(profile.status || "").toLowerCase() !== "active") {
    throw new HttpError("Only an active landlord can view receiving-account settings.", 403);
  }
  const result = await firestore(env, "landlordPaymentAccounts/" + encodeURIComponent(uid));
  if (result.status === 404) return json({ configured: false, status: "not_configured" });
  const data = decodeFields(result.data.fields);
  return json({
    configured: true,
    accountType: data.accountType || "",
    registeredBusinessName: data.registeredBusinessName || "",
    maskedAccount: data.maskedAccount || "",
    status: data.status || "pending_verification",
    environment: data.environment || "sandbox",
    credentialsStored: Boolean(data.encryptedConfig),
  });
}

function darajaTimestamp() {
  const date = new Date(Date.now() + 3 * 60 * 60 * 1000);
  return date.getUTCFullYear() +
    String(date.getUTCMonth() + 1).padStart(2, "0") +
    String(date.getUTCDate()).padStart(2, "0") +
    String(date.getUTCHours()).padStart(2, "0") +
    String(date.getUTCMinutes()).padStart(2, "0") +
    String(date.getUTCSeconds()).padStart(2, "0");
}
function assertConfiguration(env) {
  const required = [
    "FIREBASE_PROJECT_ID", "FIREBASE_WEB_API_KEY", "FIREBASE_SERVICE_ACCOUNT_JSON",
    "MPESA_ENCRYPTION_KEY", "STK_CALLBACK_URL", "STK_CALLBACK_TOKEN",
  ];
  const missing = required.filter(key => !env[key]);
  if (missing.length) throw new HttpError("Worker configuration is incomplete: " + missing.join(", "), 500);
  if (String(env.STK_CALLBACK_TOKEN).length < 32) throw new HttpError("STK_CALLBACK_TOKEN must be at least 32 characters.", 500);
  if (!String(env.STK_CALLBACK_URL).startsWith("https://")) throw new HttpError("STK_CALLBACK_URL must use HTTPS.", 500);
}
async function verifyLandlordPaymentAccount(request, env) {
  assertConfiguration(env);
  const uid = await verifyFirebaseUser(request, env);
  const profileResult = await firestore(env, "users/" + encodeURIComponent(uid));
  if (profileResult.status === 404) throw new HttpError("Landlord profile not found.", 403);
  const profile = decodeFields(profileResult.data.fields);
  if (String(profile.role || "").toLowerCase() !== "landlord" ||
      String(profile.status || "").toLowerCase() !== "active") {
    throw new HttpError("Only an active landlord can verify a receiving account.", 403);
  }
  const accountResult = await firestore(env, "landlordPaymentAccounts/" + encodeURIComponent(uid));
  if (accountResult.status === 404) throw new HttpError("Save your PayBill or Till details first.", 409);
  const accountMeta = decodeFields(accountResult.data.fields);
  const merchant = await decryptLandlordConfig(env, accountMeta.encryptedConfig);
  const input = await request.json().catch(() => ({}));
  const phone = normalizePhone(input.phone);
  const amount = 1;
  const timestamp = darajaTimestamp();
  const callbackUrl = String(env.STK_CALLBACK_URL);
  const expectedCallback = new URL(callbackUrl);
  if (!expectedCallback.pathname.endsWith("/hooks/stk/result/" + env.STK_CALLBACK_TOKEN)) {
    throw new HttpError("STK_CALLBACK_URL path must end with /hooks/stk/result/<STK_CALLBACK_TOKEN>.", 500);
  }
  const host = env.DARAJA_ENV === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
  const accessToken = await darajaAccessToken(env, merchant);
  const accountReference = "SNVERIFY" + crypto.randomUUID().replace(/-/g, "").slice(0, 5).toUpperCase();
  const payload = {
    BusinessShortCode: merchant.businessShortCode,
    Password: btoa(merchant.businessShortCode + merchant.passkey + timestamp),
    Timestamp: timestamp,
    TransactionType: merchant.accountType === "till" ? "CustomerBuyGoodsOnline" : "CustomerPayBillOnline",
    Amount: amount,
    PartyA: phone,
    PartyB: merchant.accountType === "till" ? merchant.tillNumber : merchant.businessShortCode,
    PhoneNumber: phone,
    CallBackURL: callbackUrl,
    AccountReference: accountReference,
    TransactionDesc: "SkyNest verify",
  };
  const response = await fetch(host + "/mpesa/stkpush/v1/processrequest", {
    method: "POST",
    headers: { authorization: "Bearer " + accessToken, "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.ResponseCode !== "0" || !data.CheckoutRequestID) {
    throw new HttpError(data.errorMessage || data.ResponseDescription || "Safaricom did not accept the verification prompt.", 502);
  }
  const checkoutId = String(data.CheckoutRequestID);
  const pending = {
    checkoutRequestId: checkoutId,
    merchantRequestId: String(data.MerchantRequestID || ""),
    tenantId: uid,
    tenantName: String(profile.displayName || "Landlord"),
    landlordId: uid,
    createdBy: uid,
    amountKes: amount,
    phone,
    accountReference,
    purpose: "account_verification",
    accountUpdatedAt: accountMeta.updatedAt || "",
    status: "pending",
    method: "MPESA",
    createdAt: { __firestoreTimestamp: new Date() },
  };
  const created = await createDocument(env, "mpesaPaymentRequests", checkoutId, pending);
  if (created.status === 409) throw new HttpError("Verification checkout already exists. Please retry.", 409);
  const early = await firestore(env, "mpesaCallbackInbox/" + encodeURIComponent(checkoutId));
  if (early.status !== 404) {
    const callbackJson = decodeFields(early.data.fields).payloadJson;
    if (callbackJson) {
      await settleCallback(env, JSON.parse(callbackJson), pending);
      await firestore(env, "mpesaCallbackInbox/" + encodeURIComponent(checkoutId), { method: "DELETE" });
    }
  }
  return json({ accepted: true, purpose: "account_verification", checkoutRequestId: checkoutId,
    message: data.CustomerMessage || "Approve the KES 1 verification payment on your phone. It will not be recorded as rent." });
}

async function requestStkPush(request, env) {
  assertConfiguration(env);
  const uid = await verifyFirebaseUser(request, env);
  let input;
  try { input = await request.json(); } catch { throw new HttpError("Request body must be valid JSON."); }
  const amount = Number(input.amountKes);
  if (!Number.isSafeInteger(amount) || amount < 1 || amount > 150000) {
    throw new HttpError("Amount must be a whole number between KES 1 and KES 150,000.");
  }
  const phone = normalizePhone(input.phone);
  const profileResult = await firestore(env, "users/" + encodeURIComponent(uid));
  if (profileResult.status === 404) throw new HttpError("SkyNest tenant profile was not found.", 403);
  const profile = decodeFields(profileResult.data.fields);
  const role = String(profile.role || "").trim().toLowerCase();
  const accountStatus = String(profile.status || "").trim().toLowerCase();
  if (role !== "tenant" || accountStatus !== "active" || !profile.landlordId) {
    throw new HttpError("Only an active tenant linked to a landlord can pay rent.", 403);
  }

  const landlordResult = await firestore(env, "users/" + encodeURIComponent(String(profile.landlordId)));
  if (landlordResult.status === 404) throw new HttpError("The linked landlord account was not found.", 403);
  const landlordProfile = decodeFields(landlordResult.data.fields);
  if (String(landlordProfile.role || "").toLowerCase() !== "landlord" ||
      String(landlordProfile.status || "").toLowerCase() !== "active") {
    throw new HttpError("The linked landlord account is not active. Contact SkyNest support.", 403);
  }
  const accountResult = await firestore(env, "landlordPaymentAccounts/" + encodeURIComponent(String(profile.landlordId)));
  if (accountResult.status === 404) throw new HttpError("Your landlord has not configured an M-Pesa receiving account yet.", 409);
  const accountMeta = decodeFields(accountResult.data.fields);
  if (accountMeta.status !== "verified" || accountMeta.verifiedEnvironment !== String(env.DARAJA_ENV || "sandbox")) {
    throw new HttpError("Your landlord's M-Pesa account is not verified for the current " + String(env.DARAJA_ENV || "sandbox") + " environment. Ask the landlord to verify it in SkyNest.", 409);
  }
  const merchant = await decryptLandlordConfig(env, accountMeta.encryptedConfig);
  const host = env.DARAJA_ENV === "production" ? "https://api.safaricom.co.ke" : "https://sandbox.safaricom.co.ke";
  const timestamp = darajaTimestamp();
  const callbackUrl = String(env.STK_CALLBACK_URL);
  const expectedCallback = new URL(callbackUrl);
  if (!expectedCallback.pathname.endsWith("/hooks/stk/result/" + env.STK_CALLBACK_TOKEN)) {
    throw new HttpError("STK_CALLBACK_URL path must end with /hooks/stk/result/<STK_CALLBACK_TOKEN>.", 500);
  }
  const accessToken = await darajaAccessToken(env, merchant);
  const accountReference = "SN" + crypto.randomUUID().replace(/-/g, "").slice(0, 10).toUpperCase();
  const payload = {
    BusinessShortCode: merchant.businessShortCode,
    Password: btoa(merchant.businessShortCode + merchant.passkey + timestamp),
    Timestamp: timestamp,
    TransactionType: merchant.accountType === "till" ? "CustomerBuyGoodsOnline" : "CustomerPayBillOnline",
    Amount: amount,
    PartyA: phone,
    PartyB: merchant.accountType === "till" ? merchant.tillNumber : merchant.businessShortCode,
    PhoneNumber: phone,
    CallBackURL: callbackUrl,
    AccountReference: accountReference,
    TransactionDesc: "SkyNest rent",
  };
  const response = await fetch(host + "/mpesa/stkpush/v1/processrequest", {
    method: "POST",
    headers: { authorization: "Bearer " + accessToken, "content-type": "application/json" },
    body: JSON.stringify(payload),
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok || data.ResponseCode !== "0" || !data.CheckoutRequestID) {
    throw new HttpError(data.errorMessage || data.ResponseDescription || "Safaricom did not accept the STK Push request.", 502);
  }

  const checkoutId = String(data.CheckoutRequestID);
  if (!/^[A-Za-z0-9_-]{5,160}$/.test(checkoutId)) throw new HttpError("Safaricom returned an invalid checkout reference.", 502);
  const pendingFields = {
    checkoutRequestId: checkoutId,
    merchantRequestId: String(data.MerchantRequestID || ""),
    tenantId: uid,
    tenantName: String(profile.displayName || ""),
    landlordId: String(profile.landlordId),
    createdBy: String(profile.landlordId),
    houseId: String(profile.houseId || ""),
    houseNo: String(profile.houseNo || ""),
    amountKes: amount,
    phone,
    accountReference,
    status: "pending",
    method: "MPESA",
    createdAt: { __firestoreTimestamp: new Date() },
  };
  const created = await createDocument(env, "mpesaPaymentRequests", checkoutId, pendingFields);
  if (created.status === 409) throw new HttpError("This M-Pesa checkout reference already exists. Contact support before retrying.", 409);

  // Safaricom can call back very quickly. If the callback arrived before the
  // pending record was written, it is parked in mpesaCallbackInbox and replayed here.
  const early = await firestore(env, "mpesaCallbackInbox/" + encodeURIComponent(checkoutId));
  if (early.status !== 404) {
    const callback = decodeFields(early.data.fields).payloadJson;
    if (callback) {
      await settleCallback(env, JSON.parse(callback), pendingFields);
      await firestore(env, "mpesaCallbackInbox/" + encodeURIComponent(checkoutId), { method: "DELETE" });
    }
  }
  return json({
    accepted: true,
    message: data.CustomerMessage || "Check your phone and enter your M-Pesa PIN.",
    checkoutRequestId: checkoutId,
  });
}
async function settleCallback(env, body, knownPending = null) {
  const callback = body?.Body?.stkCallback;
  if (!callback?.CheckoutRequestID) return;
  const checkoutId = String(callback.CheckoutRequestID);
  const pendingResult = knownPending
    ? { status: 200, data: { fields: encodeFields(knownPending) } }
    : await firestore(env, "mpesaPaymentRequests/" + encodeURIComponent(checkoutId));
  if (pendingResult.status === 404) {
    await createDocument(env, "mpesaCallbackInbox", checkoutId, {
      payloadJson: JSON.stringify(body),
      receivedAt: { __firestoreTimestamp: new Date() },
    });
    return;
  }
  const pending = knownPending || decodeFields(pendingResult.data.fields);
  if (pending.checkoutRequestId !== checkoutId) return;
  if (!pending.merchantRequestId ||
      !callback.MerchantRequestID ||
      String(callback.MerchantRequestID) !== String(pending.merchantRequestId)) return;
  if (["confirmed", "failed"].includes(pending.status)) return;
  if (pending.status !== "pending") return;

  const successful = Number(callback.ResultCode) === 0;
  const metadata = {};
  for (const item of callback.CallbackMetadata?.Item || []) metadata[item.Name] = item.Value;
  if (successful) {
    const { receipt, paidAmount, paidPhone } = validateSuccessfulCallback(pending, metadata);
    if (pending.purpose === "account_verification") {
      if (pending.landlordId !== pending.tenantId) throw new HttpError("Invalid landlord verification request.", 403);
      const currentAccount = await firestore(env, "landlordPaymentAccounts/" + encodeURIComponent(pending.landlordId));
      if (currentAccount.status === 404) throw new HttpError("Landlord account was removed during verification.", 409);
      const currentAccountFields = decodeFields(currentAccount.data.fields);
      if (String(currentAccountFields.updatedAt || "") !== String(pending.accountUpdatedAt || "")) {
        throw new HttpError("Landlord account details changed during verification. Run the verification again.", 409);
      }
      await patchDocument(env, "landlordPaymentAccounts/" + encodeURIComponent(pending.landlordId), {
        status: "verified",
        verifiedAt: { __firestoreTimestamp: new Date() },
        verificationReceipt: receipt,
        verificationPhone: paidPhone,
        verifiedEnvironment: String(env.DARAJA_ENV || "sandbox"),
      });
    } else {
      const payment = {
        tenantId: pending.tenantId,
        tenantName: pending.tenantName || "Tenant",
        landlordId: pending.landlordId,
        createdBy: pending.landlordId,
        houseId: pending.houseId || "",
        houseNo: pending.houseNo || "",
        amount: paidAmount,
        method: "MPESA",
        transactionCode: receipt,
        mpesaReceipt: receipt,
        status: "Paid",
        confirmedBy: "safaricom_callback",
        checkoutRequestId: checkoutId,
        phone: paidPhone,
        createdAt: { __firestoreTimestamp: new Date() },
        confirmedAt: { __firestoreTimestamp: new Date() },
      };
      const paymentCreated = await createDocument(env, "payments", receipt, payment);
      if (paymentCreated.status === 409) {
        const existing = await firestore(env, "payments/" + encodeURIComponent(receipt));
        const existingFields = decodeFields(existing.data.fields);
        if (existingFields.checkoutRequestId !== checkoutId) {
          throw new HttpError("M-Pesa receipt is already linked to another payment. Manual review required.", 409);
        }
      }
    }
  }
  await patchDocument(env, "mpesaPaymentRequests/" + encodeURIComponent(checkoutId), {
    status: successful ? "confirmed" : "failed",
    resultCode: Number(callback.ResultCode),
    resultDescription: String(callback.ResultDesc || ""),
    mpesaReceipt: String(metadata.MpesaReceiptNumber || ""),
    updatedAt: { __firestoreTimestamp: new Date() },
  });
}
async function handleCallback(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ ResultCode: 0, ResultDesc: "Accepted" }); }
  await settleCallback(env, body);
  return json({ ResultCode: 0, ResultDesc: "Accepted" });
}
export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, {
      status: 204,
      headers: {
        "access-control-allow-origin": "*",
        "access-control-allow-methods": "GET,POST,OPTIONS",
        "access-control-allow-headers": "authorization,content-type",
      },
    });
    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") {
        return json({ ok: true, service: "skynest-mpesa", environment: env.DARAJA_ENV || "sandbox" });
      }
      if (request.method === "GET" && url.pathname === "/api/mpesa/account") {
        return await getLandlordPaymentAccount(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/mpesa/account") {
        return await saveLandlordPaymentAccount(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/mpesa/account/verify") {
        return await verifyLandlordPaymentAccount(request, env);
      }
      if (request.method === "POST" && url.pathname === "/api/mpesa/stkpush") {
        return await requestStkPush(request, env);
      }
      if (request.method === "POST" && url.pathname === "/hooks/stk/result/" + env.STK_CALLBACK_TOKEN) {
        assertConfiguration(env);
        return await handleCallback(request, env);
      }
      return json({ error: "Not found" }, 404);
    } catch (error) {
      const status = error instanceof HttpError ? error.status : 500;
      return json({ error: error?.message || "Payment service error." }, status);
    }
  },
};
