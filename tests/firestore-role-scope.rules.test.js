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
    await setDoc(doc(db, "users", "tenant-1"), {
      role: "tenant", status: "active", landlordId: "landlord-1",
      houseId: "house-assigned", houseNo: "A1"
    });
    await setDoc(doc(db, "houses", "house-assigned"), {
      createdBy: "landlord-1", landlordId: "landlord-1",
      caretakerIds: ["caretaker-1"], houseNo: "A1", rent: 15000, assignedTenantId: "tenant-1"
    });
    await setDoc(doc(db, "houses", "house-other"), {
      createdBy: "landlord-1", landlordId: "landlord-1",
      caretakerIds: ["another-caretaker"], houseNo: "B1", rent: 20000
    });
    await setDoc(doc(db, "tenants", "tenant-other-house"), {
      name: "Private tenant", createdBy: "landlord-1",
      landlordId: "landlord-1", houseId: "house-other"
    });
    await setDoc(doc(db, "payments", "tenant-own-payment"), {
      createdBy: "landlord-1", landlordId: "landlord-1", tenantId: "tenant-1",
      houseId: "house-assigned", houseNo: "A1", amount: 5000, status: "Paid"
    });
    await setDoc(doc(db, "payments", "another-tenant-payment"), {
      createdBy: "landlord-1", landlordId: "landlord-1", tenantId: "another-tenant",
      houseId: "house-other", houseNo: "B1", amount: 7000, status: "Paid"
    });
    await setDoc(doc(db, "payments", "payment-without-tenant-link"), {
      createdBy: "landlord-1", landlordId: "landlord-1",
      houseId: "house-assigned", houseNo: "A1", amount: 3000, status: "Paid"
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
    await setDoc(doc(db, "houseRequests", "request-assigned"), {
      tenantId: "tenant-1", landlordId: "landlord-1",
      houseId: "house-assigned", houseNo: "A1", status: "pending"
    });
    await setDoc(doc(db, "houseRequests", "request-other"), {
      tenantId: "another-tenant", landlordId: "landlord-1",
      houseId: "house-other", houseNo: "B1", status: "pending"
    });
  });
}

test("tenant can read only their own assigned house", async () => {
  await seed();
  const db = env.authenticatedContext("tenant-1").firestore();
  await assertSucceeds(getDoc(doc(db, "houses", "house-assigned")));
  await assertFails(getDoc(doc(db, "houses", "house-other")));
});

