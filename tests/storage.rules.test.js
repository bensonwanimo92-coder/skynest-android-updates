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
