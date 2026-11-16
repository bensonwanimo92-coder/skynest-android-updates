"use strict";

const test = require("node:test");
const assert = require("node:assert/strict");
const { rentPeriodAt, buildRentInvoice } = require("./rent_invoice_scheduler");

test("rent period uses Nairobi calendar month even near UTC month boundary", () => {
  assert.equal(rentPeriodAt(new Date("2026-10-31T21:30:00.000Z")), "2026-11");
  assert.equal(rentPeriodAt(new Date("2026-11-30T20:30:00.000Z")), "2026-11");
});

test("creates a stable invoice snapshot for a correctly assigned active tenant", () => {
  const invoice = buildRentInvoice({
    tenantId: "tenant-1",
    tenant: {
      role: "tenant", status: "active", landlordId: "landlord-1",
      houseId: "house-a", houseNo: "A1", displayName: "Tenant One",
    },
    house: {
      id: "house-a", createdBy: "landlord-1", landlordId: "landlord-1",
      assignedTenantId: "tenant-1", houseNo: "A1", rent: 15000,
    },
    period: "2026-11",
  });
  assert.equal(invoice.id, "tenant-1_house-a_2026-11");
  assert.equal(invoice.data.amountDueKes, 15000);
  assert.equal(invoice.data.rentAtIssue, 15000);
  assert.equal(invoice.data.tenantName, "Tenant One");
});

test("rejects mismatched tenant, house, landlord, invalid rent and invalid period", () => {
  const base = {
    tenantId: "tenant-1",
    tenant: {
      role: "tenant", status: "active", landlordId: "landlord-1",
      houseId: "house-a", houseNo: "A1",
    },
    house: {
      id: "house-a", createdBy: "landlord-1", landlordId: "landlord-1",
      assignedTenantId: "tenant-1", houseNo: "A1", rent: 15000,
    },
    period: "2026-11",
  };
  assert.equal(buildRentInvoice({ ...base, tenant: { ...base.tenant, houseNo: "B2" } }), null);
  assert.equal(buildRentInvoice({ ...base, house: { ...base.house, assignedTenantId: "tenant-2" } }), null);
  assert.equal(buildRentInvoice({ ...base, house: { ...base.house, rent: 0 } }), null);
  assert.equal(buildRentInvoice({ ...base, period: "2026-13" }), null);
});