test("caretaker can create tenant record only for a house assigned by the linked landlord", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  await assertSucceeds(setDoc(doc(db, "tenants", "new-assigned"), {
    name: "Assigned tenant", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-assigned",
    houseNo: "A1", rentAmount: 15000
  }));
  await assertFails(setDoc(doc(db, "tenants", "new-unassigned"), {
    name: "Unassigned tenant", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-other",
    houseNo: "B1", rentAmount: 20000
  }));
  await assertFails(setDoc(doc(db, "tenants", "spoof-landlord"), {
    name: "Spoofed landlord", createdBy: "caretaker-1",
    landlordId: "another-landlord", houseId: "house-assigned",
    houseNo: "A1", rentAmount: 15000
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
    where("landlordId", "==", "landlord-1"),
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

test("caretaker cannot forge the assigned house number or monthly rent", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  await assertFails(setDoc(doc(db, "tenants", "forged-rent"), {
    name: "Forged rent", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-assigned",
    houseNo: "A1", rentAmount: 1
  }));
  await assertFails(setDoc(doc(db, "tenants", "forged-house"), {
    name: "Forged house", createdBy: "caretaker-1",
    landlordId: "landlord-1", houseId: "house-assigned",
    houseNo: "B1", rentAmount: 15000
  }));
});


test("landlord payment records must point to a house owned by that landlord", async () => {
  await seed();
  const landlord = env.authenticatedContext("landlord-1").firestore();
  const valid = {
    createdBy: "landlord-1", landlordId: "landlord-1",
    houseId: "house-assigned", houseNo: "A1", amount: 15000,
    status: "Pending verification", method: "CASH"
  };
  await assertSucceeds(setDoc(doc(landlord, "payments", "valid-payment"), valid));
  await assertFails(setDoc(doc(landlord, "payments", "wrong-house"), {
    ...valid, houseId: "house-not-owned"
  }));
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  await assertFails(setDoc(doc(caretaker, "payments", "caretaker-payment"), valid));
});


test("landlord can issue immutable rent invoices only for an active assigned tenant and house", async () => {
  await seed();
  const db = env.authenticatedContext("landlord-1").firestore();
  const valid = {
    landlordId: "landlord-1", createdBy: "landlord-1", tenantId: "tenant-1",
    tenantName: "Tenant One", houseId: "house-assigned", houseNo: "A1",
    period: "2026-11", amountDueKes: 15000, rentAtIssue: 15000,
    status: "issued", createdAt: serverTimestamp()
  };
  await assertSucceeds(setDoc(doc(db, "rentInvoices", "tenant-1_house-assigned_2026-11"), valid));
  await assertFails(setDoc(doc(db, "rentInvoices", "wrong-house-invoice"), {
    ...valid, houseId: "house-other", houseNo: "B1"
  }));
  await assertFails(setDoc(doc(db, "rentInvoices", "wrong-tenant-invoice"), {
    ...valid, tenantId: "another-tenant"
  }));
});

test("tenant can read only their own rent invoices and invoices cannot be edited", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "rentInvoices", "tenant-own-invoice"), {
      landlordId: "landlord-1", tenantId: "tenant-1", houseId: "house-assigned",
      houseNo: "A1", period: "2026-11", amountDueKes: 15000, rentAtIssue: 15000,
      status: "issued", createdBy: "landlord-1", createdAt: new Date()
    });
    await setDoc(doc(db, "rentInvoices", "other-tenant-invoice"), {
      landlordId: "landlord-1", tenantId: "another-tenant", houseId: "house-other",
      houseNo: "B1", period: "2026-11", amountDueKes: 20000, rentAtIssue: 20000,
      status: "issued", createdBy: "landlord-1", createdAt: new Date()
    });
  });
  const tenant = env.authenticatedContext("tenant-1").firestore();
  await assertSucceeds(getDoc(doc(tenant, "rentInvoices", "tenant-own-invoice")));
  await assertFails(getDoc(doc(tenant, "rentInvoices", "other-tenant-invoice")));
  await assertFails(updateDoc(doc(tenant, "rentInvoices", "tenant-own-invoice"), { amountDueKes: 1 }));
});

test("tenant can read only payment records linked to their own UID", async () => {
  await seed();
  const tenant = env.authenticatedContext("tenant-1").firestore();
  await assertSucceeds(getDoc(doc(tenant, "payments", "tenant-own-payment")));
  await assertFails(getDoc(doc(tenant, "payments", "another-tenant-payment")));
  await assertFails(getDoc(doc(tenant, "payments", "payment-without-tenant-link")));
});

test("tenant dashboard invoice and payment queries are restricted to the signed-in tenant", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "rentInvoices", "tenant-own-invoice-query"), {
      landlordId: "landlord-1", tenantId: "tenant-1", houseId: "house-assigned",
      houseNo: "A1", period: "2026-11", amountDueKes: 15000,
      rentAtIssue: 15000, createdBy: "landlord-1", status: "issued",
      createdAt: new Date()
    });
    await setDoc(doc(db, "rentInvoices", "other-tenant-invoice-query"), {
      landlordId: "landlord-1", tenantId: "another-tenant", houseId: "house-other",
      houseNo: "B1", period: "2026-11", amountDueKes: 20000,
      rentAtIssue: 20000, createdBy: "landlord-1", status: "issued",
      createdAt: new Date()
    });
  });
  const tenant = env.authenticatedContext("tenant-1").firestore();
  const ownInvoices = query(
    collection(tenant, "rentInvoices"),
    where("tenantId", "==", "tenant-1")
  );
  const ownInvoiceResults = await assertSucceeds(getDocs(ownInvoices));
  assert.equal(ownInvoiceResults.size, 1);

  const ownPayments = query(
    collection(tenant, "payments"),
    where("tenantId", "==", "tenant-1")
  );
  const ownPaymentResults = await assertSucceeds(getDocs(ownPayments));
  assert.equal(ownPaymentResults.size, 1);
});

