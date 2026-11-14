# SkyNest Upgrade Programme

Working branch: `feature/skynest-flexible-dashboard-upgrades`
Baseline: `ae0359d36bbfe8b868f9133e49eed6d988f17a8a` (`integration/roles-on-current-main`)

## Delivery rules
- Keep production and integration branches unchanged while work is developed here.
- Preserve Firebase authentication, role-based access, biometric lock, payment records, call signalling, and existing user data.
- Make small, reviewable changes; run static analysis and tests after each coherent group.
- Do not publish an OTA or APK until the full release candidate passes checks. A Shorebird release is not itself an OTA patch.
- Verify behaviour on physical Android devices for fingerprint, calling audio/video, notifications, and offline access.
- Do not expose private tenant, landlord, payment, or conversation data in public discovery.

## Upgrade backlog

### 1. Login and visual identity
- [x] Apply a premium graphite-and-gold visual refinement to the login header and primary sign-in action. Full responsive/accessibility review remains pending.
- [ ] Complete the broader login screen redesign and responsive verification.
- [ ] Preserve sign-in, registration, password reset, validation, and fingerprint compatibility.
- [ ] Redesign SkyNest logo toward a distinctive, warm, joyful but premium property brand; do not replace production icon until approved.
- [ ] Create separate Benson Wanimo signature identity; do not confuse it with SkyNest branding.

### 2. Dashboard and navigation
- [x] Enlarge dashboard tiles moderately (grid ratio adjusted from 1.12 to 1.02; icon container increased from 54 to 58 logical pixels). Responsive verification remains pending.
- [x] Tile interaction now opens a compact bottom-sheet preview with a downward Continue control; Continue opens the full module. Accessibility/responsive verification remains pending.
- [x] Dashboard grid now adapts to available width using a maximum tile extent; keyboard/screen-reader and device-size verification remain pending.

### 3. Plans and flexible module fields
- [ ] Improve inner Plans tiles/cards (not the semi-main Plans tile).
- [x] Add edit and delete actions for individual plan entries and reminders.
- [x] Add long-press/selection mode and confirmation-protected bulk deletion for plan entries.
- [x] Show created and last-updated timestamps on plan/reminder cards; updates now refresh the timestamp.
- [ ] Audit other modules for similarly rigid fields and missing add/edit/delete, bulk actions, timestamps, filters, and responsive layouts.
- [ ] Preserve role permissions and existing records; avoid destructive schema changes.

### 4. Reading Hub offline downloads
- [ ] Add a persistent in-app My Downloads shelf.
- [ ] Save supported downloadable files locally for genuine offline reading.
- [ ] Show metadata, file availability, reading/open action, delete and re-download controls.
- [ ] Clearly distinguish catalogue links from actual downloaded files.

### 5. Public property discovery
- [ ] Create a public SkyNest Discover experience for approved vacant-house listings.
- [ ] Include property photos, location, rent, bedrooms, amenities, availability, and enquiry/viewing requests.
- [ ] Consider public website/search indexing as well as app discovery.
- [ ] Keep public listing data separate from private tenant, landlord, payment, and account records.

### 6. Sound and interaction feedback
- [ ] Add configurable tap/navigation sounds (a basic system click sound is now triggered on dashboard tile taps; settings and coverage across other navigation controls remain pending).
- [ ] Add outgoing-call ringback and incoming-call ringtone.
- [ ] Add mute and vibration preferences.
- [ ] Stop/release audio cleanly on answer, decline, hang-up, navigation, and app lifecycle changes.

### 7. Calls: real camera and audio/video controls
- [ ] Verify outgoing and incoming audio call flow and audible ringback/ringtone.
- [x] Existing source already requests real device camera capture for video calls using WebRTC camera tracks; device-level verification remains pending.
- [x] Add front/rear camera switch control (committed; device test pending).
- [x] Existing source includes camera enable/disable, microphone mute, and speaker controls; device-level verification remains pending.
- [ ] Handle permissions denied/revoked, camera unavailable, call termination, and resource disposal safely.
- [ ] Test on physical Android devices; do not equate a successful build with working camera/audio.

### 8. Group chat attachments and membership
- [ ] Allow sending images in group conversations.
- [ ] Allow sending PDFs and other supported document attachments.
- [ ] Show safe attachment previews, file names/types/sizes, download/open actions, and upload progress/failure states.
- [ ] Add/verify group member list and member profile access.
- [ ] Enforce membership and storage access rules so only authorized participants can access group files.

### 9. One-to-one direct messages (DMs)
- [ ] Allow a member to start a private one-to-one chat with another group member, similar to WhatsApp.
- [ ] Keep DMs separate from group threads and enforce participant-only access.
- [ ] Support message history, timestamps, delivery/read state where reliable, and notifications.
- [ ] Prevent duplicate one-to-one conversation records for the same participants.

### 10. Main user profiles and profile photos
- [ ] Add a user profile screen with editable profile photo.
- [x] Show available Firebase account/profile photo in the dashboard account avatar and propagate available photo URL to new group messages; full profile photo management and group-member list coverage remain pending.
- [ ] Support upload, replacement, removal/default avatar, image sizing/cropping, and loading/error states.
- [ ] Apply storage and Firestore security rules so users can update permitted profile fields without changing another user's identity.

## Status
The rapid sprint has committed these source changes on this feature branch: front/rear camera switch (`774ca015`); dashboard preview-before-open interaction (`4ec92703`); moderately larger and width-adaptive dashboard tiles (`48e60973`, `5110a88c`); dashboard tile click feedback (`0e463f37`); Plans edit/delete/multi-select and timestamps (`07fb6cec`, `98a84e3a`, `b39befaf`); profile-photo display/propagation where a Firebase photo URL already exists (`f56f7456`); a graphite-and-gold login visual refinement (`527a3230`); and a dedicated branch CI workflow (`c1b47f57`) to run Flutter analysis/tests. CI run #4 completed successfully: dependency resolution, `flutter analyze --no-pub --no-fatal-infos`, and `flutter test --no-pub` all passed. Physical-device testing and a signed Android release build remain outstanding. Profile photo upload, group attachments, private DMs, persistent offline downloads, public property discovery, ringback/ringtones, and remaining responsive/accessibility work are still pending. This document does not claim that the overall upgrade programme is complete, released, or delivered.
