# SkyNest Next Complete — Master Implementation Checklist

## Live progress — 16 November 2026

- [x] Tenant email onboarding now covers both new tenant registration and landlord-to-tenant role switching: tenant supplies the landlord's registered email, the server resolves one active landlord, creates a pending linked request, and the landlord retains approval authority. Caretaker registration still requires a valid single-use invitation. Release-candidate checks including Flutter analysis/tests and Cloud Functions syntax passed on commit `5d9a51a0ad189bcc62ee87fd49c7e7f5cb02d12a` (run `43881970973`); the later integrated ledger checks also passed.
- [x] Rent ledger now persists a fixed monthly invoice snapshot the first time the landlord opens the ledger for an active tenant with a verified assigned house. The snapshot stores rent-at-issue and is immutable; tenants can read only invoices linked to their UID. Firestore emulator tests passed on run `43882836632`; Flutter analysis/tests and Cloud Functions syntax passed on run `43882824523`. Legacy historical periods without saved rent snapshots are explicitly labelled **DUE UNKNOWN** rather than being falsely treated as overpayments or reconstructed using today's rent. A controlled historical backfill and automatic month-start invoice generation are still outstanding.
- [x] Added a manual-approval GitHub Actions workflow for deploying both `requestTenantAccess` and `changeAccountRole` callables: `.github/workflows/deploy-tenant-onboarding.yml`. This workflow has not been dispatched; production callable deployment remains pending and requires the configured Firebase project credentials.
- [x] Tenant onboarding implementation added on the integration branch: registration now requests the landlord's email rather than an invitation code; a Firebase callable performs server-side active-landlord resolution and creates a pending, landlord-linked tenant profile. Caretaker invitation validation remains mandatory. Commits: `63d9e34f0bfc585b98ea976f294558367a58b8cc`, `c94f41dac1a7f8641f0fcf3945a21d72bd73dd0c`, `d02325ef021acc0d9241b82e068360c7846e4589`, `a958656a0719b4694d2f3cf6789844cdb6b263d4`. Added Node syntax validation to release-candidate checks (`3cb7df32a44767071a8e07c657a027c0d0b54a0e`). Deployment and live callable verification are still required.
- [x] Rent-ledger status parsing now uses an explicit allowlist of confirmed receipt states; labels such as `unpaid`, `pending verification`, `failed` and unknown values cannot be counted as received. Added regression tests. Flutter analysis/tests passed on final source commit `ebb7211e8dde5ec0ccd1e4c9d5c1b400462c6071` (run `43879558314`).
- [x] Payment-record reads are now role-scoped: landlords can query records linked to their landlord UID, and tenants can read only records carrying their own tenant UID. Emulator tests cover own payment, another tenant's payment, legacy records without tenant links, and landlord query scope. Firestore emulator suite passed on final source commit (run `43879558227`). Legacy payment records without a `tenantId` remain landlord-only until safely backfilled.

- [x] Caretaker tenant-approval shortcut removed from the caretaker dashboard; collection confirmation now checks `can_collect` at the Firestore rules layer, not only in app code. Commits: `120bfef888c39c51a067da7d5553f559b1018ba4`, `daadec809aa253e258d0769ba123fdc346b14833`. Not yet emulator-tested.

- [x] Caretaker/non-landlord tenant approval path blocked in the app UI; approval writes now require the active linked landlord in Firestore rules. Source commits: `74d88846049bdbe66c4f9745ff09b9356a24e66a` (app) and `530318c0ea4fd4ec041c47797a51efcee004cf3e` (rules). Not yet emulator-tested or end-to-end verified.

