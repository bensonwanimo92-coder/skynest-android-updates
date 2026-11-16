import test from "node:test";
import assert from "node:assert/strict";
import {
  validateSuccessfulCallback,
  validateTenantHouseLink,
  validateMerchantAccountInput,
} from "./payment_validation.js";

test("accepts a callback only when receipt, amount and payer match", () => {
  const pending = { amountKes: 1200, phone: "254712345678" };
  const metadata = {
    MpesaReceiptNumber: "QAB12CD34E",
    Amount: 1200,
    PhoneNumber: "254712345678",
  };
  assert.deepEqual(validateSuccessfulCallback(pending, metadata), {
    receipt: "QAB12CD34E",
    paidAmount: 1200,
    paidPhone: "254712345678",
  });
});

test("rejects a callback with a mismatched amount", () => {
  assert.throws(
    () => validateSuccessfulCallback(
      { amountKes: 1200, phone: "254712345678" },
      { MpesaReceiptNumber: "QAB12CD34E", Amount: 100, PhoneNumber: "254712345678" },
    ),
    /amount does not match/,
  );
});

test("rejects a callback from a different payer phone", () => {
  assert.throws(
    () => validateSuccessfulCallback(
      { amountKes: 1200, phone: "254712345678" },
      { MpesaReceiptNumber: "QAB12CD34E", Amount: 1200, PhoneNumber: "254700000000" },
    ),
    /payer does not match/,
  );
});

test("normalizes Kenyan local phone numbers in callback validation", () => {
  const result = validateSuccessfulCallback(
    { amountKes: 500, phone: "0712345678" },
    { MpesaReceiptNumber: "QAB12CD34E", Amount: 500, PhoneNumber: "254712345678" },
  );
  assert.equal(result.paidPhone, "254712345678");
});

test("requires tenant to remain assigned to the exact landlord house", () => {
  const profile = {
    role: "tenant", status: "active", landlordId: "landlord-1",
    houseId: "house-4", houseNo: "4",
  };
  const house = {
    createdBy: "landlord-1", landlordId: "landlord-1",
    assignedTenantId: "tenant-1", houseNo: "4",
  };
  assert.deepEqual(validateTenantHouseLink(profile, house, "tenant-1"), {
    landlordId: "landlord-1", houseId: "house-4", houseNo: "4",
  });
  assert.throws(
    () => validateTenantHouseLink(profile, { ...house, assignedTenantId: "tenant-2" }, "tenant-1"),
    /assigned house could not be verified/,
  );
});

test("validates landlord PayBill and Till receiving-account inputs", () => {
  const paybill = validateMerchantAccountInput({
    accountType: "paybill", registeredBusinessName: "Example Rentals",
    businessShortCode: "123456", consumerKey: "consumer-key-123",
    consumerSecret: "consumer-secret-123", passkey: "passkey-123",
  });
  assert.equal(paybill.accountType, "paybill");
  const till = validateMerchantAccountInput({
    accountType: "till", registeredBusinessName: "Example Rentals",
    businessShortCode: "123456", tillNumber: "987654",
    consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
    passkey: "passkey-123",
  });
  assert.equal(till.tillNumber, "987654");
  assert.throws(
    () => validateMerchantAccountInput({
      accountType: "paybill", registeredBusinessName: "Example Rentals",
      businessShortCode: "123456", tillNumber: "987654",
      consumerKey: "consumer-key-123", consumerSecret: "consumer-secret-123",
      passkey: "passkey-123",
    }),
    /Till number is not used for PayBill/,
  );
});
