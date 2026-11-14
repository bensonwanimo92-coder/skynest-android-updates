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
- [ ] Redesign login screen to a polished, high-end responsive experience.
- [ ] Preserve sign-in, registration, password reset, validation, and fingerprint compatibility.
- [ ] Redesign SkyNest logo toward a distinctive, warm, joyful but premium property brand; do not replace production icon until approved.
- [ ] Create separate Benson Wanimo signature identity; do not confuse it with SkyNest branding.

### 2. Dashboard and navigation
- [x] Enlarge dashboard tiles moderately (grid ratio adjusted from 1.12 to 1.02; icon container increased from 54 to 58 logical pixels). Responsive verification remains pending.
- [x] Tile interaction now opens a compact bottom-sheet preview with a downward Continue control; Continue opens the full module. Accessibility/responsive verification remains pending.
- [ ] Keep the interaction accessible, keyboard/screen-reader friendly, and responsive across screen sizes.

### 3. Plans and flexible module fields
- [ ] Improve inner Plans tiles/cards (not the semi-main Plans tile).
- [ ] Add, edit, delete individual plan entries.
- [ ] Support safe multi-select and bulk deletion with confirmation.
- [ ] Show created and last-updated timestamps.
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
- [ ] Show profile photo alongside the user's name in chats, group member lists, and relevant identity surfaces.
- [ ] Support upload, replacement, removal/default avatar, image sizing/cropping, and loading/error states.
- [ ] Apply storage and Firestore security rules so users can update permitted profile fields without changing another user's identity.

## Status
The rapid sprint has committed the following source changes on this feature branch: front/rear camera switch (`774ca015`); dashboard preview-before-open interaction (`4ec92703`); moderately larger dashboard tiles (`48e60973`); and dashboard tile click feedback (`0e463f37`). Existing camera capture and mute/speaker controls were confirmed by source inspection, not device testing. The dashboard and call changes have not yet been compiled or tested on a physical device. All other backlog items remain pending. This document does not claim that the overall upgrade programme is complete, released, or delivered.
