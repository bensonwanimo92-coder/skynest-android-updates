// Pure validation for successful Daraja STK callbacks. Never infer missing values.
function normalizePhone(value) {
  let phone = String(value ?? "").replace(/[\\s+()\\-]/g, "");
  if (phone.startsWith("0")) phone = "254" + phone.slice(1);
  else if (/^[17]\\d{8}$/.test(phone)) phone = "254" + phone;
  if (!/^254[17]\\d{8}$/.test(phone)) {
    throw new Error("M-Pesa callback contains an invalid payer phone.");
  }
  return phone;
}

export function validateSuccessfulCallback(pending, metadata) {
  const receipt = String(metadata?.MpesaReceiptNumber ?? "").trim().toUpperCase();
  if (!/^[A-Z0-9]{8,16}$/.test(receipt)) {
    throw new Error("Successful callback did not contain a valid M-Pesa receipt.");
  }
  const paidAmount = Number(metadata?.Amount);
  if (!Number.isSafeInteger(paidAmount) || paidAmount !== Number(pending?.amountKes)) {
    throw new Error("M-Pesa callback amount does not match the pending rent request. Manual review required.");
  }
  const paidPhone = normalizePhone(metadata?.PhoneNumber);
  if (paidPhone !== normalizePhone(pending?.phone)) {
    throw new Error("M-Pesa callback payer does not match the pending rent request. Manual review required.");
  }
  return { receipt, paidAmount, paidPhone };
}
