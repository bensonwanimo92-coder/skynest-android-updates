import test from "node:test";
import assert from "node:assert/strict";
import { validateMerchantAccountInput, validatePayerHouseLink } from "./payment_validation.js";

test("accepts PayBill and business name without Daraja credentials", () => {
  assert.deepEqual(validateMerchantAccountInput({
    accountType: "paybill",
    registeredBusinessName: "Example Rentals",
    accountNumber: "123456",
  }), {
    accountType: "paybill",
    businessName: "Example Rentals",
    accountNumber: "123456",
  });
});

test("accepts Buy Goods Till and business name", () => {
  assert.equal(validateMerchantAccountInput({
    accountType: "till",
    registeredBusinessName: "Example Rentals",
    accountNumber: "987654",
  }).accountType, "till");
});

test("rejects missing recipient account number", () => {
  assert.throws(() => validateMerchantAccountInput({
    accountType: "paybill", registeredBusinessName: "Example Rentals", accountNumber: "",
  }), /valid 5–20 digit/);
});

test("rejects unsupported receiving account types", () => {
  assert.throws(() => validateMerchantAccountInput({
    accountType: "bank", registeredBusinessName: "Example Rentals", accountNumber: "123456",
  }), /Choose PayBill or Buy Goods Till/);
});

test("allows an active tenant only for their linked house", () => {
  const profile = { role: "tenant", status: "active", landlordId: "landlord1", houseId: "house1", houseNo: "A1" };
  const house = { createdBy: "landlord1", landlordId: "landlord1", assignedTenantId: "tenant1", houseNo: "A1" };
  assert.deepEqual(validatePayerHouseLink(profile, house, "tenant1"), {
    landlordId: "landlord1", houseId: "house1", houseNo: "A1",
  });
  assert.throws(() => validatePayerHouseLink(profile, house, "tenant2"), /assignment could not be verified/);
});

test("allows an active caretaker only for an assigned house", () => {
  const profile = { role: "caretaker", status: "active", landlordId: "landlord1", houseId: "house1" };
  const house = { createdBy: "landlord1", landlordId: "landlord1", assignedTenantId: "caretaker1", houseNo: "B2" };
  assert.equal(validatePayerHouseLink(profile, house, "caretaker1").houseNo, "B2");
  assert.throws(() => validatePayerHouseLink(profile, house, "caretaker2"), /active account|rented home/);
});