- [x] Tenant house visibility now allows an active tenant to read the exact occupied house assigned to their UID, while denying access to another tenant's occupied house. Firestore rules commit `77ab8b1684a20946ca8b3e114eaa8611195fe9c0`; emulator test added in `ca8b6e3fb059b664bf70af6cbfc353ca4beaa9ef`. Latest integration-head emulator workflow passed on run `43878012088` (commit `ee9106bd24`).
- [x] Dedicated integration branch established: `integration/skynest-next-complete`.
- [x] Master checklist committed to this branch.
- [x] Dashboard horizontal PageView/3D carousel replaced in the working branch with a vertically stacked ListView of photo-background tiles, grey-toned dark overlay, restrained borders and the existing preview interaction.
- [x] Dashboard source CI passed on integration commit `ee9106bd24` (release candidate checks run `43878000809`). APK packaging from this branch, physical installation, and visual review remain pending; it is not yet marked verified.
- [x] Draft PR #20 opened against `integration/skynest-complete-release-candidate`: https://github.com/bensonwanimo92-coder/skynest-android-updates/pull/20. Keep it unmerged until the complete release scope and gates pass.
- [x] Tenant signup no longer requires an invitation code: the tenant enters the landlord's registered email, and the authenticated `requestTenantAccess` callable resolves exactly one active landlord server-side, creates a pending tenant profile linked to that landlord, and leaves approval to the landlord. The tenant cannot submit arbitrary landlord/property IDs. Caretaker signup still requires a valid, single-use caretaker invitation. Client handling is retry-safe if the callable response is interrupted. Flutter/Node syntax checks are being run; Firebase Functions deployment and live registration/approval verification remain pending. The self-service landlord-to-tenant role-switch path now uses the same landlord-email lookup and approval flow; caretaker invitation remains mandatory.
- [x] Approval-authority hardening implemented in the working branch: the approvals screen blocks non-landlords, the approval action checks for an active landlord, and Firestore tenant-approval writes require the linked landlord UID. Caretaker navigation no longer exposes tenant approvals. Firestore emulator tests passed on run 43877400028; Android UI and full role-flow verification remain pending.
- [x] Closed a caretaker privilege gap: caretaker house updates are now limited to occupancy/status fields and cannot set, replace or clear `assignedTenantId`; landlord assignment remains permitted. Regression coverage passed in Firestore emulator run 43877400028.
- [x] Firestore tenant-record creation and reads now scope caretaker access to houses whose `landlordId`/`createdBy` match the caretaker's landlord and whose `caretakerIds` includes that caretaker; tenant reads are limited to their own linked record. Caretaker-created records must identify the caretaker as `createdBy` and include a validated `houseId`. Rules commit `544d8ad7a932a3e36b55be30a991313e0d2bb6a5`. The expanded role-scope emulator suite passed on the current integration head (run 43876075510); app-flow integration and legacy-record compatibility remain outstanding. Caretaker-created tenant records must also match the assigned house's actual house number and configured rent, preventing a caretaker from inventing a unit or changing its rent amount.
- [x] Added dedicated Firestore role-scope tests for assigned-house caretaker tenant creation, denial for unassigned houses/spoofed landlords, and continued landlord access. Test file: `tests/firestore-role-scope.rules.test.js`; command: `npm run test:role-scope-rules`. The updated integration-head Firestore emulator workflow passed on run 43877400028, executing marketplace rules, role-scope rules and Storage rules. The Android Dart analysis/Flutter test workflow also passed (run 43877399724), and M-Pesa Worker syntax/unit tests passed (run 43877399715). These are automated checks, not physical-device verification, production deployment or full live payment-flow confirmation.
- [x] Landlord-created tenant records now resolve the entered house number against the landlord's own house records and persist the unique `houseId`; duplicate or unknown house numbers are rejected. Approved house requests now also persist their `houseId` in the tenant record. App commits `d3672a023f79991cbf45059ba677d2bc50874743` and `7f98d642f348ca5d26be05405186844e4e3f575b`. App tests/build and legacy-record migration review remain pending.
- [x] Caretaker payment-confirmation tasks now carry `houseId`; Firestore create/read/confirm rules verify that the caretaker is currently assigned to that exact house under the linked landlord. The app's two task-creation paths now attach the house document ID. Rules/app commits `38ac84087ae5bce9bbb57676ca442f442e6e5ddb` and `768dfe91b2394569395880dbe7a5eaf6885a1377`. The updated integration-head Firestore emulator workflow passed on run 43877400028; caretaker query compatibility and end-to-end payment flow remain pending. The caretaker confirmation screen now filters by caretaker UID, landlord ID and invited `propertyIds` to satisfy the same rules; it currently reports a clear limitation above 30 assigned houses pending paginated multi-query support. Manual landlord rent records and landlord-verified tenant submissions now resolve and persist a unique landlord-owned `houseId`; Firestore payment creation requires the authenticated landlord, matching landlord ID, and matching house document/house number. Emulator test added for valid, spoofed-house and caretaker payment creation. Tenant rent-submission rules now also require the authenticated tenant's own `houseId`, `houseNo`, landlord link and matching `assignedTenantId` on the house document; emulator coverage added for wrong-house, wrong-unit and wrong-landlord attempts. The current integration-head emulator suite passed on run 43876075510, including wrong-house, wrong-unit and wrong-landlord denials; live tenant payment submission remains unverified.
- [x] Cloudflare M-Pesa STK requests now verify the tenant profile's active status, exact house ID/number, landlord ownership and `assignedTenantId` against the live house document before sending a Daraja prompt. Added unit tests for valid, unassigned, wrong-landlord, mismatched-unit and missing-assignment cases. Worker syntax and unit-test CI passed on the latest integration head (run 43877399715). Cloudflare deployment, live Daraja sandbox STK request, callback delivery and end-to-end app verification remain pending.

