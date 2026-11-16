# SkyNest M-Pesa Cloudflare Worker

Sandbox-first Daraja STK Push gateway for SkyNest. The Worker keeps Daraja and Firebase service credentials server-side and uses Firebase Auth to identify the signed-in tenant. It does not require Firebase Cloud Functions.

## Scope and merchant limitation

This deployment is **single-merchant / single-shortcode**. It is not yet the multi-landlord Paybill/Till platform. Each landlord cannot safely use a different shortcode with the same Daraja shortcode/passkey. Multi-merchant routing requires Safaricom-approved platform onboarding and merchant credential handling, or an approved aggregator. Do not collect landlord Daraja secrets in the Android app or store them as plain Firestore fields.

This version supports tenant STK Push only. C2B callbacks, Paybill/Till merchant selection, Ratiba standing orders, refunds, and automated instalment scheduling are not implemented.

## Configure Worker

Worker name: `skynestmpesaapi`

Set these under Cloudflare > Workers & Pages > skynestmpesaapi > Settings > Variables and Secrets:

- `FIREBASE_PROJECT_ID` (plain text)
- `FIREBASE_WEB_API_KEY` (plain text)
- `FIREBASE_SERVICE_ACCOUNT_JSON` (secret; full service-account JSON)
- `DARAJA_ENV` = `sandbox` (plain text)
- `DARAJA_CONSUMER_KEY` (secret)
- `DARAJA_CONSUMER_SECRET` (secret)
- `DARAJA_SHORTCODE` (plain text or secret)
- `DARAJA_PASSKEY` (secret)
- `STK_CALLBACK_TOKEN` (secret, random value of at least 32 characters)
- `STK_CALLBACK_URL` (plain text HTTPS URL)

The callback URL must be:
`https://YOUR-WORKER.workers.dev/hooks/stk/result/YOUR_RANDOM_TOKEN`

The token in the URL must exactly match `STK_CALLBACK_TOKEN`. Do not paste any secret into chat, GitHub source files, or the Android app.

## Deploy

From this folder with Wrangler authenticated:

```sh
npm install
npm run check
npx wrangler deploy
```

Or connect the GitHub repository in Cloudflare Workers Builds and set the project root to `cloudflare-worker`, with deploy command `npx wrangler deploy`. Do not deploy the production service until the secrets above are configured. Keep `DARAJA_ENV=sandbox`.

## Routes

- `GET /health` — health response (does not prove Firebase or Daraja credentials are valid)
- `POST /api/mpesa/stkpush` — requires `Authorization: Bearer <Firebase ID token>` and JSON body `{"amountKes":100,"phone":"2547XXXXXXXX"}`
- `POST /hooks/stk/result/<token>` — Safaricom STK callback

An active user document in `users/{uid}` with `role=tenant`, `status=active`, and `landlordId` is required. A successful callback creates `payments/{M-Pesa receipt}` using the fields consumed by the existing SkyNest landlord Payments screen, including `tenantName`, `createdBy`, `houseNo`, `amount`, `method`, `transactionCode`, `status`, and Firestore timestamps.

The callback handler parks very early callbacks in `mpesaCallbackInbox` and replays them after the pending checkout is saved. Duplicate callbacks are made idempotent by the checkout status and receipt document ID. The callback URL token is a bearer secret; keep it private and rotate it if exposed.

## Verification checklist

1. Deploy to Cloudflare and confirm `GET /health`.
2. Confirm Worker secrets are configured without sharing them.
3. Use Daraja sandbox credentials and a sandbox test MSISDN.
4. Confirm the STK prompt appears.
5. Confirm callback changes `mpesaPaymentRequests/{CheckoutRequestID}` to `confirmed`.
6. Confirm exactly one `payments/{receipt}` document appears and is visible to the landlord in SkyNest.
7. Confirm a failed/cancelled prompt creates no paid rent record.

A green health response alone is not an end-to-end payment test. Do not switch to production or merge/release until sandbox callback and Firestore visibility have both been verified.
