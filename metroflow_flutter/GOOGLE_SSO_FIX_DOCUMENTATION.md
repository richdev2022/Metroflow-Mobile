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
