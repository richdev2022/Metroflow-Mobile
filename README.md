# Metricorex Pay - Flutter App

## Getting Started

### Prerequisites
- Flutter SDK (Dart ≥ 3.8 — e.g. Flutter 3.32+; flutter_lints 6 requires it)
- Android Studio / VS Code (with Flutter plugin)

### Installation
1. Navigate to Flutter project:
   ```bash
   cd metroflow_flutter
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Generate platform-specific files if missing:
   ```bash
   flutter create .
   ```

4. Start the development server:
   ```bash
   flutter run
   ```

### Features Implemented
- ✅ Authentication (Login/Register + Google SSO)
- ✅ KYC Verification flow (BVN/NIN + OTP)
- ✅ Wallet Management (Personal & Business wallets)
- ✅ Payroll & Employees
- ✅ Transfers (single, bulk & international) & History
- ✅ **Payment Links** — create & share links, track payments
- ✅ **Smart Invoices** — itemised invoices, share public checkout, track status
- ✅ **MetricAi Credit Packs** — purchase AI credit top-ups from your wallet
- ✅ **Store** — list products/services, share the storefront link, fulfil paid orders
- ✅ **Subscriptions** — recurring billing plans (daily/weekly/monthly), subscribers & auto-charges
- ✅ MetricAi chat, image generation & product documentation (GLM-powered)
- ✅ Team workspace: tasks, board, backlog, ideas, epics, chat, calls & meetings
- ✅ Profile & Settings
- ✅ Theme Switching (Light/Dark/System)
- ✅ Biometrics (Fingerprint/FaceID) — per-account keys, activation prompt on login (skippable to Settings), stickyAuth + in-flight guards against Android's double-trigger
- ✅ Push notifications — FCM with incoming-call data payloads that render the full-screen ringing UI, foreground-swallow fix, token kept on idle security logout
- ✅ Roles & permissions screen with per-call error isolation (no blank screens, no wrongful logouts)
- ✅ **5-slide onboarding** summarising the full business feature set (work, meetings, money, get-paid, MetricAi & security)
- ✅ **Grouped navigation** — the More sheet and drawer share one taxonomy (Work & Team · Money · Get Paid · MetricAi · App) so 20+ destinations stay scannable; Wallet/Payroll keep their KYC gate
- ✅ **Home = the whole suite** — hero with wallet balance strip + Fund shortcut (with **wallet picker**: personal vs business), work+money quick actions, a "Get Paid" hub (Payment Links / Invoices / Storefront / Subscriptions with live counts) and a money row (Transfers / Payroll / Fund)

### E2E Payload Encryption

When `EXPO_PUBLIC_PAYLOAD_ENCRYPTION_KEY` is present in `metroflow_flutter/.env` (must equal the backend's `PAYLOAD_ENCRYPTION_KEY`), every JSON request/response body travels as an AES-256-GCM envelope (`{ v, iv, tag, ct }`, header `x-mfv-enc: 1`) via `lib/services/payload_crypto.dart` + the dio interceptors in `lib/services/api.dart`. Envelope detection is shape-first (proxies can't break it), and a keyless server's `400 DECRYPT_FAILED` transparently retries once in plaintext — mismatched deployments degrade, never break. Unset key = fully plaintext.

### Environment

`metroflow_flutter/.env` (bundled asset — flutter_dotenv):

```env
EXPO_PUBLIC_API_BASE_URL=https://api.metricorex.com/api
EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID=...          # required for Google SSO on Android
EXPO_PUBLIC_PAYLOAD_ENCRYPTION_KEY=...        # 32-byte base64, MUST match the backend
```

### Project Structure
```
Metricorex_flutter/
├── lib/
│   ├── screens/          # All screen components
│   ├── services/         # API & Biometrics services
│   ├── providers/        # Riverpod state management
│   ├── models/           # Data models
│   ├── utils/            # Utilities (logger)
│   ├── theme/            # App theme & colors
│   └── main.dart
└── pubspec.yaml
```

## Branching & Releases

- `main` — release source of truth. GitHub Actions builds the release APK from `main` tags/pushes.
- `develop` — integration branch. Feature work merges here first; once verified (CI green), a PR `develop → main` is merged to cut a release.
- Hotfixes may branch from `main` and must be merged back into `develop`.

## Backend Environment

The app talks to `https://api.metricorex.com/` in release builds (see `lib/services/api.dart`). When the backend adds new endpoints, **deploy the API before shipping a new build** — the app surfaces a friendly "feature isn't available yet" message if the server is older than the client. Backend repo: `metroflow-backend` (`bash scripts/deploy.sh` on the VPS).
