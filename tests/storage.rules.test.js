import fs from "node:fs";
import { before, beforeEach, after, test } from "node:test";
import {
  initializeTestEnvironment, assertFails, assertSucceeds
} from "@firebase/rules-unit-testing";
import { doc, setDoc } from "firebase/firestore";
import { ref, uploadBytes, getBytes } from "firebase/storage";

const projectId = "demo-skynest-marketplace";
let env;
const firestoreRules = fs.readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");
const storageRules = fs.readFileSync(new URL("../storage.rules", import.meta.url), "utf8");

before(async () => {
  env = await initializeTestEnvironment({
    projectId,
    firestore: { rules: firestoreRules },
    storage: { rules: storageRules }
  });
});

beforeEach(async () => {
  await env.clearFirestore();
  await env.clearStorage();
});

after(async () => env.cleanup());

test("profile photo uploads are limited to the account owner", async () => {
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const owner = env.authenticatedContext("alice").storage();
  const stranger = env.authenticatedContext("eve").storage();
  const ownPhoto = ref(owner, "profile_photos/alice/profile.jpg");

  await assertSucceeds(uploadBytes(ownPhoto, image, { contentType: "image/jpeg" }));
  await assertFails(uploadBytes(
    ref(stranger, "profile_photos/alice/profile.jpg"),
    image,
    { contentType: "image/jpeg" }
  ));
});

test("group attachment access requires current group membership", async () => {
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "groups", "group-1"), {
      memberIds: ["alice", "bob"]
    });
  });

  const pdf = new Uint8Array([0x25, 0x50, 0x44, 0x46]);
  const alice = env.authenticatedContext("alice").storage();
  const bob = env.authenticatedContext("bob").storage();
  const eve = env.authenticatedContext("eve").storage();
  const path = "group_attachments/group-1/alice/guide.pdf";

  await assertSucceeds(uploadBytes(ref(alice, path), pdf, { contentType: "application/pdf" }));
  await assertSucceeds(getBytes(ref(bob, path)));
  await assertFails(getBytes(ref(eve, path)));
  await assertFails(uploadBytes(
    ref(eve, "group_attachments/group-1/eve/blocked.pdf"),
    pdf,
    { contentType: "application/pdf" }
  ));
});

test("marketplace media uploads are owner-scoped and public only after approval", async () => {
  const ownerUid = "market-advertiser";
  const listingId = "market-draft";
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", listingId), {
      ownerUid, status: "draft"
    });
  });
  const image = new Uint8Array([0xff, 0xd8, 0xff, 0xd9]);
  const owner = env.authenticatedContext(ownerUid).storage();
  const stranger = env.authenticatedContext("intruder").storage();
  const publicStorage = env.unauthenticatedContext().storage();
  const path = "listing_media/market-advertiser/market-draft/front.jpg";
  await assertSucceeds(uploadBytes(ref(owner, path), image, { contentType: "image/jpeg" }));
  await assertFails(getBytes(ref(stranger, path)));
  await assertFails(getBytes(ref(publicStorage, path)));
  await env.withSecurityRulesDisabled(async (context) => {
    await setDoc(doc(context.firestore(), "publicListings", listingId), {
      ownerUid, status: "approved",
      expiresAt: new Date(Date.now() + 86400000)
    });
  });
  await assertSucceeds(getBytes(ref(publicStorage, path)));
  await assertFails(uploadBytes(
    ref(stranger, "listing_media/market-advertiser/market-draft/intruder.jpg"),
    image,
    { contentType: "image/jpeg" }
  ));
});
