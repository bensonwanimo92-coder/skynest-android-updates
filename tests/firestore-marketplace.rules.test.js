import fs from "node:fs";
import { before, beforeEach, after, test } from "node:test";
import assert from "node:assert/strict";
import {
  initializeTestEnvironment, assertFails, assertSucceeds
} from "@firebase/rules-unit-testing";
import {
  collection, doc, getDoc, serverTimestamp, setDoc, updateDoc, Timestamp
} from "firebase/firestore";

const projectId = "demo-skynest-marketplace";
let env;
const rules = fs.readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules }
  });
});
beforeEach(async () => env.clearFirestore());
after(async () => env.cleanup());

function listing(overrides = {}) {
  return {
    ownerUid: "advertiser-1",
    title: "Two bedroom apartment near town",
    category: "Residential",
    advertType: "For rent",
    county: "Nairobi",
    town: "Westlands",
    price: 28000,
    currency: "KES",
    description: "Bright two bedroom apartment with secure parking and water.",
    contactPhone: "+254700000000",
    photoUrls: [],
    status: "draft",
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    ...overrides
  };
}

test("verified advertiser can create own draft but cannot self-publish", async () => {
  const db = env.authenticatedContext("advertiser-1", { email_verified: true }).firestore();
  await assertSucceeds(setDoc(doc(db, "publicListings", "draft-1"), listing()));
  await assertFails(setDoc(doc(db, "publicListings", "bad-1"), listing({
    status: "approved",
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 86400000))
  })));
});

test("unverified advertiser cannot create listings", async () => {
  const db = env.authenticatedContext("advertiser-2", { email_verified: false }).firestore();
  await assertFails(setDoc(doc(db, "publicListings", "draft-2"), listing({
    ownerUid: "advertiser-2"
  })));
});

test("advertiser cannot read another user's private draft", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", "private-draft"), listing());
  });
  const stranger = env.authenticatedContext("stranger").firestore();
  await assertFails(getDoc(doc(stranger, "publicListings", "private-draft")));
});

test("public visitors can read approved unexpired listings only", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "publicListings", "live"), listing({
      status: "approved",
      expiresAt: Timestamp.fromDate(new Date(Date.now() + 86400000))
    }));
    await setDoc(doc(db, "publicListings", "expired"), listing({
      status: "approved",
      expiresAt: Timestamp.fromDate(new Date(Date.now() - 86400000))
    }));
    await setDoc(doc(db, "publicListings", "pending"), listing({ status: "pending" }));
  });
  const publicDb = env.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(publicDb, "publicListings", "live")));
  await assertFails(getDoc(doc(publicDb, "publicListings", "expired")));
  await assertFails(getDoc(doc(publicDb, "publicListings", "pending")));
});

test("custom-claim marketplace admin can approve a pending listing", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", "pending-1"), listing({ status: "pending" }));
  });
  const ordinary = env.authenticatedContext("ordinary-user", { email_verified: true }).firestore();
  await assertFails(updateDoc(doc(ordinary, "publicListings", "pending-1"), {
    status: "approved",
    reviewedAt: serverTimestamp(),
    reviewedBy: "ordinary-user",
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 86400000))
  }));

  const admin = env.authenticatedContext("admin-uid", {
    email_verified: true,
    marketplaceAdmin: true
  }).firestore();
  await assertSucceeds(updateDoc(doc(admin, "publicListings", "pending-1"), {
    status: "approved",
    reviewedAt: serverTimestamp(),
    reviewedBy: "admin-uid",
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 86400000))
  }));
});


test("pinned verified initial administrator can moderate on Spark without custom claims", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", "spark-pending"), listing({ status: "pending" }));
  });
  const uid = "PN9bC3ZzgSaOK1JjG4TcjCU9Grx1";
  const admin = env.authenticatedContext(uid, {
    email: "bensonwanimo92@gmail.com",
    email_verified: true
  }).firestore();
  await assertSucceeds(updateDoc(doc(admin, "publicListings", "spark-pending"), {
    status: "approved",
    reviewedAt: serverTimestamp(),
    reviewedBy: uid,
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 86400000))
  }));
});

test("pinned initial administrator identity cannot be impersonated with a different UID or email", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", "protected-pending"), listing({ status: "pending" }));
  });
  const sameEmailWrongUid = env.authenticatedContext("not-the-admin", {
    email: "bensonwanimo92@gmail.com",
    email_verified: true
  }).firestore();
  const sameUidWrongEmail = env.authenticatedContext("PN9bC3ZzgSaOK1JjG4TcjCU9Grx1", {
    email: "attacker@example.com",
    email_verified: true
  }).firestore();
  const unverified = env.authenticatedContext("PN9bC3ZzgSaOK1JjG4TcjCU9Grx1", {
    email: "bensonwanimo92@gmail.com",
    email_verified: false
  }).firestore();
  const change = {
    status: "approved",
    reviewedAt: serverTimestamp(),
    reviewedBy: "PN9bC3ZzgSaOK1JjG4TcjCU9Grx1",
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 86400000))
  };
  await assertFails(updateDoc(doc(sameEmailWrongUid, "publicListings", "protected-pending"), change));
  await assertFails(updateDoc(doc(sameUidWrongEmail, "publicListings", "protected-pending"), change));
  await assertFails(updateDoc(doc(unverified, "publicListings", "protected-pending"), change));
});

test("public marketplace rules do not expose private SkyNest house records", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "houses", "private-house"), {
      createdBy: "landlord-uid",
      rent: 25000,
      tenantName: "Private tenant"
    });
  });
  const publicDb = env.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(publicDb, "houses", "private-house")));
});


