import fs from "node:fs";
import { before, beforeEach, after, test } from "node:test";
import assert from "node:assert/strict";
import {
  initializeTestEnvironment, assertFails, assertSucceeds
} from "@firebase/rules-unit-testing";
import {
  collection, deleteDoc, deleteField, doc, getDoc, serverTimestamp, setDoc, updateDoc, Timestamp
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

test("landlords can edit pamphlet content without changing ownership", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "landlord-1"), {
      role: "landlord",
      status: "active"
    });
    await setDoc(doc(db, "users", "other-landlord"), {
      role: "landlord",
      status: "active"
    });
  });

  const landlord = env.authenticatedContext("landlord-1").firestore();
  const pamphlet = doc(landlord, "pamphlets", "rent-reminder");
  await assertSucceeds(setDoc(pamphlet, {
    title: "Monthly Rent Reminder",
    type: "rentNotice",
    message: "Rent is due on the agreed date.",
    swahiliMessage: "Kodi inapaswa kulipwa kwa wakati.",
    copies: 1,
    landlordId: "landlord-1",
    createdBy: "landlord-1",
    createdAt: serverTimestamp(),
    isPrinted: false
  }));

  await assertSucceeds(updateDoc(pamphlet, {
    isPrinted: true,
    printedAt: serverTimestamp()
  }));
  await assertSucceeds(updateDoc(pamphlet, {
    title: "Updated Rent Reminder",
    type: "rentNotice",
    message: "Please pay rent by the agreed date and keep your receipt.",
    swahiliMessage: "Tafadhali lipa kodi kwa tarehe tuliyokubaliana.",
    copies: 2,
    isPrinted: false,
    printedAt: deleteField()
  }));

  const saved = await getDoc(pamphlet);
  assert.equal(saved.data().title, "Updated Rent Reminder");
  assert.equal(saved.data().copies, 2);
  assert.equal(saved.data().isPrinted, false);
  assert.equal("printedAt" in saved.data(), false);

  await assertFails(updateDoc(pamphlet, { landlordId: "other-landlord" }));
  await assertFails(updateDoc(pamphlet, { copies: 501 }));
  await assertFails(updateDoc(pamphlet, { type: "unrestricted" }));

  const other = env.authenticatedContext("other-landlord").firestore();
  await assertFails(updateDoc(doc(other, "pamphlets", "rent-reminder"), {
    title: "Attempted takeover"
  }));
});

test("Recycle Bin is private to its owning active Landlord", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "landlord-1"), { role: "landlord", status: "active" });
    await setDoc(doc(db, "users", "landlord-2"), { role: "landlord", status: "active" });
    await setDoc(doc(db, "users", "caretaker-1"), { role: "caretaker", status: "active", landlordId: "landlord-1" });
  });

  const record = {
    ownerId: "landlord-1",
    originalCollection: "houses",
    originalId: "house-1",
    recordType: "House",
    title: "House A1",
    originalData: { createdBy: "landlord-1", landlordId: "landlord-1", houseNo: "A1" },
    deletedAt: serverTimestamp()
  };
  const owner = env.authenticatedContext("landlord-1").firestore();
  const other = env.authenticatedContext("landlord-2").firestore();
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  const item = doc(owner, "recycleBin", "item-1");

  await assertSucceeds(setDoc(item, record));
  await assertSucceeds(getDoc(item));
  await assertFails(getDoc(doc(other, "recycleBin", "item-1")));
  await assertFails(setDoc(doc(other, "recycleBin", "forged"), {
    ...record, ownerId: "landlord-1"
  }));
  await assertFails(setDoc(doc(caretaker, "recycleBin", "caretaker-item"), {
    ...record, ownerId: "caretaker-1",
    originalData: { createdBy: "caretaker-1" }
  }));
  await assertFails(deleteDoc(doc(other, "recycleBin", "item-1")));
  await assertSucceeds(deleteDoc(item));
});


test("scheduled automations are restricted to their active Landlord owner", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "landlord-automation-1"), {
      role: "landlord", status: "active"
    });
    await setDoc(doc(db, "users", "landlord-automation-2"), {
      role: "landlord", status: "active"
    });
    await setDoc(doc(db, "users", "inactive-landlord"), {
      role: "landlord", status: "suspended"
    });
  });

  const owner = env.authenticatedContext("landlord-automation-1").firestore();
  const other = env.authenticatedContext("landlord-automation-2").firestore();
  const inactive = env.authenticatedContext("inactive-landlord").firestore();
  const reminder = {
    ownerId: "landlord-automation-1",
    title: "Monthly rent reminder",
    message: "Check rent collection for this month.",
    frequency: "monthly",
    nextRunAt: Timestamp.fromDate(new Date(Date.now() + 86400000)),
    enabled: true,
    createdAt: serverTimestamp(),
    updatedAt: serverTimestamp(),
    attemptCount: 0
  };

  const ref = doc(owner, "automations", "rent-reminder");
  await assertSucceeds(setDoc(ref, reminder));
  await assertSucceeds(getDoc(ref));
  await assertFails(getDoc(doc(other, "automations", "rent-reminder")));
  await assertFails(getDoc(doc(inactive, "automations", "rent-reminder")));

  await assertSucceeds(updateDoc(ref, {
    enabled: false,
    updatedAt: serverTimestamp()
  }));
  await assertFails(updateDoc(doc(other, "automations", "rent-reminder"), {
    enabled: false,
    updatedAt: serverTimestamp()
  }));
  await assertFails(updateDoc(ref, {
    ownerId: "landlord-automation-2",
    updatedAt: serverTimestamp()
  }));

  await assertSucceeds(deleteDoc(ref));
  await assertFails(setDoc(doc(other, "automations", "forged-reminder"), {
    ...reminder,
    ownerId: "landlord-automation-1"
  }));
});


test("activity audit entries are owner-scoped and cannot be forged for another actor", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "audit-landlord-1"), {
      role: "landlord", status: "active"
    });
    await setDoc(doc(db, "users", "audit-landlord-2"), {
      role: "landlord", status: "active"
    });
  });

  const owner = env.authenticatedContext("audit-landlord-1").firestore();
  const other = env.authenticatedContext("audit-landlord-2").firestore();
  const entry = {
    landlordId: "audit-landlord-1",
    actorId: "audit-landlord-1",
    actorName: "Landlord",
    actorRole: "landlord",
    action: "Permanently deleted House: A1",
    isSuspicious: true,
    createdAt: serverTimestamp()
  };

  await assertSucceeds(setDoc(doc(owner, "activityLogs", "audit-1"), entry));
  await assertSucceeds(getDoc(doc(owner, "activityLogs", "audit-1")));
  await assertFails(getDoc(doc(other, "activityLogs", "audit-1")));
  await assertFails(setDoc(doc(other, "activityLogs", "forged-audit"), {
    ...entry,
    actorId: "audit-landlord-1"
  }));
  await assertFails(updateDoc(doc(owner, "activityLogs", "audit-1"), {
    action: "Changed audit history"
  }));
  await assertFails(deleteDoc(doc(owner, "activityLogs", "audit-1")));
});
