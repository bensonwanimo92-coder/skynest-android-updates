# SkyNest M-Pesa Cloudflare Worker

Sandbox-first Daraja STK Push gateway. It avoids Firebase Cloud Functions and can run on Cloudflare Workers.

## Important limit
This first integration uses one Daraja shortcode/passkey. It does NOT make arbitrary landlord Paybill/Till numbers work with one credential. Safaricom C2B URL registration is mapped to each merchant shortcode; multi-landlord production support requires Safaricom-approved platform onboarding or a licensed aggregator. Do not switch to production before approval.

## Worker secrets
Configure these in Cloudflare Worker Settings > Variables and Secrets. Never put them in the APK or chat:
- FIREBASE_PROJECT_ID
- FIREBASE_WEB_API_KEY
- FIREBASE_SERVICE_ACCOUNT_JSON (entire Firebase service-account JSON)
- DARAJA_CONSUMER_KEY
- DARAJA_CONSUMER_SECRET
- DARAJA_SHORTCODE
- DARAJA_PASSKEY
- STK_CALLBACK_URL (public HTTPS URL ending /hooks/stk/result/<token>)
- STK_CALLBACK_TOKEN (same random token as the URL path)

Keep DARAJA_ENV=sandbox for testing.

## Deploy
From this folder, use Wrangler or the Cloudflare dashboard:
1. Create Worker skynest-mpesa-api.
2. Upload src/index.js and set the variables/secrets above.
3. Set STK_CALLBACK_URL to https://YOUR-WORKER.workers.dev/hooks/stk/result/YOUR_RANDOM_TOKEN.
4. Deploy and check GET /health.

## Routes
- GET /health
- POST /api/mpesa/stkpush (Authorization: Bearer Firebase ID token; body: {"amountKes":100,"phone":"2547XXXXXXXX"})
- POST /hooks/stk/result/<token> (Safaricom callback)

An active Firebase tenant profile with role=tenant, status=active and landlordId is required. Successful callbacks create payments/{M-Pesa receipt} in Firestore; duplicate callbacks are ignored.

## Before app testing
The Flutter tenant payment screen still needs to call this Worker endpoint with the signed-in Firebase ID token. After deployment, wire the exact Worker URL into the app build. Then run a sandbox STK request and verify callback + Firestore record. This code alone is not yet an end-to-end tested app release.
