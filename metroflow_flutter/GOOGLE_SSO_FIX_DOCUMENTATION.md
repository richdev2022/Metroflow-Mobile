# Google SSO — Mobile Crash Fix & Required Console Setup

## What was crashing

### iOS (hard crash, uncatchable from Dart)
`ios/Runner/Info.plist` was **missing the `GIDClientID` key and the reversed
client-ID URL scheme (`CFBundleURLTypes`)**. On `google_sign_in` (iOS pod
5.9.0), `signIn()` raises a native `NSException` when the client ID is absent.
Dart `try/catch` cannot catch `NSException` — the app dies at the tap.

**Fixed in code (this commit):**
- `GIDClientID` = `438902996656-dbmnffpr8vufvso2o10esspalvl9c25c.apps.googleusercontent.com`
- `CFBundleURLTypes` scheme = `com.googleusercontent.apps.438902996656-dbmnffpr8vufvso2o10esspalvl9c25c`

### Android (DEVELOPER_ERROR — ApiException 10)
1. `android/app/google-services.json` had an **empty `oauth_client` array** —
   no web client was associated with the app.
2. The `serverClientId` used by the Dart layer belongs to GCP project
   **438902996656**, while `google-services.json` is Firebase project
   **268045301442 ("metricorex")** — a cross-project setup.

**Fixed in code (this commit):**
- Added the web client (`client_type: 3`) to `oauth_client` and
  `other_platform_oauth_client` in `google-services.json`.

## ⚠️ Console steps you MUST complete (cannot be done from code)

For sign-in to succeed on **Android**, the app must be registered as an OAuth
client in the **same GCP project that owns the web client ID**
(`438902996656-…`):

1. Open https://console.cloud.google.com/apis/credentials (select the project
   that contains the `438902996656-…` Web client).
2. **Create credentials → OAuth client ID → Android**, with:
   - Package name: `com.example.Metricorex_flutter`
   - SHA-1: the signing key's SHA-1.
     - Debug: `cd android && ./gradlew signingReport` (look for the debug
       variant).
     - Release: the SHA-1 of the keystore used for production
       (`keytool -list -v -keystore <keystore> -alias <alias>`).
       ⚠️ NOTE: `android/app/build.gradle.kts` currently signs **release
       builds with the debug keystore** — use that same debug-keystore SHA-1
       until a real release keystore exists.
3. Repeat step 2 for every SHA-1 you ship with (debug + release).

Optionally, migrate everything into ONE project (recommended): create a Web
client in Firebase project "metricorex" (268045301442), put its ID in
`EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID` (.env), `GIDClientID` (iOS) and
`serverClientId` (google_auth_service.dart), then update
`android/app/google-services.json` accordingly.

## Verifying

- Android: `flutter run` → tap "Sign in with Google" → account picker opens.
  If you still see DEVELOPER_ERROR the SHA-1/package is not registered in the
  client-ID's project (step 2 above).
- iOS: build and run; the account picker opens; no crash on tap.

---

# iOS Access blocked fix (Feb 2026)

## The bug

On iOS, tapping "Sign in with Google" opened the browser but Google returned:

> **Access blocked: This app's request is invalid**
> Error 400: `invalid_request` — *Custom scheme URIs are not allowed for
> 'WEB' client type.*

**Root cause:** `GIDClientID` in `ios/Runner/Info.plist` was set to the
**Web-type** OAuth client
(`438902996656-dbmnffpr8vufvso2o10esspalvl9c25c…`). A Web client is only
allowed to redirect to `https://` URIs; `google_sign_in` on iOS redirects
into the app via the custom scheme
`com.googleusercontent.apps.<client-id>`, so Google rejects the request
before the consent screen. The Web client is still REQUIRED — but only as
`serverClientId` in `lib/services/google_auth_service.dart` (that is what
makes Google issue the ID token on Android/Web).

## The fix (build settings)

`Info.plist` now references build settings instead of hard-coded values:

```xml
<key>GIDClientID</key>
<string>$(GOOGLE_IOS_CLIENT_ID)</string>
...
<key>CFBundleURLSchemes</key>
<array>
  <string>$(GOOGLE_IOS_URL_SCHEME)</string>
</array>
```

- **NEW `ios/Flutter/GoogleSignIn.xcconfig`** holds the defaults:
  - `GOOGLE_IOS_CLIENT_ID` — the **iOS-type** client ID
  - `GOOGLE_IOS_URL_SCHEME` — that client ID reversed, with
    `.apps.googleusercontent.com` stripped
    (`com.googleusercontent.apps.<id-without-suffix>`)
- `ios/Flutter/Debug.xcconfig` and `Release.xcconfig` include it
  (`#include "GoogleSignIn.xcconfig"`), so both build configurations inherit
  the settings.
- `lib/services/google_auth_service.dart` keeps `serverClientId` = WEB
  client (unchanged flow logic) and maps the "Access blocked /
  invalid_request / Custom scheme" error to a clear support message.

## GCP console steps (cannot be done from code)

1. Open https://console.cloud.google.com/apis/credentials and select the
   project that owns the `438902996656-…` Web client (same project!).
2. **Create credentials → OAuth client ID → iOS**:
   - Bundle ID: `com.metricorex.app` (must match the app's
     `PRODUCT_BUNDLE_IDENTIFIER` — verified in
     `ios/Runner.xcodeproj/project.pbxproj`).
3. Copy the new client ID and paste it into
   `ios/Flutter/GoogleSignIn.xcconfig` (`GOOGLE_IOS_CLIENT_ID`), and set
   `GOOGLE_IOS_URL_SCHEME` to the reversed value:
   `com.googleusercontent.apps.<new-client-id-without-.apps.googleusercontent.com>`.

## CI (ios-testflight workflow)

Two repository **secrets** drive the build settings (they override the
xcconfig defaults via xcodebuild environment build-setting overrides, and
are only exported when non-empty):

| Secret | Value |
| --- | --- |
| `GOOGLE_IOS_CLIENT_ID` | the iOS-type client ID (step 2 above) |
| `GOOGLE_IOS_URL_SCHEME` | `com.googleusercontent.apps.<client-id-without-suffix>` |

Both the *Build Flutter iOS* step and the *fastlane beta* step in
`.github/workflows/ios-testflight.yml` receive them. Until the secrets and
the GCP client exist, the committed xcconfig defaults ship the old (Web)
ID — Google sign-in on iOS keeps returning "Access blocked" and the app now
shows a clear configuration-mismatch message instead of a raw Google error.

## Verifying (iOS)

1. Add the GCP iOS client + the two secrets.
2. Run the iOS TestFlight workflow (or `flutter build ios` locally).
3. Sign in with Google → consent screen opens, redirect returns into the
   app, ID token is exchanged by `POST /auth/google`.
