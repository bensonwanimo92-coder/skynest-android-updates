# SkyNest Android

Flutter rental-management application. The Android application ID must remain `com.hello22_.chuka` so signed releases can update the existing installation.

## Included modules
- Firebase email/password sign-in, account creation and password reset
- Houses and tenant records stored in Cloud Firestore
- Payment ledger (manual records remain **Pending verification**)
- Rent calculator and payment calendar
- Plans/reminders, achievement counts, pamphlets and selectable themes
- Google Mobile Ads integration currently uses Google's **test** banner unit

## Firebase setup required
The repository intentionally does not contain a Firebase project configuration. To enable authentication and Firestore:

1. In Firebase Console, open the Firebase project and add an Android app with package name `com.hello22_.chuka`.
2. Download that app's `google-services.json`.
3. Convert the file to Base64 using a trusted local/offline Base64 encoder. Do not paste passwords or keystore contents into chat.
4. In GitHub repository Settings → Secrets and variables → Actions, add a repository secret named `FIREBASE_ANDROID_CONFIG_BASE64` and paste the Base64 output.
5. Publish the rules in `firestore.rules` to the project's Cloud Firestore database.

Without that secret, the build can be checked, but the app will display a Firebase setup warning and the workflow will not publish a release APK.

## Important payment and subscription limitations
- The tenant **My rent & balance** screen can initiate an authenticated M-Pesa STK Push through the Cloudflare Worker. The Worker resolves the tenant's linked landlord and requires that landlord's merchant account to be verified for the active environment. A request is not a confirmed payment: only a validated Safaricom callback creates the receipt-backed payment record. Sandbox/live deployment and end-to-end callback verification are still required.
- Premium status is read from `subscriptions/{uid}.isPremium`; the app does not let a client grant itself Premium. A trusted admin/server must update this field after payment verification.
- Live M-Pesa and subscription payments need a secure backend; Daraja secrets must never be embedded in the Flutter app.

## Firestore data ownership
The app writes a `createdBy` UID to houses, tenants, plans and payment records, and queries only the signed-in user's records. Deploy `firestore.rules` before using the app with real tenant information.
