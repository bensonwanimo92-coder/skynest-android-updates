# SkyNest Individual Landlord M-Pesa Receiving Accounts

Status: approved product direction — each landlord supplies their own Daraja Consumer Key, Consumer Secret and Lipa Na M-Pesa Passkey. The implementation is being repaired on a dedicated branch; no production deployment has been made.
Target branch: fix/individual-landlord-daraja-credentials

The current Worker selects Sandbox or Production globally through `DARAJA_ENV`; the landlord-specific credentials are separate, but the environment is not independently selectable per landlord. Keep the deployment in Sandbox until the required multi-landlord checks and Safaricom live onboarding are complete.

## Product decision

SkyNest uses the individual-landlord receiving model. Each landlord collects rent into their own Safaricom-registered business PayBill or Buy Goods Till. SkyNest is not the merchant of record, does not pool rent, and does not promise to settle funds from a central account.

The automated STK setup supports a landlord-owned PayBill or Buy Goods Till with Daraja credentials. A personal M-Pesa phone number can be used for manual Send Money, with the tenant submitting the receipt for landlord review; it is not a Daraja STK merchant destination. B2C phone payouts are a separate business disbursement product and are not rent collection.

## Landlord experience

Add Landlord > Settings > Payments > M-Pesa Receiving Account.

The setup wizard has these steps:

1. Choose PayBill or Buy Goods Till.
2. Enter the registered business name and shortcode details:
   - PayBill: PayBill/business shortcode.
   - Till: Till number plus the Safaricom Daraja shortcode/head-office number required for that Till.
3. Enter the Daraja Consumer Key, Consumer Secret and Lipa Na M-Pesa Online Passkey. These are write-only secrets: after saving, the app must never read them back or display them.
4. The platform initially runs in Sandbox. Production is a controlled platform rollout after the relevant landlord has Safaricom-approved live Daraja credentials and controlled verification succeeds.
5. Save as Pending verification.
6. Run a controlled test STK Push to the landlord's own M-Pesa phone, using a small amount selected and explicitly confirmed by the landlord. The test must not create a rent payment or tenant ledger entry.
7. Activate the receiving account only after the trusted backend validates the Daraja response and the test callback. Show Verified, Pending, Action required, Suspended or Failed states.

The screen also shows masked shortcode details, business name, account type, environment, verification time, last successful test, and a Change/Disable action. Changing credentials invalidates the old verification and returns the account to Pending verification.

## Tenant payment experience

When an active tenant requests an STK Push, the backend derives the landlord from the authenticated tenant profile and derives the house from the tenant's assigned tenancy. The client cannot supply or override landlordId, shortcode, account credentials, transaction owner, or payment status.

The backend loads the landlord's active verified receiving configuration and initiates the STK Push against that merchant. The payment request records landlordId, tenantId, houseId, amount, expected phone, checkout ID, merchant request ID, receiving-account version, and status. The callback creates exactly one payment record for that landlord after successful verification.

PayBill requests should use a predictable, unique account reference based on the SkyNest payment/invoice reference (within Safaricom field limits). Till requests must use the correct Safaricom Buy Goods transaction type and Till/shortcode mapping validated for that merchant. Do not assume PayBill and Till payloads are interchangeable.

## Backend and data design

### Firestore

- `landlordPaymentAccounts/{landlordUid}`: backend-only document. Contains merchant type, masked/non-secret metadata, encrypted credential envelope, credential version, environment, verification status, timestamps and audit metadata.
- `mpesaPaymentRequests/{checkoutRequestId}`: pending/terminal payment state and immutable merchant/tenant/house correlation fields.
- `payments/{mpesaReceipt}`: canonical confirmed payment record, created only by the trusted callback processor.
- `mpesaCallbackInbox/{checkoutRequestId}`: short-lived parking for callbacks that arrive before the pending request write completes; apply retention/cleanup.

Firestore client rules must deny all client reads and writes to the credential document and must prevent clients from creating or editing callback/payment records that claim a verified M-Pesa payment. Landlords view safe account metadata through an authenticated Worker endpoint, not by reading credential documents.

### Cloudflare Worker

Replace the current single-merchant environment configuration for payment initiation with per-landlord configuration lookup:

1. Verify the Firebase ID token.
2. Load the user's profile and require an active tenant linked to an active landlord.
3. Load that landlord's verified account configuration.
4. Decrypt the merchant credential envelope using a Worker-only encryption key stored as a Cloudflare secret. Use authenticated encryption (AES-GCM), unique random IVs, versioned envelopes and key-rotation support. Never log plaintext credentials.
5. Obtain/cache Daraja OAuth tokens keyed by landlord and credential version, not in one global token variable.
6. Build the PayBill or Till STK payload using that merchant's verified configuration.
7. Store a pending request with immutable landlord, tenant, property and merchant-version correlation.
8. Process callbacks idempotently; verify checkout ID, merchant request ID, expected amount and payer phone where available, receipt uniqueness and pending state before writing a Paid payment record.
9. Ensure a callback cannot redirect or reassign a payment to a different landlord.

