# SkyNest M-Pesa Cloudflare Worker

Production-capable Safaricom Daraja STK Push gateway for SkyNest. Each landlord configures their own Safaricom-approved PayBill or Buy Goods Till account. Daraja credentials are encrypted server-side with AES-GCM and are never returned to the Android app.

## Merchant routing

- A tenant's landlord is resolved from the authenticated tenant profile; the client cannot choose or override the destination.
- Each landlord has a separate encrypted Daraja configuration in `landlordPaymentAccounts/{landlordUid}`.
- Only a merchant account verified for the active environment can receive tenant STK requests.
- A KES 1 merchant verification prompt goes to the landlord's phone and is never recorded as rent.
- A successful rent callback is checked against the pending checkout, amount, payer phone and unique receipt before the ledger is updated.
- Duplicate callbacks are idempotent. Failed or cancelled prompts do not create paid rent entries.

A landlord must have a Safaricom-approved Daraja production app and eligible PayBill or Buy Goods integration. A personal M-Pesa number is not an STK merchant shortcode. Do not assume any Till can be used without the matching approved Daraja configuration.

## Cloudflare Worker secrets and variables

Worker name: `mpesaapi`

Configure under Cloudflare > Workers & Pages > skynestmpesaapi > Settings > Variables and Secrets:

- `FIREBASE_PROJECT_ID` — plain text.
- `FIREBASE_WEB_API_KEY` — plain text.
- `FIREBASE_SERVICE_ACCOUNT_JSON` — secret; Firebase service-account JSON with Firestore access.
- `MPESA_ENCRYPTION_KEY` — secret; exactly 32 random ASCII characters. Back it up securely; do not rotate it while encrypted landlord accounts exist.
- `STK_CALLBACK_TOKEN` — secret; random value of at least 32 characters.
- `STK_CALLBACK_URL` — HTTPS URL ending in `/hooks/stk/result/YOUR_RANDOM_TOKEN`; token must match `STK_CALLBACK_TOKEN`.

Daraja Consumer Key, Consumer Secret and Lipa Na M-Pesa Passkey are entered by each landlord in the app and encrypted by the Worker. Never commit secrets or send them in chat.

## API routes

- `GET /health` — Worker health and configured environment.
- `GET /api/mpesa/account` — authenticated landlord's masked account status.
- `POST /api/mpesa/account` — save authenticated landlord's encrypted merchant account.
- `POST /api/mpesa/account/verify` — send landlord KES 1 verification STK.
- `POST /api/mpesa/stkpush` — authenticated active tenant rent STK.
- `POST /hooks/stk/result/<token>` — Safaricom callback.

## Deployment

The Android app calls `https://mpesaapi.bensonwanimo92.workers.dev` by default. The Wrangler Worker name is `mpesaapi` so deployment updates that existing endpoint rather than creating a second Worker. The GitHub Actions deployment workflow is manual and deploys this Worker without simulator, emulator, or test jobs. Configure the Cloudflare API token and account ID as GitHub Actions secrets before running it.

Production mode is selected in `wrangler.toml`. Do not send a real payment until the Worker secrets, callback URL, each landlord's approved live Daraja credentials and the live callback routing are correctly configured.