test("landlord payment queries remain scoped to their own landlord ID", async () => {
  await seed();
  const landlord = env.authenticatedContext("landlord-1").firestore();
  const ownPayments = query(collection(landlord, "payments"), where("landlordId", "==", "landlord-1"));
  const results = await assertSucceeds(getDocs(ownPayments));
  assert.equal(results.size, 4);
});

test("tenant payment submissions must match the tenant's assigned house and landlord", async () => {
  await seed();
  const tenant = env.authenticatedContext("tenant-1").firestore();
  const valid = {
    tenantId: "tenant-1", landlordId: "landlord-1",
    houseId: "house-assigned", houseNo: "A1",
    amount: 15000, method: "CASH", status: "pending"
  };
  await assertSucceeds(setDoc(doc(tenant, "paymentSubmissions", "valid-submission"), valid));
  await assertFails(setDoc(doc(tenant, "paymentSubmissions", "wrong-house"), {
    ...valid, houseId: "house-other", houseNo: "B1"
  }));
  await assertFails(setDoc(doc(tenant, "paymentSubmissions", "wrong-house-number"), {
    ...valid, houseNo: "B1"
  }));
  await assertFails(setDoc(doc(tenant, "paymentSubmissions", "wrong-landlord"), {
    ...valid, landlordId: "another-landlord"
  }));
});


test("caretaker house requests are restricted to assigned houses and cannot approve them", async () => {
  await seed();
  const db = env.authenticatedContext("caretaker-1").firestore();
  const assigned = query(
    collection(db, "houseRequests"),
    where("landlordId", "==", "landlord-1"),
    where("houseId", "==", "house-assigned")
  );
  const results = await assertSucceeds(getDocs(assigned));
  assert.equal(results.size, 1);
  await assertFails(getDoc(doc(db, "houseRequests", "request-other")));
  await assertFails(updateDoc(doc(db, "houseRequests", "request-assigned"), {
    status: "approved", reviewedBy: "caretaker-1", reviewedAt: serverTimestamp()
  }));
});

test("only landlord can change a tenant's house assignment", async () => {
  await seed();
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  await assertFails(updateDoc(doc(caretaker, "users", "tenant-1"), {
    houseId: "house-other", houseNo: "B1"
  }));

  // A caretaker may update occupancy metadata for an assigned house, but
  // must never be able to set, replace or clear its assigned tenant UID.
  await assertSucceeds(updateDoc(doc(caretaker, "houses", "house-assigned"), {
    isOccupied: true, status: "occupied"
  }));
  await assertFails(updateDoc(doc(caretaker, "houses", "house-assigned"), {
    assignedTenantId: "another-tenant"
  }));
  await assertFails(updateDoc(doc(caretaker, "houses", "house-assigned"), {
    isOccupied: true, status: "occupied", assignedTenantId: "another-tenant"
  }));

  const landlord = env.authenticatedContext("landlord-1").firestore();
  await assertSucceeds(updateDoc(doc(landlord, "users", "tenant-1"), {
    houseId: "house-other", houseNo: "B1"
  }));
  await assertSucceeds(updateDoc(doc(landlord, "houses", "house-assigned"), {
    assignedTenantId: "another-tenant"
  }));
});


