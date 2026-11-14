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

test("only custom-claim marketplace admin can approve a pending listing", async () => {
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
