# SkyNest AI Core — integration preparation (next release)

Status: design/preparation only; no AI API credentials, billing, or production integration enabled.

## Architecture
- Single AI gateway/service; feature-specific prompt and tool adapters.
- Role-scoped server-side context retrieval; never trust client role claims alone.
- Landlord, caretaker, tenant context separation; property assignment and ownership checks.
- AI output is advisory by default. Mutations require explicit confirmation and server validation.

## Feature adapters (initial scope)
1. Landlord: rent received, arrears, vacancy, expense and property summaries.
2. Caretaker: assigned-property status, maintenance and complaints triage, tenant communication drafts.
3. Tenant: own balance/payment status, house rules, complaint status, general help.
4. Ledger/Reports: summaries, trends, discrepancies and natural-language explanations.
5. Plans: daily task planning and priorities.
6. Inventory: stock categorisation and replenishment suggestions.
7. Reading: explanations, summaries, study questions and note drafting.

## Suggested service contract
Request: authenticated user, role, feature, question, approved context identifiers.
Response: answer, source/context references, suggested actions (not executed), confidence/limitations.
Gateway: validate authentication; resolve role and scope from Firebase/server records; retrieve only minimum context; enforce quotas; log safe metadata; call model; validate response; return.
Never send secrets, unrestricted Firestore dumps, payment credentials, or unrelated tenant data to the model.

## Guardrails
- Deny cross-landlord and unassigned-house data access.
- Do not expose phone numbers, payment identifiers, credentials or sensitive records unless strictly needed and authorised.
- AI cannot initiate/approve M-Pesa payments, alter rent, delete records, assign tenants, or change access.
- Require user confirmation and deterministic backend validation for actions.
- Rate limits, token caps, timeout, retry controls, caching where appropriate, cost tracking and kill switch.
- Firebase App Check, server-side secrets, auditable rules and security tests.

## Rollout checklist
- [ ] Inspect current Firebase rules, Cloudflare Worker, app service architecture and release baseline.
- [ ] Select model/provider and cost controls; user approval for any billing/credentials.
- [ ] Implement gateway on backend, not client-side API-key storage.
- [ ] Implement role-aware context retrieval and deny-by-default tests.
- [ ] Add AI Centre UI and section shortcuts.
- [ ] Add fallback, quota, latency and offline messaging.
- [ ] Test synthetic landlord/caretaker/tenant accounts and cross-role isolation.
- [ ] Verify no production data leakage; audit AI request logging.
- [ ] Integrate only into next release after build baseline is verified.

## Estimated first release
Approximately 1–2 working days for a usable first integration, assuming accessible, stable code and backend; this is a planning estimate, not a guaranteed schedule.