- [x] Caretaker collection permission is now enforced in Firestore as well as the UI: only an active caretaker with `can_collect`, assigned as the record's caretaker and linked to that landlord, can transition a pending confirmation to `confirmed_by_caretaker`. App commit `120bfef888c39c51a067da7d5553f559b1018ba4`; rules commit `daadec809aa253e258d0769ba123fdc346b14833`. The current emulator suite passed on run 43876075510; complete caretaker-to-landlord cash handover and live end-to-end collection remain outstanding.
- [ ] Existing tenant M-Pesa STK path and manual payment-submission path are present. Persistent monthly invoice snapshots now exist for eligible current periods, but automated month-start generation, historical invoice backfill, full tenant/caretaker/landlord reconciliation, caretaker cash handover and real callback verification remain unproven.
- [ ] Do not create a release APK from this checkpoint; it is an incremental dashboard foundation, not the complete approved release.

Working branch: integration/skynest-next-complete
Baseline: integration/skynest-complete-release-candidate
Known-good installed reference: build 4415
Last pre-integration APK candidate: version 1.1.3+5447, run 43862420394, artifact ID 14223558387, built from baseline branch `integration/skynest-complete-release-candidate` (not the current next-complete branch). CI verified package `com.hello22_.chuka`, the original signing certificate, ARM64 and ARMv7 ABIs, minSdk 24 and targetSdk 35. Physical installation was not confirmed; do not treat this as the completed next-release APK.

## Delivery rules
- This branch is the sole working integration target for the next complete Android release.
- Do not publish or compile a user-facing APK until the approved scope is integrated and release checks pass.
- Do not mark an item complete because a screen or model exists; require integration and relevant tests.
- Preserve existing Firebase data, authentication, package ID, signing identity and working user flows.
- Do not blindly merge divergent feature branches; port and reconcile changes selectively.
- Do not reintroduce superseded dashboard layouts or old concepts.
- Preserve the collected 100 tile redesign ideas as unimplemented unless separately authorized.

## 1. Dashboard and visual design
- [ ] Classic, refined, premium visual identity; avoid generic solid cards.
- [ ] Latest grey-toned visual reference as the style direction; use judgment only where the exact reference asset is unavailable.
- [ ] Main dashboard sections flow vertically down the screen; no circular layout.
- [ ] Group related functions logically and combine related tiles where appropriate.
- [ ] Clear typography, restrained depth, borders, shadows and readable contrast.
- [ ] Responsive layouts and accessibility checks.
- [ ] Premium login redesign, preserving sign-in, registration, password reset and biometric flows.
- [ ] Tile preview/Continue interaction only where it remains part of the latest approved scope; verify against current source before implementing.

## 2. Landlord account
- [ ] Property, house and House Catalogue management.
- [ ] Tenant management and correct house assignment.
- [ ] Caretaker invitations, assigned houses, permission management and revocation.
- [ ] Rent collection, verification, ledger, statements and reports.
- [ ] Notices, complaints, plans and reminders.
- [ ] M-Pesa merchant account configuration and reconciliation.
- [ ] Control Centre, notification management and backups.
- [ ] Auditable financial and administrative actions.

## 3. Tenant account
- [ ] View own profile, assigned house, rent amount and rent period.
- [ ] View own verified payments, balance, credit and receipts.
- [ ] Make full, partial and instalment payments through the existing payment architecture.
- [ ] Initiate landlord-routed M-Pesa STK Push; never choose or override the receiving landlord.
- [ ] View pending, successful, failed and reversed transaction states.
- [ ] Submit promised payment dates and receive relevant reminders.
- [ ] Tenant registration/onboarding must not require an invitation code (planned requirement).
- [ ] Tenant cannot modify landlord records or payment verification.

