# SkyNest M-Pesa API — Google Cloud Run

This is the Cloud Run deployment of the SkyNest M-Pesa STK Push API. It keeps Daraja and Firebase service-account credentials on the server and uses Firebase Auth to identify the signed-in tenant.

## Free-tier note

Cloud Run has an always-free request-based allowance: 2 million requests, 180,000 vCPU-seconds and 360,000 GiB-seconds of memory per month. A Google Cloud billing account is still required. Usage above the allowance, network egress outside the included allowance, Artifact Registry storage, or other Google Cloud services can incur charges. Set a budget alert before deployment and keep minimum instances at zero.

## Configure Cloud Run environment variables and secrets

Set these on the Cloud Run service after first deployment:

- `FIREBASE_PROJECT_ID` (plain text)
- `FIREBASE_WEB_API_KEY` (plain text)
- `FIREBASE_SERVICE_ACCOUNT_JSON` (secret)
- `DARAJA_ENV=sandbox` (plain text)
- `DARAJA_CONSUMER_KEY` (secret)
- `DARAJA_CONSUMER_SECRET` (secret)
- `DARAJA_SHORTCODE` (plain text or secret)
- `DARAJA_PASSKEY` (secret)
- `STK_CALLBACK_TOKEN` (secret, random value of at least 32 characters)
- `STK_CALLBACK_URL` (HTTPS URL ending in `/hooks/stk/result/<STK_CALLBACK_TOKEN>`)

Use Secret Manager-backed environment variables for secrets. Do not put secrets in GitHub source, commit files, or send them in chat.

## Deploy from GitHub Actions

Create these GitHub repository secrets:

- `GCP_PROJECT_ID`
- `GCP_REGION` (for example `africa-south1`)
- `GCP_SA_KEY` (JSON key for a dedicated deployment service account)

The service account needs permissions to build and deploy Cloud Run from source, including Cloud Run Admin, Service Account User, and the required Cloud Build / Artifact Registry permissions.

Then run the workflow named **Deploy SkyNest M-Pesa API to Google Cloud Run** from GitHub Actions.

## API routes

- `GET /health`
- `POST /api/mpesa/stkpush` — Firebase ID token required
- `POST /hooks/stk/result/<token>` — Safaricom STK callback

Keep Daraja in sandbox until STK prompt, callback processing, and Firestore payment visibility have all been tested. A successful health check alone does not prove payments work.