Add authenticated endpoints for landlord account setup, safe account status, verification test initiation, and account disable/credential rotation. All write endpoints require landlord role and ownership checks. Never accept credentials from tenant endpoints.

### Credential security

- Never store Daraja Consumer Secret or Passkey in Flutter, app config, source control, logs, analytics, or plaintext Firestore fields.
- Send credentials only over HTTPS to the Worker setup endpoint.
- Encrypt credentials before persistent storage using a Worker-only secret key; restrict access to the Worker service identity.
- Keep the Consumer Key protected as configuration data even though it is not equivalent to the Consumer Secret.
- Redact request bodies and errors from logs.
- Add rate limits to setup/test/payment endpoints.
- Use strict CORS allowlists for the SkyNest website/app origins; CORS is not an authorization control.
- Keep callback routes unguessable and validate callbacks against a previously stored pending checkout.
- Add audit events for account create, update, verification, disable and failed access attempts.
- Do not allow caretaker accounts to configure or change the landlord's receiving account.

## UI states and design

Use SkyNest navy/blue surfaces, clear white labels, green for Verified, amber for Pending, and red for Failed/Suspended. Do not rely on color alone; include text and icons.

The setup form must be progressive: only show Till-specific head-office/Till fields for Till, and only show PayBill account-reference guidance for PayBill. Provide inline format validation, a review step, and a clear warning that saving details does not itself prove the account is live.

After verification, show a compact account card:
- M-Pesa PayBill / Buy Goods Till
- masked shortcode/Till
- registered business name
- Sandbox / Production
- Verified status and date
- Change details / Disable account

## Rollout and acceptance gates

1. Confirm the exact Daraja onboarding and request parameters for both PayBill and Buy Goods Till with Safaricom for the merchant's live account. A successful sandbox test does not establish production eligibility.
2. Implement encrypted credential storage and landlord-only setup/status endpoints.
3. Implement PayBill flow first and add Till only after shortcode/head-office/transaction-type handling is confirmed.
4. Update Firestore rules and tests so only trusted backend code can create confirmed M-Pesa payments.
5. Add Flutter landlord setup UI and tenant account-status/payment routing.
6. Test two different landlord accounts in sandbox and prove each tenant's STK request uses only their own landlord's shortcode/credentials.
7. Test success, cancellation, timeout, duplicate callback, callback-before-pending-write, reused receipt, wrong amount, wrong payer, disabled account, changed credentials and cross-landlord isolation.
8. Deploy Worker and Firestore rules separately from the APK. Keep production disabled until Safaricom merchant approval and live controlled tests pass.

## Current implementation status and remaining acceptance gates

Implemented on `integration/skynest-complete-release-candidate`:

- Landlord-only `GET/POST /api/mpesa/account` endpoints and Android receiving-account screen.
- AES-GCM encryption of Daraja merchant credentials using the Cloudflare-only `MPESA_ENCRYPTION_KEY`; secrets are not returned to the app.
- PayBill and Buy Goods Till configuration fields.
- Landlord-only KES 1 STK merchant-connection test. A successful callback activates the exact saved account configuration and is not recorded as rent.
- Tenant STK routing resolves the landlord from the authenticated tenant profile, requires the linked landlord to be active, and uses only that landlord's verified merchant configuration.
- Verification and rent callbacks validate checkout ID, merchant request ID, exact amount, payer phone, receipt uniqueness and pending state.
- Worker syntax checks and six callback-validation unit tests pass in GitHub Actions.

Not yet complete or independently verified:

- Cloudflare Worker has not been deployed with the new code and the required `MPESA_ENCRYPTION_KEY` secret.
- Sandbox end-to-end tests, including two-landlord isolation, have not yet been run against Safaricom and Firebase.
- Live PayBill/Till payloads and merchant onboarding must be confirmed with Safaricom before production use.
- No in-app manual personal-phone receiving-instructions form has been added yet. The existing tenant payment-submission flow can be used for manual receipt review if the landlord shares their Send Money number separately.
- Rate limiting, strict CORS origin allowlists, audit events for account changes, disable-account workflow, credential key rotation, transaction-status reconciliation and full timeout/reversal handling remain to be implemented.
- Firestore account/callback collections rely on the default-deny client rules and trusted Worker service credentials; add explicit emulator tests to prove client denial.
- The Android release build for the latest commit is still queued behind an earlier Shorebird setup job.

Do not describe the integration as production-ready or issue a final APK until the Worker is deployed, secrets are configured, sandbox tests pass, two-landlord isolation is proven, and the signed Android build completes.
