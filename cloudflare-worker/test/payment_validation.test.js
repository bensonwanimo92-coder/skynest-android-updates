import assert from "node:assert/strict";
import test from "node:test";

import {
  validateMerchantAccountInput,
  validateSuccessfulCallback,
  validateTenantHouseLink,
} from "../src/payment_validation.js";

const pendingPayment = {
  amountKes: 1250,
  phone: "+254 712 345 678",
};

test("accepts a successful callback when receipt, amount and payer match", () => {
  const result = validateSuccessfulCallback(pendingPayment, {
    MpesaReceiptNumber: "ABC1234567",
    Amount: 1250,
    PhoneNumber: "0712345678",
  });

  assert.deepEqual(result, {
    receipt: "ABC1234567",
    paidAmount: 1250,
    paidPhone: "254712345678",
  });
});

test("normalizes a lowercase receipt before returning it", () => {
  const result = validateSuccessfulCallback(pendingPayment, {
    MpesaReceiptNumber: "abc1234567",
    Amount: "1250",
    PhoneNumber: "254712345678",
  });

  assert.equal(result.receipt, "ABC1234567");
});

test("rejects missing, malformed or too-short M-Pesa receipts", () => {
  for (const receipt of [undefined, "", "ABC1234", "ABC-123456", "ABC 123456"]) {
    assert.throws(
      () => validateSuccessfulCallback(pendingPayment, {
        MpesaReceiptNumber: receipt,
        Amount: 1250,
        PhoneNumber: "0712345678",
      }),
      /valid M-Pesa receipt/,
    );
  }
});

test("rejects callback amounts that do not exactly match the pending amount", () => {
  for (const amount of [0, 1249, 1251, 1250.5, "not-a-number"]) {
    assert.throws(
      () => validateSuccessfulCallback(pendingPayment, {
        MpesaReceiptNumber: "ABC1234567",
        Amount: amount,
        PhoneNumber: "0712345678",
      }),
      /amount does not match/,
    );
  }
});

test("rejects a callback from a different payer", () => {
  assert.throws(
    () => validateSuccessfulCallback(pendingPayment, {
      MpesaReceiptNumber: "ABC1234567",
      Amount: 1250,
      PhoneNumber: "0798765432",
    }),
    /payer does not match/,
  );
});

test("rejects malformed Kenyan payer numbers", () => {
  for (const phone of ["07123", "254812345678", "abc", ""]) {
    assert.throws(
      () => validateSuccessfulCallback(pendingPayment, {
        MpesaReceiptNumber: "ABC1234567",
        Amount: 1250,
        PhoneNumber: phone,
      }),
      /invalid payer phone/,
    );
  }
});

const tenantProfile = {
  role: "tenant",
  status: "active",
  landlordId: "landlord-1",
  houseId: "house-1",
  houseNo: "A-01",
};
const assignedHouse = {
  createdBy: "landlord-1",
  landlordId: "landlord-1",
  assignedTenantId: "tenant-1",
  houseNo: "A-01",
};

test("accepts the tenant's exact active landlord and house assignment", () => {
  assert.deepEqual(
    validateTenantHouseLink(tenantProfile, assignedHouse, "tenant-1"),
    { landlordId: "landlord-1", houseId: "house-1", houseNo: "A-01" },
  );
});

test("rejects inactive, non-tenant or incomplete tenant profiles", () => {
  const invalidProfiles = [
    { ...tenantProfile, status: "pending" },
    { ...tenantProfile, role: "caretaker" },
    { ...tenantProfile, landlordId: "" },
    { ...tenantProfile, houseId: "" },
    { ...tenantProfile, houseNo: "" },
  ];

  for (const profile of invalidProfiles) {
    assert.throws(() => validateTenantHouseLink(profile, assignedHouse, "tenant-1"));
  }
});

test("rejects a house assigned to another tenant", () => {
  assert.throws(
    () => validateTenantHouseLink(
      tenantProfile,
      { ...assignedHouse, assignedTenantId: "tenant-2" },
      "tenant-1",
    ),
    /could not be verified/,
  );
});

test("rejects a house belonging to another landlord", () => {
  assert.throws(
    () => validateTenantHouseLink(
      tenantProfile,
      { ...assignedHouse, landlordId: "landlord-2" },
      "tenant-1",
    ),
    /could not be verified/,
  );
});

test("rejects a house created by a different landlord", () => {
  assert.throws(
    () => validateTenantHouseLink(
      tenantProfile,
      { ...assignedHouse, createdBy: "landlord-2" },
      "tenant-1",
    ),
    /could not be verified/,
  );
});

test("rejects a changed house number", () => {
  assert.throws(
    () => validateTenantHouseLink(
      tenantProfile,
      { ...assignedHouse, houseNo: "B-02" },
      "tenant-1",
    ),
    /could not be verified/,
  );
});

test("normalizes and accepts a valid PayBill receiving account", () => {
  assert.deepEqual(validateMerchantAccountInput({
    accountType: "PAYBILL",
    businessShortCode: " 123456 ",
    tillNumber: "",
  }), {
    accountType: "paybill",
    businessShortCode: "123456",
    tillNumber: "",
  });
});

test("normalizes and accepts a valid Buy Goods Till", () => {
  assert.deepEqual(validateMerchantAccountInput({
    accountType: "TILL",
    tillNumber: "123456789012",
  }), {
    accountType: "till",
    businessShortCode: "",
    tillNumber: "123456789012",
  });
});

test("rejects unsupported merchant account types", () => {
  assert.throws(
    () => validateMerchantAccountInput({ accountType: "phone" }),
    /Choose PayBill or Buy Goods Till/,
  );
});

test("rejects invalid PayBill numbers", () => {
  for (const shortcode of ["1234", "12345678", "12A456", ""]) {
    assert.throws(
      () => validateMerchantAccountInput({
        accountType: "paybill",
        businessShortCode: shortcode,
      }),
      /PayBill number/,
    );
  }
});

test("rejects a Till without a valid numeric destination", () => {
  for (const tillNumber of ["", "1234", "12A456", "123456789012345678901"]) {
    assert.throws(
      () => validateMerchantAccountInput({
        accountType: "till",
        tillNumber,
      }),
      /Buy Goods Till number/,
    );
  }
});

test("rejects a Till number supplied for a PayBill account", () => {
  assert.throws(
    () => validateMerchantAccountInput({
      accountType: "paybill",
      businessShortCode: "123456",
      tillNumber: "123456",
    }),
    /Till number is not used for PayBill/,
  );
});