test("private direct messages allow participant bootstrap and deny outsiders", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    for (const uid of ["alice", "bob", "eve"]) {
      await setDoc(doc(db, "users", uid), {
        displayName: uid,
        role: "landlord",
        status: "active"
      });
    }
  });

  const alice = env.authenticatedContext("alice").firestore();
  const bob = env.authenticatedContext("bob").firestore();
  const eve = env.authenticatedContext("eve").firestore();
  const conversationId = "alice__bob";
  const conversation = doc(alice, "directConversations", conversationId);

  // The participant can safely check the deterministic document before it exists.
  await assertSucceeds(getDoc(conversation));
  await assertSucceeds(setDoc(conversation, {
    participantIds: ["alice", "bob"],
    participantNames: { alice: "Alice", bob: "Bob" },
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp()
  }));
  await assertSucceeds(getDoc(doc(bob, "directConversations", conversationId)));
  await assertFails(getDoc(doc(eve, "directConversations", conversationId)));

  const encryptedMessage = {
    encryptionVersion: 1,
    encryptionAlgorithm: "X25519-HKDF-SHA256-AES-256-GCM",
    senderPublicKey: "public-key",
    nonce: "nonce",
    ciphertext: "ciphertext",
    mac: "mac",
    keyEnvelopes: { alice: "wrapped-key-a", bob: "wrapped-key-b" },
    senderId: "alice",
    senderName: "Alice",
    createdAt: serverTimestamp()
  };
  await assertSucceeds(setDoc(
    doc(alice, "directConversations", conversationId, "messages", "message-1"),
    encryptedMessage
  ));
  await assertFails(setDoc(
    doc(eve, "directConversations", conversationId, "messages", "message-2"),
    { ...encryptedMessage, senderId: "eve" }
  ));
});

test("verified advertiser can create multi-category vehicle advert with structured details and media metadata", async () => {
  const db = env.authenticatedContext("vehicle-advertiser", { email_verified: true }).firestore();
  await assertSucceeds(setDoc(doc(db, "publicListings", "vehicle-draft"), listing({
    ownerUid: "vehicle-advertiser",
    title: "Low mileage Toyota Harrier in excellent condition",
    category: "Vehicles",
    advertType: "For sale",
    details: { make: "Toyota", model: "Harrier", yearMade: 2020, mileage: 42000 },
    media: [{ kind: "image", storagePath: "listing_media/vehicle-advertiser/vehicle-draft/front.jpg", contentType: "image/jpeg", size: 1000 }],
    photoUrls: ["https://example.invalid/front.jpg"],
    videoUrls: ["https://example.invalid/walkaround.mp4"]
  })));
});

test("advertisers cannot assign themselves premium or standard tiers", async () => {
  const db = env.authenticatedContext("tier-advertiser", { email_verified: true }).firestore();
  await assertFails(setDoc(doc(db, "publicListings", "self-premium"), listing({
    ownerUid: "tier-advertiser",
    advertiserTier: "premium"
  })));
  await assertSucceeds(setDoc(doc(db, "publicListings", "tier-draft"), listing({
    ownerUid: "tier-advertiser"
  })));
  await assertFails(updateDoc(doc(db, "publicListings", "tier-draft"), {
    advertiserTier: "standard",
    updatedAt: serverTimestamp()
  }));
});

test("admin can request changes and assign a premium tier only during approval", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", "review-me"), listing({ status: "pending" }));
  });
  const uid = "PN9bC3ZzgSaOK1JjG4TcjCU9Grx1";
  const admin = env.authenticatedContext(uid, {
    email: "bensonwanimo92@gmail.com",
    email_verified: true
  }).firestore();
  await assertSucceeds(updateDoc(doc(admin, "publicListings", "review-me"), {
    status: "changes_requested",
    rejectionReason: "Please add clearer exterior photos.",
    reviewedAt: serverTimestamp(),
    reviewedBy: uid,
    updatedAt: serverTimestamp()
  }));
  const advertiser = env.authenticatedContext("advertiser-1", { email_verified: true }).firestore();
  await assertSucceeds(updateDoc(doc(advertiser, "publicListings", "review-me"), {
    status: "pending",
    submittedAt: serverTimestamp(),
    updatedAt: serverTimestamp()
  }));
  await assertSucceeds(updateDoc(doc(admin, "publicListings", "review-me"), {
    status: "approved",
    advertiserTier: "premium",
    reviewedAt: serverTimestamp(),
    reviewedBy: uid,
    updatedAt: serverTimestamp(),
    expiresAt: Timestamp.fromDate(new Date(Date.now() + 30 * 86400000))
  }));
});

test("moderation audit log is append-only and administrator-only", async () => {
  const uid = "PN9bC3ZzgSaOK1JjG4TcjCU9Grx1";
  const entry = {
    listingId: "listing-1",
    ownerUid: "advertiser-1",
    action: "approved",
    reason: "Verified details and media.",
    advertiserTier: "premium",
    actorUid: uid,
    actorEmail: "bensonwanimo92@gmail.com",
    createdAt: serverTimestamp()
  };
  const admin = env.authenticatedContext(uid, {
    email: "bensonwanimo92@gmail.com",
    email_verified: true
  }).firestore();
  const advertiser = env.authenticatedContext("advertiser-1", { email_verified: true }).firestore();
  await assertSucceeds(setDoc(doc(admin, "marketplaceModerationLogs", "audit-1"), entry));
  await assertFails(setDoc(doc(advertiser, "marketplaceModerationLogs", "audit-2"), {
    ...entry, actorUid: "advertiser-1"
  }));
  await assertFails(updateDoc(doc(admin, "marketplaceModerationLogs", "audit-1"), {
    reason: "Changed after the fact."
  }));
});
