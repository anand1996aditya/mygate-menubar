# MyGate MenuBar

A small macOS menu bar app for MyGate residents. It shows pending visitor approvals at the gate
and lets you approve or deny them without opening the phone app.

## Features

- Live pending approval check, refreshed every two seconds.
- Visitor popup with the gate photo, visitor type, gate and flat details.
- Approve or deny with one click.
- Recent visitor history: who is inside now, plus today's passes and their status.
- Pre-approvals: delivery company, cab, guest invite and visiting help.
- Branded menu bar icon and popover.

## How it works

The app uses the same endpoints as the MyGate Android app:

- Login: OTP request and login, then the returned `access-key` header.
- Pending approval: `GET /notif/v2/validation/active`.
- Approve: `POST /ecom/v3/approvalrequest/allowonce`.
- Deny: `POST /ecom/v3/approvalrequest/userreject`.
- Pre-approval lists and requests.
- Visitor history: `GET /flat/v2/visitors` and `GET /seekinvite/v1/myvisits`.

Polling replaces push notifications, because the phone app's FCM channel is not available on macOS.

## Setup

1. Build and install:

        ./build.sh
        cp -R "Build/MyGate MenuBar.app" ~/Applications/
        open "$HOME/Applications/MyGate MenuBar.app"

2. Enter the phone number and the OTP in the app. The session is stored at
   `~/Library/Application Support/MyGate MenuBar/config.json` with `0600` permissions.

No credentials are compiled into the binary.

## Privacy

The repository contains no API keys, session tokens, phone numbers or personal photos.
Credentials stay in Application Support on your Mac.

## Limits

- Read-only for door locks. The app only handles gate approvals.
- No push notifications. Polling is the alerting mechanism.
- Approval and deny calls act on real visitor requests.

## License

MIT. See `LICENSE`.
