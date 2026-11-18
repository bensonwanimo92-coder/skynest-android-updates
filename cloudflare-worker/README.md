# SkyNest M-Pesa Cloudflare Worker

SkyNest uses one centrally managed Safaricom Daraja integration. Landlords enter only their PayBill number or Buy Goods Till number; they never provide Consumer Keys, Consumer Secrets or Passkeys.

## Merchant routing

- A tenant's landlord is resolved from the authenticated tenant profile; the client cannot choose or override the destination.
- Each landlord has a receiving-account record in `landlordPaymentAccounts/{landlordUid}`. Only the receiving-account identifiers are stored.
- Only a merchant account verified for the active environment can receive tenant STK requests.
- A KES 1 merchant verification prompt goes to the landlord's phone and is never recorded as rent.
- A successful rent callback is checked against the pending checkout, amount, payer phone and unique receipt before the ledger is updated.
- Duplicate callbacks are idempotent. Failed or cancelled prompts do not create paid rent entries.

Do not enable central merchant routing until Safaricom confirms the SkyNest aggregator/sub-merchant arrangement, shortcode mapping, settlement behavior and callback model in writing. A Till uses its approved head-office shortcode in `BusinessShortCode` and the Till in `PartyB`; arbitrary Till numbers cannot be assumed to belong to SkyNest's head office.

## Cloudflare Worker secrets and variables

Worker name: `mpesaapi`

Configure under Cloudflare > Workers & Pages > skynestmpesaapi > Settings > Variables and Secrets:

- `FIREBASE_PROJECT_ID` — plain text.
- `FIREBASE_WEB_API_KEY` — plain text.
- `FIREBASE_SERVICE_ACCOUNT_JSON` — secret; Firebase service-account JSON with Firestore access.
- `MPESA_ENCRYPTION_KEY` — secret; exactly 32 random ASCII characters. Back it up securely; do not rotate it while encrypted landlord accounts exist.
- `STK_CALLBACK_TOKEN` — secret; random value of at least 32 characters.
- `STK_CALLBACK_URL` — HTTPS URL ending in `/hooks/stk/result/YOUR_RANDOM_TOKEN`; token must match `STK_CALLBACK_TOKEN`.

All Daraja credentials are central SkyNest Cloudflare secrets. Landlords enter only PayBill or Till details. Never commit secrets or send them in chat. Standard STK Push does not let an API client redirect funds to arbitrary merchant shortcodes merely by changing `PartyB`; direct settlement needs Safaricom-approved merchant routing.

## API routes

- `GET /health` — Worker health and configured environment.
- `GET /api/mpesa/account` — authenticated landlord's masked account status.
- `POST /api/mpesa/account` — save authenticated landlord's encrypted merchant account.
- `POST /api/mpesa/account/verify` — send landlord KES 1 verification STK.
- `POST /api/mpesa/stkpush` — authenticated active tenant rent STK.
- `POST /hooks/stk/result/<token>` — Safaricom callback.

## Deployment

The Android app calls `https://mpesaapi.bensonwanimo92.workers.dev` by default. The Wrangler Worker name is `mpesaapi` so deployment updates that existing endpoint rather than creating a second Worker. The GitHub Actions deployment workflow is manual and runs the Worker syntax checks and pure Node validation tests before deployment. These checks do not launch a simulator or emulator. Configure the Cloudflare API token and account ID as GitHub Actions secrets before running it.

Production mode is selected in `wrangler.toml`. Do not send a real payment until SkyNest central production credentials, callback URL and Safaricom-approved merchant routing are configured. The code deliberately rejects payment and verification requests while merchant routing is disabled.

## Validation

From this directory, run `npm run check`. It checks Worker JavaScript syntax and runs the built-in Node.js test suite for callback, tenant-house assignment and merchant-account validation. The deployment workflow requires these checks to pass before Wrangler can deploy the Worker.
