import test from "node:test";
import assert from "node:assert/strict";
import { validateSuccessfulCallback } from "../src/payment_validation.js";

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
