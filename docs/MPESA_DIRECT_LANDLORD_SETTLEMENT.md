# SkyNest M-Pesa — Direct-to-Landlord Settlement Decision

Decision recorded: 16 November 2026

## User-approved outcome

SkyNest rent payments must settle directly to the landlord's own registered PayBill or Till. SkyNest must not collect, pool, hold, or later remit rent. The landlord must not be asked to obtain or paste Daraja Consumer Key, Consumer Secret, or Lipa Na M-Pesa Passkey into the SkyNest app.

## Required product experience

1. Landlord enters the receiving account type, registered business name, PayBill/Till identifiers, and the minimum contact/ownership information required for verification.
2. SkyNest verifies that the receiving account belongs to or is authorized for that landlord before enabling payments.
3. Tenant selects a rent amount and requests payment without choosing or editing the recipient.
4. The payment provider routes funds directly to that landlord's receiving account.
5. Only an authenticated, validated provider callback with a unique transaction reference can post a payment to the rent ledger.
6. Pending, failed, reversed, duplicate, and mismatched callbacks must never be counted as rent received.

## Architecture constraint

A central SkyNest Daraja Consumer Key/Secret alone does not prove that one STK Push application can initiate payments against arbitrary third-party PayBills/Tills. A Daraja STK Push request is tied to a merchant shortcode and its passkey. Therefore, do not replace landlord credentials with SkyNest-wide credentials and assume arbitrary merchant routing works.

The implementation requires a Safaricom-approved platform/aggregator arrangement that explicitly supports:
- onboarding and verifying independent landlord merchants;
- initiating tenant payments for the selected landlord;
- direct settlement to that landlord's own PayBill/Till (not a SkyNest wallet or pooled account);
- callback delivery and reconciliation with landlord/tenant/payment references;
- documented production authorization, fees, limits, reversals, and support responsibilities.

A provider that first credits a platform/sub-merchant wallet and later forwards funds is not accepted as direct settlement unless the user explicitly changes this requirement.

## Current code assessment

The current Cloudflare Worker is a sandbox-first, per-landlord Daraja implementation. It stores each landlord's Daraja credentials encrypted server-side, verifies a merchant by sending a KES 1 STK prompt, and uses the verified merchant configuration for tenant STK requests. It is not the selected central-provider architecture.

Do not silently remove the existing flow or expose a half-configured payment option. Until an approved direct-settlement provider and its API contract are selected:
- keep production payments disabled;
- do not accept Daraja secrets in the landlord-facing app as the final UX;
- do not mark a landlord account verified merely because input validation passed;
- do not claim funds settle directly to landlords;
- preserve callback validation, tenant-house ownership checks, idempotency and ledger safeguards.

## Provider acceptance checklist

- [ ] Written provider/Safaricom confirmation of direct-to-landlord settlement.
- [ ] API documentation and sandbox credentials for platform merchant onboarding.
- [ ] Verified merchant identity and destination ownership checks.
- [ ] Payment initiation API supports each landlord's own destination without landlord Daraja secrets in the client.
- [ ] Signed/authenticated webhooks, retry semantics, event IDs and status-query API.
- [ ] Explicit proof that funds do not pass through or remain in a SkyNest-controlled balance.
- [ ] Fees, settlement timing, limits, refunds/reversals and dispute handling documented.
- [ ] Security review and backend secret configuration completed.
- [ ] Sandbox end-to-end test for PayBill and Till, including duplicate and late callbacks.
- [ ] Production approval and a small controlled live verification before enabling tenants.

## Technical references reviewed

- Safaricom Daraja STK Push request fields and shortcode/passkey relationship: https://developer.safaricom.co.ke/
- Candidate gateway documentation must be checked against the direct-settlement requirement; sub-merchant wallets and later B2B payouts are not equivalent to direct settlement.

## Release gate

The M-Pesa feature remains **not release-verified** until the provider decision, sandbox flow, callback reconciliation, deployment, and role-based end-to-end checks pass. No release APK should be produced solely to demonstrate this incomplete payment route.
