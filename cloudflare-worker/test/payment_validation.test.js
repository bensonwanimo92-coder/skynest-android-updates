import test from "node:test";
import assert from "node:assert/strict";
import { validateSuccessfulCallback, validateTenantHouseLink, validateMerchantAccountInput } from "../src/payment_validation.js";

const pending = { amountKes: 25000, phone: "254712345678" };
const metadata = { MpesaReceiptNumber: "QWE1234567", Amount: 25000, PhoneNumber: 254712345678 };

test("accepts a matching successful callback", () => {
  assert.deepEqual(validateSuccessfulCallback(pending, metadata), {
    receipt: "QWE1234567", paidAmount: 25000, paidPhone: "254712345678",
  });
});
test("rejects a mismatched amount", () => {
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, Amount: 24999 }), /amount does not match/);
});
test("rejects missing or non-integer amount", () => {
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, Amount: undefined }), /amount does not match/);
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, Amount: 25000.5 }), /amount does not match/);
});
test("rejects a different payer phone", () => {
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, PhoneNumber: 254722222222 }), /payer does not match/);
});
test("rejects invalid or missing receipt", () => {
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, MpesaReceiptNumber: "bad!" }), /valid M-Pesa receipt/);
  assert.throws(() => validateSuccessfulCallback(pending, { ...metadata, MpesaReceiptNumber: undefined }), /valid M-Pesa receipt/);
});
test("normalizes a Kenyan 07 phone in callback metadata", () => {
  assert.equal(validateSuccessfulCallback(pending, { ...metadata, PhoneNumber: "0712345678" }).paidPhone, "254712345678");
});


const tenantProfile = {
  role: "tenant", status: "active", landlordId: "landlord-1",
  houseId: "house-1", houseNo: "A1"
};
const assignedHouse = {
  createdBy: "landlord-1", landlordId: "landlord-1",
  assignedTenantId: "tenant-1", houseNo: "A1"
};

test("accepts an active tenant's exact landlord-assigned house", () => {
  assert.deepEqual(validateTenantHouseLink(tenantProfile, assignedHouse, "tenant-1"), {
    landlordId: "landlord-1", houseId: "house-1", houseNo: "A1"
  });
});
test("rejects an unassigned tenant house", () => {
  assert.throws(() => validateTenantHouseLink(tenantProfile,
    { ...assignedHouse, assignedTenantId: "another-tenant" }, "tenant-1"), /could not be verified/);
});
test("rejects a house belonging to another landlord", () => {
  assert.throws(() => validateTenantHouseLink(tenantProfile,
    { ...assignedHouse, landlordId: "another-landlord" }, "tenant-1"), /could not be verified/);
});
test("rejects a mismatched unit number", () => {
  assert.throws(() => validateTenantHouseLink(tenantProfile,
    { ...assignedHouse, houseNo: "B9" }, "tenant-1"), /could not be verified/);
});
test("rejects tenants without an active house assignment", () => {
  assert.throws(() => validateTenantHouseLink({ ...tenantProfile, houseId: "" },
    assignedHouse, "tenant-1"), /complete active house assignment/);
});


test("accepts a valid PayBill merchant configuration", () => {
  assert.deepEqual(validateMerchantAccountInput({
    accountType: "paybill", registeredBusinessName: "Example Properties",
    businessShortCode: "123456", tillNumber: "",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123456"
  }), {
    accountType: "paybill", businessName: "Example Properties",
    businessShortCode: "123456", tillNumber: "",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123456"
  });
});
test("accepts a valid Buy Goods Till configuration", () => {
  const result = validateMerchantAccountInput({
    accountType: "till", registeredBusinessName: "Example Properties",
    businessShortCode: "123456", tillNumber: "9876543210",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123456"
  });
  assert.equal(result.tillNumber, "9876543210");
});
test("rejects non-digit or incorrectly sized merchant shortcodes", () => {
  const base = {
    accountType: "paybill", registeredBusinessName: "Example Properties",
    businessShortCode: "123456", tillNumber: "",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123456"
  };
  for (const businessShortCode of ["1234", "12345678", "12A456", "12345x"]) {
    assert.throws(() => validateMerchantAccountInput({ ...base, businessShortCode }), /shortcode/);
  }
});
test("rejects invalid Till numbers and a Till number on PayBill", () => {
  const base = {
    accountType: "till", registeredBusinessName: "Example Properties",
    businessShortCode: "123456", tillNumber: "9876543210",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123456"
  };
  for (const tillNumber of ["1234", "123456789012345678901", "12345X"]) {
    assert.throws(() => validateMerchantAccountInput({ ...base, tillNumber }), /Till number/);
  }
  assert.throws(() => validateMerchantAccountInput({ ...base, accountType: "paybill" }), /not used for PayBill/);
});
test("rejects missing merchant credentials", () => {
  assert.throws(() => validateMerchantAccountInput({
    accountType: "paybill", registeredBusinessName: "Example Properties",
    businessShortCode: "123456", consumerKey: "", consumerSecret: "", passkey: ""
  }), /Consumer Key/);
});
