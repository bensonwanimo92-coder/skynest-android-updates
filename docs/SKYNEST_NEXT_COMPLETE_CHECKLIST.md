# SkyNest Next Complete — Master Implementation Checklist

## Live progress — 16 November 2026

- [x] Caretaker tenant-approval shortcut removed from the caretaker dashboard; collection confirmation now checks `can_collect` at the Firestore rules layer, not only in app code. Commits: `120bfef888c39c51a067da7d5553f559b1018ba4`, `daadec809aa253e258d0769ba123fdc346b14833`. Not yet emulator-tested.

- [x] Caretaker/non-landlord tenant approval path blocked in the app UI; approval writes now require the active linked landlord in Firestore rules. Source commits: `74d88846049bdbe66c4f9745ff09b9356a24e66a` (app) and `530318c0ea4fd4ec041c47797a51efcee004cf3e` (rules). Not yet emulator-tested or end-to-end verified.

- [x] Dedicated integration branch established: `integration/skynest-next-complete`.
- [x] Master checklist committed to this branch.
- [x] Dashboard horizontal PageView/3D carousel replaced in the working branch with a vertically stacked ListView of photo-background tiles, grey-toned dark overlay, restrained borders and the existing preview interaction.
- [ ] Dashboard change awaiting CI/build validation and visual review; it is not yet marked tested or verified.
- [ ] Draft PR #20 opened against `integration/skynest-complete-release-candidate`: https://github.com/bensonwanimo92-coder/skynest-android-updates/pull/20
- [ ] Tenant onboarding integration remains outstanding. Current registration still requires invitation codes for both tenants and caretakers. Caretaker invitation must remain mandatory. Tenant signup can only safely remove the invitation requirement once a privacy-preserving landlord/property discovery and approval route is implemented; an unlinked pending tenant must not be able to nominate arbitrary landlord/property IDs or read another account's data.
- [x] Approval-authority hardening implemented in the working branch: the approvals screen blocks non-landlords, the approval action checks for an active landlord, and Firestore tenant-approval writes require the linked landlord UID. Caretaker navigation no longer exposes tenant approvals. Automated/emulator tests and full role-flow verification are still pending.
- [x] Firestore tenant-record creation and reads now scope caretaker access to houses whose `landlordId`/`createdBy` match the caretaker's landlord and whose `caretakerIds` includes that caretaker; tenant reads are limited to their own linked record. Caretaker-created records must identify the caretaker as `createdBy` and include a validated `houseId`. Rules commit `544d8ad7a932a3e36b55be30a991313e0d2bb6a5`. Emulator tests and app-flow integration remain outstanding.
- [x] Added dedicated Firestore role-scope tests for assigned-house caretaker tenant creation, denial for unassigned houses/spoofed landlords, and continued landlord access. Test file: `tests/firestore-role-scope.rules.test.js`; command: `npm run test:role-scope-rules`. Tests have been authored but not executed; emulator validation remains pending.
- [x] Landlord-created tenant records now resolve the entered house number against the landlord's own house records and persist the unique `houseId`; duplicate or unknown house numbers are rejected. Approved house requests now also persist their `houseId` in the tenant record. App commits `d3672a023f79991cbf45059ba677d2bc50874743` and `7f98d642f348ca5d26be05405186844e4e3f575b`. App tests/build and legacy-record migration review remain pending.
- [x] Caretaker payment-confirmation tasks now carry `houseId`; Firestore create/read/confirm rules verify that the caretaker is currently assigned to that exact house under the linked landlord. The app's two task-creation paths now attach the house document ID. Rules/app commits `38ac84087ae5bce9bbb57676ca442f442e6e5ddb` and `768dfe91b2394569395880dbe7a5eaf6885a1377`. Emulator validation is running; caretaker query compatibility and end-to-end payment flow remain pending.
- [x] Caretaker collection permission is now enforced in Firestore as well as the UI: only an active caretaker with `can_collect`, assigned as the record's caretaker and linked to that landlord, can transition a pending confirmation to `confirmed_by_caretaker`. App commit `120bfef888c39c51a067da7d5553f559b1018ba4`; rules commit `daadec809aa253e258d0769ba123fdc346b14833`. Emulator and end-to-end tests remain outstanding.
- [ ] Existing tenant M-Pesa STK path and manual payment-submission path are present, but full tenant/caretaker/landlord reconciliation, cash handover, persistent invoice history and real callback verification remain unproven.
- [ ] Do not create a release APK from this checkpoint; it is an incremental dashboard foundation, not the complete approved release.

Working branch: integration/skynest-next-complete
Baseline: integration/skynest-complete-release-candidate
Known-good installed reference: build 4415
Current candidate reference: build 447 (CI passed; physical installation not confirmed)

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
- [ ] Caretaker sees only assigned properties and relevant tenants.
- [ ] Authorized tenant addition within assigned properties.
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
