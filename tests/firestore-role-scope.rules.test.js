import fs from "node:fs";
import { before, after, test } from "node:test";
import assert from "node:assert/strict";
import { initializeTestEnvironment, assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { collection, doc, getDoc, getDocs, query, serverTimestamp, setDoc, updateDoc, where } from "firebase/firestore";

const projectId = "demo-skynest-role-scope";
let env;
const rules = fs.readFileSync(new URL("../firestore.rules", import.meta.url), "utf8");

before(async () => {
  env = await initializeTestEnvironment({ projectId, firestore: { rules } });
});
after(async () => env.cleanup());

async function seed() {
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "users", "caretaker-1"), {
      role: "caretaker", status: "active", landlordId: "landlord-1",
      caretakerPermission: "can_collect", propertyIds: ["house-assigned"]
    });
    await setDoc(doc(db, "users", "landlord-1"), {
      role: "landlord", status: "active"
    });
    await setDoc(doc(db, "houses", "house-assigned"), {
      createdBy: "landlord-1", landlordId: "landlord-1",
      caretakerIds: ["caretaker-1"]
    });
    await setDoc(doc(db, "houses", "house-other"), {
      createdBy: "landlord-1", landlordId: "landlord-1",
      caretakerIds: ["another-caretaker"]
    });
    await setDoc(doc(db, "tenants", "tenant-other-house"), {
      name: "Private tenant", createdBy: "landlord-1",
      landlordId: "landlord-1", houseId: "house-other"
    });
    await setDoc(doc(db, "paymentConfirmations", "confirmation-assigned"), {
      landlordId: "landlord-1", caretakerId: "caretaker-1",
      houseId: "house-assigned", paymentId: "payment-1",
      tenantName: "Assigned tenant", houseNo: "A1",
      status: "pending", createdAt: new Date()
    });
    await setDoc(doc(db, "paymentConfirmations", "confirmation-other"), {
      landlordId: "landlord-1", caretakerId: "caretaker-1",
      houseId: "house-other", paymentId: "payment-2",
      tenantName: "Other tenant", houseNo: "B1",
      status: "pending", createdAt: new Date()
    });
  });
}

test("caretaker can create tenant record only for a house assigned by the linked landlord", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  await assertSucceeds(setDoc(doc(db, "tenants", "new-assigned"), {
    name: "Assigned tenant", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-assigned"
  }));
  await assertFails(setDoc(doc(db, "tenants", "new-unassigned"), {
    name: "Unassigned tenant", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-other"
  }));
  await assertFails(setDoc(doc(db, "tenants", "spoof-landlord"), {
    name: "Spoofed landlord", createdBy: "caretaker-1",
    landlordId: "another-landlord", houseId: "house-assigned"
  }));
});

test("caretaker cannot read tenant records in an unassigned house", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  await assertFails(getDoc(doc(db, "tenants", "tenant-other-house")));
});

test("landlord retains access to own tenant records", async () => {
  await seed();
  const db = env.authenticatedContext("landlord-1").firestore();
  await assertSucceeds(getDoc(doc(db, "tenants", "tenant-other-house")));
});


test("caretaker confirmation query and update remain restricted to assigned houses and can_collect", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  const broadQuery = query(
    collection(db, "paymentConfirmations"),
    where("caretakerId", "==", "caretaker-1")
  );
  await assertFails(getDocs(broadQuery));
  const assignedQuery = query(
    collection(db, "paymentConfirmations"),
    where("caretakerId", "==", "caretaker-1"),
    where("houseId", "==", "house-assigned")
  );
  const results = await assertSucceeds(getDocs(assignedQuery));
  assert.equal(results.size, 1);
  await assertFails(getDoc(doc(db, "paymentConfirmations", "confirmation-other")));
  await assertSucceeds(updateDoc(doc(db, "paymentConfirmations", "confirmation-assigned"), {
    status: "confirmed_by_caretaker",
    confirmedBy: "caretaker-1",
    confirmedAt: serverTimestamp()
  }));
});

test("landlord can create caretaker confirmation only for that caretaker's assigned house", async () => {
  await seed();
  const db = env.authenticatedContext("landlord-1").firestore();
  const valid = {
    landlordId: "landlord-1", caretakerId: "caretaker-1",
    houseId: "house-assigned", paymentId: "payment-3",
    tenantName: "Assigned tenant", houseNo: "A1",
    status: "pending", createdAt: serverTimestamp()
  };
  await assertSucceeds(setDoc(doc(db, "paymentConfirmations", "new-valid"), valid));
  await assertFails(setDoc(doc(db, "paymentConfirmations", "new-invalid"), {
    ...valid, houseId: "house-other"
  }));
});