test("caretaker cash collection is restricted to assigned active tenants and can_collect permission", async () => {
  await seed();
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  const valid = {
    landlordId: "landlord-1", caretakerId: "caretaker-1",
    tenantId: "tenant-1", tenantName: "Tenant One",
    houseId: "house-assigned", houseNo: "A1", amountKes: 5000,
    method: "CASH", status: "collected_pending_handover",
    collectedAt: serverTimestamp(), createdAt: serverTimestamp()
  };
  await assertSucceeds(setDoc(doc(caretaker, "cashCollections", "cash-valid"), valid));
  await assertFails(setDoc(doc(caretaker, "cashCollections", "cash-wrong-house"), {
    ...valid, houseId: "house-other", houseNo: "B1"
  }));
  await assertFails(setDoc(doc(caretaker, "cashCollections", "cash-wrong-tenant"), {
    ...valid, tenantId: "another-tenant"
  }));
  await assertFails(setDoc(doc(caretaker, "cashCollections", "cash-spoof-landlord"), {
    ...valid, landlordId: "another-landlord"
  }));
  await assertFails(updateDoc(doc(caretaker, "cashCollections", "cash-valid"), {
    amountKes: 1
  }));
  const ownQuery = query(
    collection(caretaker, "cashCollections"),
    where("caretakerId", "==", "caretaker-1"),
    where("landlordId", "==", "landlord-1"),
    where("houseId", "==", "house-assigned")
  );
  const own = await assertSucceeds(getDocs(ownQuery));
  assert.equal(own.size, 1);
  const landlord = env.authenticatedContext("landlord-1").firestore();
  await assertSucceeds(getDoc(doc(landlord, "cashCollections", "cash-valid")));
});

test("view-only caretaker cannot record cash collections", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (context) => {
    await updateDoc(doc(context.firestore(), "users", "caretaker-1"), {
      caretakerPermission: "view_only"
    });
  });
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  await assertFails(setDoc(doc(caretaker, "cashCollections", "cash-view-only"), {
    landlordId: "landlord-1", caretakerId: "caretaker-1",
    tenantId: "tenant-1", tenantName: "Tenant One",
    houseId: "house-assigned", houseNo: "A1", amountKes: 5000,
    method: "CASH", status: "collected_pending_handover",
    collectedAt: serverTimestamp(), createdAt: serverTimestamp()
  }));
});

test("cash handover must match the caretaker's recorded collection and landlord alone acknowledges it", async () => {
  await seed();
  await env.withSecurityRulesDisabled(async (context) => {
    const db = context.firestore();
    await setDoc(doc(db, "cashCollections", "cash-handover-1"), {
      landlordId: "landlord-1", caretakerId: "caretaker-1",
      tenantId: "tenant-1", tenantName: "Tenant One",
      houseId: "house-assigned", houseNo: "A1", amountKes: 5000,
      method: "CASH", status: "collected_pending_handover",
      collectedAt: new Date(), createdAt: new Date()
    });
  });
  const caretaker = env.authenticatedContext("caretaker-1").firestore();
  const handover = {
    collectionId: "cash-handover-1", landlordId: "landlord-1",
    caretakerId: "caretaker-1", tenantId: "tenant-1",
    tenantName: "Tenant One", houseId: "house-assigned",
    houseNo: "A1", amountKes: 5000,
    status: "submitted", submittedAt: serverTimestamp()
  };
  await assertSucceeds(setDoc(doc(caretaker, "cashHandovers", "cash-handover-1"), handover));
  await assertFails(setDoc(doc(caretaker, "cashHandovers", "cash-handover-forged"), {
    ...handover, collectionId: "cash-handover-1", amountKes: 9000
  }));
  const landlord = env.authenticatedContext("landlord-1").firestore();
  await assertSucceeds(getDoc(doc(landlord, "cashHandovers", "cash-handover-1")));
  await assertSucceeds(updateDoc(doc(landlord, "cashHandovers", "cash-handover-1"), {
    status: "acknowledged", acknowledgedBy: "landlord-1",
    acknowledgedAt: serverTimestamp()
  }));
  await assertFails(updateDoc(doc(landlord, "cashHandovers", "cash-handover-1"), {
    amountKes: 1
  }));
  await assertFails(updateDoc(doc(caretaker, "cashHandovers", "cash-handover-1"), {
    status: "acknowledged", acknowledgedBy: "caretaker-1",
    acknowledgedAt: serverTimestamp()
  }));
  const tenant = env.authenticatedContext("tenant-1").firestore();
  await assertFails(getDoc(doc(tenant, "cashHandovers", "cash-handover-1")));
});
