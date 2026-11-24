// SkyNest AI Core: provider-neutral request contract and safety primitives.
// This module deliberately does not call an AI provider or access Firestore yet.
// Integration must supply authenticated server-derived role/context and provider configuration.
export const AI_FEATURES = Object.freeze([
  "landlord", "caretaker", "tenant", "ledger_reports",
  "plans", "inventory", "reading",
]);
export const MUTATING_ACTIONS = Object.freeze([
  "change_rent", "delete_record", "assign_tenant", "initiate_payment",
  "approve_payment", "change_access",
]);

export class AiRequestError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

export function validateAiRequest(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    throw new AiRequestError("Request body must be an object.");
  }
  const feature = String(body.feature || "");
  const question = String(body.question || "").trim();
  if (!AI_FEATURES.includes(feature)) throw new AiRequestError("Unsupported AI feature.");
  if (!question || question.length > 4000) throw new AiRequestError("Question must be between 1 and 4000 characters.");
  // Client-supplied role, landlord, tenant, house and payment identifiers are
  // intentionally not accepted as authority; server must derive scope itself.
  return Object.freeze({ feature, question });
}

export function safeAiEnvelope({ feature, answer, references = [], suggestions = [] }) {
  return {
    feature,
    answer: String(answer || ""),
    references: Array.isArray(references) ? references.slice(0, 20) : [],
    suggestions: Array.isArray(suggestions) ? suggestions.slice(0, 10) : [],
    actionsExecuted: false,
  };
}

export function enforceActionConfirmation(action) {
  if (MUTATING_ACTIONS.includes(String(action || ""))) {
    throw new AiRequestError("AI suggestions cannot execute sensitive actions; explicit user confirmation and server-side validation are required.", 403);
  }
  return true;
}