## 4. Caretaker account and permissions
- [ ] Landlord-created invitation; 24-hour expiry and acceptance.
- [ ] Caretaker remains linked to the correct landlord.
- [ ] Landlord assigns specific houses.
- [ ] Permission levels: Can Collect and View Only.
- [x] Caretaker house-request reads are restricted to their assigned house IDs; only landlords can approve/decline requests or change a tenant's house assignment. The caretaker screen now shows assigned-house requests without approval controls. Firestore emulator tests passed on run 43877400028; production index deployment and full end-to-end role-flow verification remain pending.
- [ ] Authorized tenant addition within assigned properties.
- [x] Corrected caretaker cash-collection and handover history streams to include the selected assigned `houseId`, matching the Firestore rule query constraints; history is now shown per selected house rather than issuing an over-broad multi-house query. Automated release-candidate and rules tests are running for commit `d9603bad267740286700e3c01492fc2881e449d8`.
- [x] Cash collection records now use the assigned tenant's profile name rather than free-text caretaker input, preventing avoidable tenant-name mismatches in handover reconciliation; missing tenant profiles are handled without crashing the screen. Latest Flutter and Firestore CI validation is pending.
- [ ] Record permitted collections with tenant, house, amount, date, method and collector.
- [ ] Caretaker cannot change landlord financial totals, verify own collections or access unassigned properties.
- [ ] Landlord can revoke access.
- [ ] Audit log for important caretaker actions.
- [ ] Caretaker onboarding continues to require an invitation code.

## 5. Three-account money flow and reconciliation
- [ ] Tenant digital rent payment goes to the landlord's configured merchant account.
- [ ] Tenant cash/physical payment can be recorded by an authorized caretaker.
- [ ] Caretaker collection record identifies tenant, house, amount, date, method and collector.
- [ ] Landlord can verify and reconcile caretaker-recorded collections.
- [ ] Cash handover from caretaker to landlord can be recorded with amount, date and acknowledgement.
- [ ] Track collected, handed-over and outstanding-to-handover amounts without treating caretaker as owner of funds.
- [ ] Every transaction has a unique reference and duplicate protection.
- [ ] Pending, confirmed, failed and reversed states handled correctly.
- [ ] Partial payments, instalments, overpayments, credits and reversals reconcile correctly.
- [ ] Landlord sees consolidated property finances.
- [ ] Caretaker sees only assigned-house information.
- [ ] Tenant sees only their own financial information.
- [ ] Every financial adjustment has an auditable actor, timestamp and reason.

## 6. Complete rent ledger
- [ ] Persisted rent invoices/period records.
- [ ] Historical rent rate preserved per period; do not reconstruct old invoices from today's rent.
- [ ] Full, partial and instalment payment allocation.
- [ ] Outstanding balances, tenant credits and overpayments.
- [ ] Promised payment dates and reminder status.
- [ ] Receipts and transaction history.
- [ ] Cash versus digital payment distinction.
- [ ] Reconciliation and exportable statements/reports.
- [ ] Role-scoped ledger access and Firestore rules.
- [ ] Tests for calculations, allocation, reversals, duplicate callbacks and access restrictions.

## 7. M-Pesa
- [ ] Landlord PayBill/Till setup and secure credential handling.
- [ ] Merchant verification and environment binding.
- [ ] Authenticated tenant STK request resolved to the correct landlord.
- [ ] Callback validation, unique receipt and duplicate protection.
- [ ] Payment status reflected accurately in tenant, caretaker (where permitted) and landlord views.
- [ ] Sandbox end-to-end tests before production.
- [ ] Deploy API/Worker and secrets only through authorized secure configuration; never commit or request secrets in chat.

## 8. Other approved modules
- [ ] Plans and Reminders.
- [ ] Activity Log.
- [ ] Property Reports.
- [ ] Complaints and Notices.
- [ ] Tenant Groups.
- [ ] Control Centre, notification management, automations and backups.
- [ ] Messaging, attachments and voice messages.
- [ ] Calls and media features.
- [ ] Marketplace Inventory connected to approved website adverts through shared Firebase data.
- [ ] Website advertiser submission for multiple categories and rich media.
- [ ] Marketplace moderation, approval, expiry and tier prioritization.
- [ ] Media Centre and Reading Hub/offline downloads where part of the current approved branch scope.

## 9. Release gate
- [ ] Audit all feature branches and PRs; record source, conflicts and selected changes.
- [ ] Reconcile Dart dependencies, Android build configuration, Firestore rules and indexes.
- [ ] Run Dart analysis and all Flutter tests.
- [ ] Run Firestore emulator/security tests.
- [ ] Run payment/API tests.
- [ ] Verify landlord, tenant and caretaker flows independently and together.
- [ ] Verify responsive dashboard and visual acceptance.
- [ ] Verify Android package ID, signing certificate, ABI coverage and version code.
- [ ] Verify in-place upgrade from known-good build 4415 without uninstalling or wiping user data.
- [ ] Only then produce and publish one complete APK; clearly report any remaining unverified external deployment or real-device test.

## Status convention
- Not started: no verified work.
- Implemented: source code exists.
- Integrated: connected to the working app and backend.
- Tested: relevant automated tests pass.
- Verified: end-to-end behaviour confirmed on the required environment/device.

An item is not complete until the required integration, tests and verification are recorded.
