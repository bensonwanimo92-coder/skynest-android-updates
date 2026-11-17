"use strict";

/**
 * Returns the accounting period in the requested IANA timezone.
 * Using formatToParts avoids relying on the runner's machine timezone.
 */
function rentPeriodAt(date, timeZone = "Africa/Nairobi") {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone,
    year: "numeric",
    month: "2-digit",
  }).formatToParts(date);
  const values = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return values.year + "-" + values.month;
}

/**
 * Build an immutable monthly rent snapshot only when the tenant and house
 * explicitly agree on landlord, house ID and house number.
 */
function buildRentInvoice({ tenantId, tenant, house, period }) {
  if (!tenantId || !tenant || !house || !/^\d{4}-(0[1-9]|1[0-2])$/.test(period || "")) return null;
  const landlordId = String(house.landlordId || "");
  const houseNo = String(house.houseNo || "");
  const rent = Number(house.rent);
  if (!landlordId || house.createdBy !== landlordId ||
      house.assignedTenantId !== tenantId || !houseNo ||
      tenant.role !== "tenant" || tenant.status !== "active" ||
      tenant.landlordId !== landlordId || tenant.houseId !== house.id ||
      String(tenant.houseNo || "") !== houseNo ||
      !Number.isSafeInteger(rent) || rent <= 0) return null;

  return {
    id: tenantId + "_" + house.id + "_" + period,
    data: {
      landlordId,
      createdBy: landlordId,
      tenantId,
      tenantName: String(tenant.displayName || tenant.name || "Tenant"),
      houseId: house.id,
      houseNo,
      period,
      amountDueKes: rent,
      rentAtIssue: rent,
      status: "issued",
    },
  };
}

module.exports = { rentPeriodAt, buildRentInvoice };
