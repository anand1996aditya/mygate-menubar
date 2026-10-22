# Changelog

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
