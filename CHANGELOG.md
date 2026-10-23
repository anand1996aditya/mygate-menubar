# Changelog

## 1.4.7 — 23 Oct 2026

- Approve and Deny now use the notification reply URL and `valstatus` A/D, matching the phone app.
- The visitor panel has a fixed height; long titles and repeated body text cannot push the buttons out.
- The panel photo placeholder is icon-only at thumbnail size.

## 1.4.6 — 23 Oct 2026

- Bundle identifier is now `io.github.anand1996aditya.mygate-menubar`.
- Application Support folder renamed to `MyGateMenuBar`; existing data is copied on first launch.
- Keychain service renamed; the old access key is migrated automatically.

## 1.4.5 — 23 Oct 2026

- Visitor photo now uses the same 46 x 46 point thumbnail as the Urban Company app.
- Large 3000 x 4000 photos are downscaled before layout; buttons stay visible.
- Added photo-loader and huge-image regression tests.


- Visitor photos are downloaded, downscaled and cropped to the 116 x 146 thumbnail before layout.
- A 3000 x 4000 test image no longer changes the panel height or hides the buttons.
- Regression test added for the downscaler.


- Visitor alert panel is now a compact card with a thumbnail, not a full-screen photo.
- The panel has a close button, auto-closes after five minutes, and closes on screen change.
- Pending polling restarts after wake, so expired requests do not leave a stale panel.

## 1.4.1 — 23 Oct 2026

- The MyGate access key now lives in the macOS Keychain (service `com.secureu.mygate`), not in `config.json`.
- Existing sessions migrate on first launch: the key moves to the Keychain and is blanked from the JSON. Other settings are kept.
- `config.json` now holds only non-secret settings and keeps `0600` permissions.
- Diagnostics logs and raw diagnostic dumps are written with `0600`; older `0644` logs are repaired on launch.
- Ad-hoc signing is unchanged. Notarisation needs an Apple Developer ID and is not part of this release.

## 1.4.0 — 22 Oct 2026

- History now imports MyGate's activity feed, the same list the phone shows, for the last 72 hours.
- Delivery, cab and visiting-help pre-approvals can now be cancelled from History.
- Feed entries are grouped by day and remain scrollable.

## 1.3.2 — 22 Oct 2026

- History is scrollable and shows every stored entry, grouped by day.
- Removed the 30-entry display cap.

## 1.3.1 — 22 Oct 2026

- Delivery dropdown gains "Others (any delivery)", so a courier from an unlisted company can still be pre-approved.
- Unknown-company pre-approvals are sent as a generic DELIVERY address and verified live.

## 1.3.0 — 22 Oct 2026

- Active guest passes can be revoked from the History screen, with a confirmation.
- Revoked passes disappear from MyGate immediately and are marked Revoked locally.
- Guest invites in history are labelled "Guest invite" instead of the owner name.

## 1.2.7 — 22 Oct 2026

- Guest invites now appear as "Guest invite" in history instead of the owner name.
- Adds a live functional test mode for pre-approvals, invites and passes.

## 1.2.6 — 22 Oct 2026

- History screen shows the full three days that are stored, not only the last 24 hours.

## 1.2.5 — 22 Oct 2026

- One field height (40 pt) for text inputs, dropdowns, cab code boxes, duration selector and action buttons.
- Placeholder text is light gray everywhere; chosen values are white.

## 1.2.4 — 22 Oct 2026

- Dropdown placeholders use the same light gray as text-field placeholders.
- Selected dropdown values stay in primary white.

## 1.2.3 — 22 Oct 2026

- Action button and duration selector share the same 40 pt height and capsule structure.

## 1.2.2 — 22 Oct 2026

- Delivery company and duration fields share one fixed 40 pt height.
- Custom popup menus replace SwiftUI menus so both fields match exactly.

## 1.2.1 — 22 Oct 2026

- Phone, OTP and cab fields accept digits only and stop at their limits.
- Phone numbers accept +91, leading zero and spaced formats and normalise to 10 digits.
- Guest mobile requires exactly 10 digits; OTP verify requires 6 digits.
- Form fields clear when switching tabs or after a successful pre-approval.
- Footer buttons are real buttons; refresh also reloads history.

## 1.2.0 — 22 Oct 2026

- Cab pre-approval uses a four-box code field and stops at four digits.
- Button labels match MyGate: Send invite for guests, Pre-approve for delivery, cab and visiting help.
- Delivery company list comes from MyGate's live provider list, sorted, with Blinkit, Zomato and Swiggy included.
- Visitor and gate history is stored locally for up to three days.
- Approval buttons show progress and keep errors visible instead of closing silently.
- Offline self-tests for parsing, cab digits, labels, company defaults and history retention.

## 1.1.0 — 22 Oct 2026

- Visitor popup rebuilt as a borderless, key-capable panel with reliable buttons.
- Recent visitor history with a Home/History toggle.
- Alphabetical delivery company and visiting help lists.
- Removed the Cab star badge.
- Single-instance guard and LaunchAgent start at login.
- Sanitised repository: no credentials, phone numbers or personal photos.

## 1.0.0 — 22 Oct 2026

- Initial app: OTP login, pending approvals, approve and deny, pre-approvals.
