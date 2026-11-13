# SkyNest Next Update — Product & Engineering Scope

This is the consolidated scope requested for the next coordinated SkyNest update. The work is to be implemented together after review; this file is the source of truth for the requested features.

## Functional account and workflow changes

### Account role switching
- Allow a user to switch between Landlord and Tenant while retaining the same Firebase Auth account and sign-in credentials.
- Require a valid invitation and the receiving Landlord's approval when switching into Tenant.
- Prevent switching while property ownership, linked active/pending tenants or caretakers, an assigned tenancy, or pending house requests would orphan records.
- Preserve financial and activity history. Never silently delete or detach business records.
- Caretaker role remains landlord-managed and is not self-selectable.

### Landlord approvals
- Give Landlords a clear dashboard entry to approve/reject pending Tenant and Caretaker applications.
- Show pending state and applicant identity; notify applicants of decisions.
- Only the Landlord associated with the application may approve/reject it.
- Approval of a Caretaker must activate only the properties included in the invitation.
- Keep an auditable activity record.

## Tile redesigns

### House List
1. Staggered fade/slide entrance with 50 ms item delay.
2. Occupancy bar and filled/total units; green at 100%, orange below 50%.
3. Rounded property photo with bottom dark gradient and white house name.
4. Swipe right to edit; swipe left to archive/delete with confirmation.
5. Smart status chip for high occupancy, vacancies, or overdue rent.
6. Press micro-bounce (scale 0.97) and light haptic.
7. Shimmer placeholders while photos load.
8. Quick stats for units, tenants, and monthly collection.
9. Long-press property preview with 2–3 photos.
10. Animated empty state and “Add Your First House” action.
- First visual priority: items 1 and 6.

### Payment Records
1. 4 px left status rail: green Paid, red Overdue, orange Partial, grey Pending.
2. Prominent bold KES amount with due date beneath.
3. Tenant avatar/name and overdue indicator.
4. Swipe right to confirm payment with tick animation and haptic.
5. Subtle overdue pulse only when rent is more than 3 days late.
6. Payment-method icon for M-Pesa, Cash, or Bank.
7. Month chip.
8. Partial-payment amount and progress bar.
9. Expandable receipt with transaction ID, date paid, balance, Print Receipt and Send SMS actions.
10. Three-month on-time payment streak badge.
- First visual priority: items 1, 2 and 4.

### Tenants
1. Green active / grey moved-out indicator.
2. Red debt ribbon.
3. Swipe right to call.
4. Contract countdown.
5. Overdue/New/Vacating filter chips.
6. A–Z fast scroll.
7. Long-press WhatsApp action.
8. Family-count icon.
9. Flip card for unit and balance.
10. Confetti when a tenant is added.

### Tenant Payment Submissions
1. Blur M-Pesa screenshot until tapped.
2. Swipe green approve / red reject.
3. Compare submitted amount with expected amount.
4. Relative submission timer.
5. Double-tap zoom transaction code.
6. Flag reused transaction codes with red border.
7. Batch approve up to five.
8. Cha-ching sound on approval (user-controlled/muteable).
9. Queue position.
10. Shake animation on rejection.
- Payment integrity: duplicate transaction checks and amount validation must be enforced by trusted backend logic, not only by UI.

### Caretakers & Invitations
1. Glowing key for active caretaker.
2. Pulsing orange Pending / solid green Accepted.
3. Permission chips such as Can Collect / View Only.
4. QR code on invitation tile.
5. Swipe left to revoke access, with confirmation.
6. Last-seen indicator (show location only when actually available and consented).
7. Managed-property thumbnail.
8. 24-hour invitation expiry bar.
9. Pulsing Add action.
10. Envelope-to-person acceptance animation.

### Complaints
1. Priority color wash: High red, Low grey.
2. Large water/electricity icon background.
3. Gentle entrance motion for new complaint.
4. Stack 2–3 attached photos.
5. Open-for-days counter.
6. Swipe to resolve with confirmation.
7. Voice-note waveform.
8. Anonymous-report mask icon.
9. Escalation fire icon.
10. Lottie tick on resolution.

### Tenant Groups
1. Three overlapping member avatars.
2. Member-count bubble.
3. Pulsing megaphone during broadcast.
4. Total due summary.
5. Estate-specific color.
6. Long-press multi-select mode.
7. Empty-group ghost icon.
8. Blue unread-message dot.
9. Swipe right to broadcast.
10. Taller card for larger groups.

### Notices
1. Always-visible pin.
2. Seen X/Y progress bar.
3. Expired notices fade grey.
4. Type colors (Eviction red, Meeting blue).
5. PDF attachment count.
6. Tomorrow clock badge.
7. Resend to unseen recipients.
8. Urgent notice attention animation on open.
9. Large image banner when attached.
10. View count.

### Utilities
1. Animated meter numbers.
2. Red glow on overuse.
3. Circular balance ring.
4. Clear kWh/litres units.
5. Gentle warning animation below balance 20.
6. In-tile Top Up action.
7. Weekly mini sparkline.
8. Grey/off state when disconnected.
9. Bill-due chip.
10. Lightning pulse during outage.

### Reports
1. Amount sparkle.
2. Month-on-month percentage and direction arrow.
3. Swipe to export PDF.
4. Mini bar-chart backdrop.
5. Crown for highest-earning property.
6. Tappable This Month filter.
7. Red loss indicator.
8. Best Tenant badge.
9. Property filter.
10. Print action on tile.

## Cross-cutting quality and safety requirements
- Keep all totals, occupancy, balances, streaks, transaction status and reports derived from Firestore records; do not invent demo values in production UI.
- Every swipe action that changes money, access, tenancy, complaints or notices must have clear confirmation and authorization.
- Respect role-based Firestore rules and tenant privacy; never expose another tenant's receipt or personal details.
- Add accessible labels and non-color status cues; honor reduced-motion/system sound preferences where practical.
- Loading, empty, error, offline and permission-denied states must be designed for every tile.
- Keep expensive animations and image loading efficient on lower-end Android devices.
- Shorebird is for compatible Dart/UI changes. Firebase Functions, Firestore rules/indexes, native Android/plugin changes, and other server-side work must be deployed through their appropriate pipelines; an OTA patch alone cannot deliver those backend/native changes.

## Delivery acceptance
- Format and static analysis pass.
- Build and signing pass.
- Verify Firestore rules/functions deployment separately from the APK/OTA.
- Publish only verified APK/ZIP/release links.
- Emulator test may be skipped per the user's previously stated preference; report that limitation clearly and do not claim device verification.
