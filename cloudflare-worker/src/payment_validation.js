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


// Validate the landlord's merchant details before encrypting or saving them.
// Keep this pure so both PayBill and Till formats have direct regression coverage.
export function validateMerchantAccountInput(input) {
  const type = String(input?.accountType || "").toLowerCase();
  const businessName = String(input?.registeredBusinessName || "").trim();
  const shortcode = String(input?.businessShortCode || "").trim();
  const tillNumber = String(input?.tillNumber || "").trim();
  const consumerKey = String(input?.consumerKey || "").trim();
  const consumerSecret = String(input?.consumerSecret || "").trim();
  const passkey = String(input?.passkey || "").trim();

  if (!["paybill", "till"].includes(type)) throw new Error("Choose PayBill or Buy Goods Till.");
  if (!businessName || businessName.length > 120) throw new Error("Enter the registered business name.");
  if (!/^\\d{5,7}$/.test(shortcode)) throw new Error("Enter a valid 5–7 digit Daraja business shortcode.");
  if (type === "till" && !/^\\d{5,20}$/.test(tillNumber)) throw new Error("Enter a valid Buy Goods Till number.");
  if (type === "paybill" && tillNumber) throw new Error("A Till number is not used for PayBill.");
  if (consumerKey.length < 8 || consumerSecret.length < 8 || passkey.length < 8) {
    throw new Error("Enter the Daraja Consumer Key, Consumer Secret and Lipa Na M-Pesa Passkey.");
  }
  return {
    accountType: type,
    businessName,
    businessShortCode: shortcode,
    tillNumber: type === "till" ? tillNumber : "",
    consumerKey,
    consumerSecret,
    passkey,
  };
}
