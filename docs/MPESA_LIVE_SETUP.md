# SkyNest Live M-Pesa Setup

SkyNest live rent collection uses Safaricom Daraja production credentials for each landlord merchant. A landlord's PayBill or Till is the settlement destination; SkyNest does not pool tenant funds.

## One-time Firebase secret

The Functions backend encrypts merchant credentials with AES-256-GCM. Before deploying the new Functions, create the encryption secret in the Firebase project:

```bash
openssl rand -hex 32
firebase functions:secrets:set MPESA_CONFIG_ENCRYPTION_KEY
```

Paste the generated 64-character hex value into the Firebase CLI prompt. Do not commit it, paste it into chat, or place it in the Android app. Keep a secure backup. Losing this key makes previously stored merchant credentials unreadable.

The GitHub deploy identity (service account named `skynest-deployer`) needs `roles/serviceusage.serviceUsageAdmin` to enable APIs and `roles/secretmanager.admin` to create the encryption secret. The Cloud Functions runtime service account needs `roles/secretmanager.secretAccessor`; the workflow grants this to the default Compute Engine service account. If the deploy identity cannot enable APIs, a project owner must enable Secret Manager API in Google Cloud Console first. The secret must exist before deploying functions that bind to it. Firebase Cloud Functions deployment also requires the Firebase project to be on the Blaze (pay-as-you-go) plan and the required Google Cloud APIs/billing to be enabled.

## Landlord merchant onboarding

Each landlord must have a Safaricom Daraja application approved for the relevant live shortcode and Lipa Na M-Pesa Online enabled. They configure credentials inside SkyNest under **M-Pesa collection setup**:

- Production Consumer Key
- Production Consumer Secret
- Production Lipa Na M-Pesa Passkey
- PayBill shortcode; or for Buy Goods/Till, Store/Head Office shortcode and the actual Till number

The backend authenticates the credentials with the production Daraja OAuth endpoint before saving them. Credentials are encrypted at rest and never returned to the app. Sandbox credentials are rejected by the live endpoint.

For a Till, Daraja authenticates using the Store/Head Office shortcode and sends the Buy Goods transaction to the Till number. For PayBill, the PayBill shortcode is used with CustomerPayBillOnline.

## Payment flow

1. An active tenant requests a rent payment from the app.
2. The callable Function resolves the tenant's linked landlord and uses only that landlord's configured merchant credentials.
3. Daraja sends the STK prompt to the tenant's Kenyan Safaricom number.
4. Safaricom posts the callback to `mpesaStkCallback`.
5. The backend queries Daraja for the checkout result and checks the callback amount, phone and receipt against the original payment intent.
6. Only a confirmed, unique receipt creates a Paid record in the landlord's Payments/Ledger collection. Duplicate callbacks are idempotent.

A callback that cannot be independently reconciled is not credited as Paid.

## Production requirements and limitations

- Deploy Cloud Functions in the Firebase project used by the app, with `MPESA_CONFIG_ENCRYPTION_KEY` configured first.
- Each landlord is responsible for obtaining production Daraja approval and credentials for their own shortcode. SkyNest cannot manufacture Safaricom approval or credentials.
- For Till merchants, the Store/Head Office number and Till number must be correctly supplied by Safaricom.
- The current backend uses the Safaricom production API host only; no sandbox fallback is implemented.
- Do not mark a payment paid based only on the tenant's screen, an STK request acceptance, or an unverified callback.
- This implementation does not run simulator/emulator tests and adds no such test workflow.
