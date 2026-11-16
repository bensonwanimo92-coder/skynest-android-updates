// Pure validation for successful Daraja STK callbacks. Never infer missing values.
function normalizePhone(value) {
  let phone = String(value ?? "").replace(/[\s+()\-]/g, "");
  if (phone.startsWith("0")) phone = "254" + phone.slice(1);
  else if (/^[17]\d{8}$/.test(phone)) phone = "254" + phone;
  if (!/^254[17]\d{8}$/.test(phone)) {
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

// Verify that an authenticated tenant is still assigned to the exact house
// recorded in their profile before creating an STK request.
export function validateTenantHouseLink(profile, house, uid) {
  const landlordId = String(profile?.landlordId || "");
  const houseId = String(profile?.houseId || "");
  const houseNo = String(profile?.houseNo || "");
  if (!uid || String(profile?.role || "").toLowerCase() !== "tenant" ||
      String(profile?.status || "").toLowerCase() !== "active" ||
      !landlordId || !houseId || !houseNo) {
    throw new Error("The tenant account does not have a complete active house assignment.");
  }
  if (String(house?.createdBy || "") !== landlordId ||
      String(house?.landlordId || "") !== landlordId ||
      String(house?.assignedTenantId || "") !== uid ||
      String(house?.houseNo || "") !== houseNo) {
    throw new Error("The tenant's assigned house could not be verified. Contact the landlord.");
  }
  return { landlordId, houseId, houseNo };
}
