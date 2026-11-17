# SkyNest live M-Pesa setup

SkyNest M-Pesa runs through the existing Cloudflare Worker at `https://mpesaapi.bensonwanimo92.workers.dev`. The Android app calls this API directly with the signed-in user's Firebase ID token. Firebase Functions are not used for M-Pesa deployment.

## Production configuration

- Cloudflare Worker name: `mpesaapi`
- Daraja environment: `production` (set in `cloudflare-worker/wrangler.toml`)
- Firestore: retains tenant profiles, landlord merchant account metadata, pending checkout records, callback inbox and confirmed rent ledger.
- Merchant credentials: one central SkyNest Daraja Consumer Key, Consumer Secret and Passkey are held only as Cloudflare secrets. Landlords enter only their receiving PayBill number or Buy Goods Till number. The Worker never requests landlord API credentials.

## Cloudflare Worker secrets

Configure these in Cloudflare Worker settings. Do not commit or paste secret values into chat:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_WEB_API_KEY`
- `FIREBASE_SERVICE_ACCOUNT_JSON` (secret)
- `MPESA_ENCRYPTION_KEY` (secret; 32 random ASCII characters; preserve it to decrypt existing landlord configurations)
- `STK_CALLBACK_TOKEN` (secret; at least 32 random characters)
- `STK_CALLBACK_URL` (HTTPS callback URL ending in `/hooks/stk/result/<token>`, with the same token)

The Firebase service account needs Firestore access to the SkyNest project. The Cloudflare Worker uses the Firestore REST API; it does not require Firebase Cloud Functions or Secret Manager.

## Live merchant flow

1. Landlord signs in and opens M-Pesa collection setup.
2. Landlord enters their own Safaricom-approved PayBill or Buy Goods Till details and live Daraja credentials.
3. Worker encrypts and saves the merchant configuration.
4. Landlord initiates the KES 1 receiving-account verification prompt. This is a real payment to the configured merchant and is not entered as rent.
5. Once the verified status is recorded for production, linked active tenants can request rent STK Push.
6. Safaricom callback is checked against the pending checkout, merchant request, amount, payer phone and receipt. Only a confirmed callback creates the rent ledger entry.

Important: one central Daraja API does not automatically authorize STK Push to arbitrary PayBills/Tills. Safaricom must approve SkyNest as an aggregator or enable the specific sub-merchant/shortcode routing and settlement model. Until then, the Worker fails closed and sends no payment. Do not enable the flag based only on having central API keys.

## Deploy

GitHub Actions includes the manual workflow **Deploy SkyNest M-Pesa Cloudflare Worker**. It requires repository secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`. The workflow deploys the Worker directly and does not run tests or emulator jobs. Cloudflare runtime secrets listed above must already be configured.

A successful deployment or `/health` response confirms only that the Worker is reachable. It does not prove that Safaricom credentials, callback routing or a merchant account are live. Do not initiate a real tenant payment until those production settings are in place.
