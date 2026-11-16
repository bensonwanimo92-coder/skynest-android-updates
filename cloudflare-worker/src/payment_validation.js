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


// Validate the public recipient details entered by a landlord.
// Daraja credentials are platform-managed and are never requested in the app.
export function validateMerchantAccountInput(input) {
  const accountType = String(input?.accountType || "").toLowerCase();
  const businessName = String(input?.registeredBusinessName || "").trim();
  const accountNumber = String(input?.accountNumber || "").trim();
  if (!["paybill", "till"].includes(accountType)) {
    throw new Error("Choose PayBill or Buy Goods Till.");
  }
  if (!businessName || businessName.length > 120) {
    throw new Error("Enter the registered business name.");
  }
  if (!/^\\d{5,20}$/.test(accountNumber)) {
    throw new Error("Enter a valid 5–20 digit PayBill or Till number.");
  }
  return { accountType, businessName, accountNumber };
}

// Check an active tenant or caretaker's linked house before payment.
export function validatePayerHouseLink(profile, house, uid) {
  const role = String(profile?.role || "").toLowerCase();
  const landlordId = String(profile?.landlordId || "");
  const houseId = String(profile?.houseId || "");
  const houseNo = String(profile?.houseNo || "");
  if (!uid || !["tenant", "caretaker"].includes(role) ||
      String(profile?.status || "").toLowerCase() !== "active" ||
      !landlordId || !houseId) {
    throw new Error("Your active account must be linked to a landlord and assigned house.");
  }
  if (String(house?.createdBy || "") !== landlordId ||
      String(house?.landlordId || "") !== landlordId) {
    throw new Error("The assigned house does not belong to your linked landlord.");
  }
  if (role === "tenant" &&
      (String(house?.assignedTenantId || "") !== uid ||
       String(house?.houseNo || "") !== houseNo)) {
    throw new Error("Your tenant house assignment could not be verified.");
  }
  if (role === "caretaker" &&
      !Array.isArray(house?.caretakerIds || []) &&
      !(Array.isArray(profile?.propertyIds) && profile.propertyIds.includes(houseId))) {
    throw new Error("This house is not assigned to your caretaker account.");
  }
  if (role === "caretaker" &&
      !(Array.isArray(house?.caretakerIds) && house.caretakerIds.includes(uid)) &&
      !(Array.isArray(profile?.propertyIds) && profile.propertyIds.includes(houseId))) {
    throw new Error("This house is not assigned to your caretaker account.");
  }
  return { landlordId, houseId, houseNo: houseNo || String(house?.houseNo || "") };
}
