# Zelon WhatsApp Flutter Application

Professional multi-platform WhatsApp Flutter client for the Zelon WhatsApp Engine.

## Features

- **Pixel-Perfect WhatsApp Mobile UI**:
  - Authentic WhatsApp colors (`#008069`, `#128C7E`, `#25D366`, `#EFEAE2`, `#202C33`, `#005C4B`).
  - WhatsApp 4-tab bar: Camera/QR, Chats, Status Updates, and Tools.
  - Delivery ticks (clock, single gray, double gray, double blue).
  - Voice notes waveform player.
  - Emoji drawer and attachments sheet.

- **In-App WhatsApp Connection**:
  - Live QR code display with auto-refresh.
  - 8-digit Pairing Code generator with phone number input and one-tap copy.
  - Instance switcher and multiple WhatsApp numbers support.

- **Fast Loading Speed & Offline Caching**:
  - Instant cache rendering via `CacheService` backed by `SharedPreferences`.
  - Zero-wait chat switching with background sync.

- **Role-Based Permissions & Super Admin Control**:
  - Extra features are **restricted from Normal Users by default**:
    - Deleted Messages: Shows "🚫 This message was deleted" without revealing original text.
    - Edited Messages: Diff history drawer ("Old was this and Was This") is hidden.
    - Status Seen: Viewers count and stealth viewing are hidden.
    - Read Receipts: Detailed delivery analysis is hidden.
  - **Super Admin Permission Manager**:
    - Admins can toggle any of these 4 permissions per user in real time.
    - When enabled, the user immediately gets access to view deleted messages, compare edited message diffs, and inspect status viewers.

- **Automated APK Build via GitHub Actions**:
  - Automatically compiles an Android APK (`.apk`) on every push and makes it downloadable in GitHub Actions Artifacts.

## How to Build the APK Locally

```bash
cd App
flutter pub get
flutter build apk --release
```
The APK will be generated at:
`App/build/app/outputs/flutter-apk/app-release.apk`
