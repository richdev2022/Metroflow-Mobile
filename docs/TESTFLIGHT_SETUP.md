# Metricorex iOS → TestFlight Setup

This repo is fully wired for automated iOS deployment: every run **creates the
"Metricorex" app on your Apple Developer account (first run), builds, signs and
uploads to TestFlight — automatically**. No Mac, no Xcode, no Apple-ID password
and no 2FA prompts are needed: the pipeline authenticates with an **App Store
Connect API key**.

Everything below the "Your part" section is already done in code.

---

## What is already done in this repo

| Piece | Status |
|---|---|
| Bundle ID `com.metricorex.app` | Set in the Xcode project |
| App display name | `Metricorex` |
| Push Notifications capability | `ios/Runner/Runner.entitlements` (aps-environment) wired into all build configs |
| APNs background mode | Already in `Info.plist` (`remote-notification`) |
| Firebase swizzling | `FirebaseAppDelegateProxyEnabled = YES` in `Info.plist` |
| Export-compliance question | Auto-answered (`ITSAppUsesNonExemptEncryption = false`) |
| iOS permission-request bug | **Fixed** — `criticalAlert: true` was making `requestPermission` fail on iOS (it requires a special Apple entitlement), so the permission prompt never appeared and push could never work. Now requests `alert/badge/sound` only |
| Fastfile (`beta` lane) | `ios/fastlane/Fastfile` — create app → build → sign → upload |
| CI workflow | `.github/workflows/ios-testflight.yml` on macOS runners, manual button + auto-run on `main` |
| Backend | Already sends FCM HTTP v1 (works for iOS unchanged once Firebase knows about the iOS app) |

---

## Your part — about 15 minutes in your browser

> Prerequisite: your Apple Developer Program membership must be **active**
> (the $99/year enrollment completed and approved). API keys and TestFlight
> only exist for active members. If you haven't enrolled yet:
> <https://developer.apple.com/programs/enroll/>
> Also sign in once at <https://appstoreconnect.apple.com> and accept the
> **Program License Agreement** if prompted — API calls fail until you do.

### Step 1 — App Store Connect API key (pipeline credentials)

1. Sign in at <https://appstoreconnect.apple.com> with your Apple ID
   (approve the 2FA code on your device).
2. **Users and Access → Integrations → App Store Connect API → Team Keys**
   (older UI: **Keys**), press **+**.
3. Name: `metricorex-ci`, Access: **Admin** (needs to create apps + builds).
4. Download the `.p8` file **once** (Apple never lets you re-download it) and
   note the **Key ID** shown next to it, plus the **Issuer ID** shown above
   the key table.

### Step 2 — Firebase: register the iOS app + APNs (this is what makes push work)

1. **Firebase Console** → your project (the same one `android/app/google-services.json`
   belongs to) → ⚙️ **Project settings → General → Your apps → Add app → iOS**.
2. Bundle ID: **`com.metricorex.app`** (must match exactly), nickname:
   `Metricorex`. Skip App Store steps.
3. Download **`GoogleService-Info.plist`**.
4. **Apple Developer portal** → <https://developer.apple.com/account/resources/certs/list>
   → **Keys → +** → name `metricorex-apns` → tick **Apple Push Notifications
   service (APNs)** → **Configure → Sandbox & Production** → download the
   `.p8` and note its **Key ID**. Your 10-character **Team ID** is on the
   Membership details page.
5. Back in **Firebase Console → Project settings → Cloud Messaging** →
   under **Apple app configurations** pick the Metricorex iOS app →
   **APNs Authentication Key** → upload that `.p8` + Key ID + Team ID.
   ⚠️ **This upload is the single most-missed step** — without it, iOS devices
   register fine but FCM messages are silently never delivered.
6. Commit `GoogleService-Info.plist` into the repo at
   `metroflow_flutter/ios/Runner/GoogleService-Info.plist`
   (this file is app *configuration*, not a secret — it is safe to commit).

### Step 3 — Add the GitHub secrets

Repo → **Settings → Secrets and variables → Actions → New repository secret**:

| Secret name | Value |
|---|---|
| `APP_STORE_CONNECT_KEY_ID` | Key ID from Step 1 |
| `APP_STORE_CONNECT_ISSUER_ID` | Issuer ID from Step 1 |
| `APP_STORE_CONNECT_KEY_P8` | The Step-1 `.p8`, **base64-encoded**: `base64 -i AuthKey_ABC.p8 \| pbcopy` (macOS) or `base64 -w0 AuthKey_ABC.p8` (Linux) |
| `APPLE_TEAM_ID` | 10-character Team ID (Membership page) |
| `GOOGLE_SERVICE_INFO_PLIST_B64` | *(optional)* base64 of `GoogleService-Info.plist` — only needed if you chose not to commit the file |

### Step 4 — Ship it

1. Merge the `develop → main` PR (the workflow also runs on `main`), **or**
   just open the repo → **Actions → iOS TestFlight Deploy → Run workflow**.
2. First run: fastlane's `produce` **creates the "Metricorex" app record** on
   your App Store Connect automatically, registers the bundle ID, builds,
   signs (Apple cloud-signing via your API key) and uploads to TestFlight.
3. After the upload, Apple processes the build (~10–30 min). It then appears
   under **App Store Connect → My Apps → Metricorex → TestFlight**.

### Step 5 — Invite testers

1. **App Store Connect → My Apps → Metricorex → TestFlight → Testers & Groups**.
2. Add yourself as an **Internal Tester** (needs your Apple ID added under
   Users and Access first) or create a group / public link.
3. On the iPhone: install the **TestFlight** app → accept the email invite →
   **Install Metricorex**.

---

## Push notifications on iOS — how the chain works

```
Backend (VPS, unchanged) ──FCM HTTP v1──▶ Google/Firebase ──APNs──▶ iPhone
```

1. App starts → `firebase_messaging` requests permission (alert/badge/sound —
   the `criticalAlert` bug is fixed) and registers the FCM token with the
   backend as platform `ios`.
2. Backend pushes via FCM exactly as it does for Android — no backend change
   is required.
3. FCM delivers over APNs **only if** the Step-2 APNs key is uploaded to
   Firebase. If pushes reach Android but never iOS, that upload is the thing
   to re-check.

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| CI: `Please accept the Apple Developer Program License Agreement` | Sign in to <https://appstoreconnect.apple.com> and accept it |
| CI: 401/403 from App Store Connect | Wrong Issuer ID / Key ID, or the key was revoked — regenerate Step 1 |
| CI: `APP_STORE_CONNECT_KEY_P8 missing` | Secrets not added or branch protection hides them — add under Settings → Secrets |
| CI: `GoogleService-Info.plist is missing` | Commit the file (Step 2.3/2.6) or add the `GOOGLE_SERVICE_INFO_PLIST_B64` secret |
| Build uploaded but no push on iOS | APNs key not uploaded to Firebase (Step 2.5), or permission prompt denied on the device |
| Build stuck in "Processing" for hours | Normal for the first build of a new app (up to ~1 h); watch the TestFlight page |

## Security notes

- The `.p8` API key grants full App Store Connect access: keep it **only** in
  GitHub secrets (encrypted) and your own machine — never commit it.
- Consider changing your Apple ID password if it was ever shared in chat;
  the pipeline never uses it (2FA-safe API-key auth only).
- You can revoke the CI key anytime under Users and Access → Integrations.
