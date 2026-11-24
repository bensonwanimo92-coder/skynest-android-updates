import test from "node:test";
import assert from "node:assert/strict";
import { AI_FEATURES, validateAiRequest, safeAiEnvelope, enforceActionConfirmation, assertAiRoleFeature } from "../src/ai_core_contract.js";

test("AI request accepts only listed features and bounded question text", () => {
  assert.equal(validateAiRequest({feature:"tenant", question:"Explain my balance"}).feature, "tenant");
  assert.throws(() => validateAiRequest({feature:"other", question:"Hi"}));
  assert.throws(() => validateAiRequest({feature:"tenant", question:" "}));
  assert.throws(() => validateAiRequest({feature:"tenant", question:"x".repeat(4001)}));
  assert.equal(AI_FEATURES.length, 7);
});
test("request contract ignores client-provided role and scope claims", () => {
  const parsed = validateAiRequest({feature:"landlord", question:"Summary?", role:"admin", landlordId:"spoofed", houseId:"spoofed"});
  assert.deepEqual(parsed, {feature:"landlord", question:"Summary?"});
});
test("response envelope never represents actions as executed", () => {
  assert.equal(safeAiEnvelope({feature:"plans", answer:"Plan"}).actionsExecuted, false);
});
test("sensitive action execution is denied", () => {
  assert.throws(() => enforceActionConfirmation("initiate_payment"), {status:403});
  assert.equal(enforceActionConfirmation("draft_message"), true);
});

test("AI role permissions isolate landlord, caretaker and tenant assistants", () => {
  assert.equal(assertAiRoleFeature("landlord", "ledger_reports"), "landlord");
  assert.equal(assertAiRoleFeature("caretaker", "caretaker"), "caretaker");
  assert.equal(assertAiRoleFeature("tenant", "tenant"), "tenant");
  assert.throws(() => assertAiRoleFeature("tenant", "landlord"), {status:403});
  assert.throws(() => assertAiRoleFeature("caretaker", "tenant"), {status:403});
  assert.throws(() => assertAiRoleFeature("tenant", "reading", "suspended"), {status:403});
  assert.throws(() => assertAiRoleFeature("admin", "landlord"), {status:403});
});
