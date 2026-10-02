# Google SSO — Android Setup Guide (Metricorex)

This is the Android counterpart to the iOS Google SSO configuration. Unlike iOS,
Android does **not** use URL schemes or Info.plist entries — Android Google
Sign-In is registered entirely through **package name + SHA-1 fingerprints** in
the Google Cloud / Firebase console, plus a correctly generated
`google-services.json`.

---

## 0. Current state of the repo (what is already done)

The Flutter side needs **no code changes** — everything below is console work:

| Piece | Status | Where |
|---|---|---|
| `google_sign_in` plugin (v6.2.1) | ✅ wired | `pubspec.yaml` |
| `serverClientId` (Web client ID) | ✅ set, with `.env` override | `lib/services/google_auth_service.dart` + `.env` (`EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID`) |
| Scopes (`email profile openid`) | ✅ set | `google_auth_service.dart` |
| ID-token exchange `POST /auth/google { credential }` | ✅ implemented | `lib/providers/auth_provider.dart`, `lib/services/api.dart` |
| Google Services Gradle plugin | ✅ auto-applies when `google-services.json` exists | `android/app/build.gradle.kts` |
| `android/app/google-services.json` | ⚠️ present but **dead for Sign-In** (see §1) | repo |
| AndroidManifest URL scheme | ➖ **Not needed on Android** (that is iOS-only) | — |

---

## 1. Why Android SSO currently fails (root cause)

Two problems in the current configuration:

**a) The `google-services.json` has an empty `oauth_client` array:**

```json
"oauth_client": [],
"other_platform_oauth_client": []
```

An empty array means **no Android OAuth client is registered** for this app's
package name + SHA-1 in the project the json belongs to. At runtime Play
Services checks that registration and fails with
**ApiException 10 (DEVELOPER_ERROR)**, which the app surfaces as
"Google Sign-In is not available on this device…".

**b) Project mismatch.** The Web client ID used as `serverClientId` is:

```
438902996656-dbmnffpr8vufvso2o10esspalvl9c25c.apps.googleusercontent.com
```

The leading number `438902996656` is the GCP **project number** that owns that
client. But the current `google-services.json` belongs to Firebase project
`metricorex` with project number `268045301442` — a **different project**.

Google Sign-In on Android requires all three to live in the **same** GCP
project:

1. the **Android OAuth client** (package name + SHA-1),
2. the **Web client ID** passed as `serverClientId` (the token audience),
3. the **`google-services.json`** shipped in the APK (its API key identifies
   the project to Play Services).

Any split across projects → DEVELOPER_ERROR, always.

> **Decision rule:** keep using the project that owns `438902996656-…` (the one
> you configured iOS with and that the backend validates against). Do **not**
> create fresh clients in the `metricorex` Firebase project unless you are
> prepared to also regenerate the Web client ID, update `.env` +
> `google_auth_service.dart`, and redo the iOS console config.

---

## 2. Step 0 — Finalize the Android application ID FIRST

The current `applicationId` is the Flutter placeholder:

```
com.example.Metricorex_flutter        (android/app/build.gradle.kts)
```

The iOS bundle ID is `com.metricorex.app`. **You cannot change the
applicationId after the app is published on Google Play**, and it is baked into
the OAuth client registration — so decide before creating anything:

- **Option A (recommended):** rename Android to `com.metricorex.app` to match
  iOS. Ask the assistant to flip `applicationId`/`namespace` in
  `android/app/build.gradle.kts` (one commit) — but only together with a fresh
  `google-services.json` that contains the new package name, otherwise the
  Google Services Gradle plugin fails the build.
- **Option B:** keep `com.example.Metricorex_flutter` for now and register that
  package name. Works today, but it is not a Play-Store-worthy application ID.

Everything below assumes you have picked one and know the final package name
(called `<PACKAGE>` below).

---

## 3. Collect the SHA-1 fingerprints you must register

Google needs a fingerprint for **every key that can sign the app**. Get all of
these:

**a) Local debug keystore** (used by `flutter run`):

```bash
keytool -list -v -keystore ~/.android/debug.keystore \
  -alias androiddebugkey -storepass android -keypass android | grep SHA1
```

(Equivalent shortcut from the project: `cd android && ./gradlew signingReport`.)

**b) The CI / release keystore.** Today `build.gradle.kts` signs release builds
with the **debug** keystore — and on GitHub Actions that keystore is generated
fresh on each runner, so **its SHA-1 is different every build** and can never be
registered. Until a pinned keystore is wired into CI (see §7), Google SSO will
not work in CI-built APKs/AABs — only in locally-built ones.

**c) Google Play App Signing key** (once the app is on Play): Play Console →
Release → Setup → App signing → copy the **App signing key certificate SHA-1**.
Play re-signs every download, so this fingerprint must also be registered or
SSO breaks for Play-installed copies.

---

## 4. Console work — register the Android client (same project as iOS!)

1. Go to <https://console.firebase.google.com>. If the GCP project that owns
   `438902996656-…` is not yet a Firebase project, click **Add project** and
   select the existing GCP project from the list (importing it does not affect
   anything already configured in it, including your iOS setup).
2. In that project: **Project settings → General → Your apps → Add app →
   Android**. Enter:
   - **Android package name:** `<PACKAGE>` (exact applicationId, case-sensitive)
   - **App nickname:** Metricorex Android
   - **SHA-1:** paste the debug SHA-1 from §3a (add the release/Play SHA-1s from
     §3b/3c here later, via **Project settings → Your apps → Add fingerprint**)
3. Download `google-services.json` and hand it to the assistant (or drop it in)
   to replace `android/app/google-services.json`.
4. Verify the new file — this is the acceptance test that registration worked:

```json
"oauth_client": [
  { "client_info": { "mobilesdk_app_id": "…",
      "android_client_info": { "package_name": "<PACKAGE>" } },
    "oauth_client": [
      { "client_id": "<…>.apps.googleusercontent.com",
        "client_type": 1 }            // ← Android client, MUST exist now
    ],
    …
```

   and ideally `other_platform_oauth_client` also lists a `"client_type": 3`
   entry (the Web client). `client_type: 1` present = Android registration OK.

5. Cross-check in **GCP Console → APIs & Services → Credentials** (same
   project): an **OAuth 2.0 Client ID of type "Android"** should exist for
   `<PACKAGE>` + the SHA-1(s). Firebase creates it automatically when you add a
   fingerprint; if it is missing, create it manually with **Create credentials →
   OAuth client ID → Android**.
6. **OAuth consent screen** (same project): if the publishing status is
   *Testing*, only accounts listed as **Test users** can sign in — everyone
   else gets "access blocked". Either publish the app (scopes
   `email/profile/openid` are non-sensitive; no verification needed) or add
   your testers under **Audience → Test users**.

---

## 5. Hand-off checklist (what the assistant does in the repo)

Once you deliver the new `google-services.json` (and, if renaming, the
confirmation of `com.metricorex.app`):

1. Replace `android/app/google-services.json` (git-ignored? no — it is
   committed today; keep it committed so CI builds keep working).
2. If renaming: update `namespace` + `applicationId` in
   `android/app/build.gradle.kts` in the same commit.
3. **No AndroidManifest.xml changes and no Dart changes are required** — unlike
   iOS there is no URL scheme; the plugin reads everything from the json +
   `serverClientId`.
4. Push to `develop` (never main directly).

---

## 6. Verification checklist (real device)

1. **Completely uninstall** the app first — Play Services caches the old
   registration per package name.
2. `flutter run --release` or install the CI APK on a device **with Google Play
   services** (emulators without Play images always fail).
3. Tap **Continue with Google** → account picker should open.
4. Expected error codes if something is still off:

| Symptom / code | Meaning | Fix |
|---|---|---|
| `ApiException: 10` (DEVELOPER_ERROR) | package/SHA-1/project mismatch — the current failure | Re-check §1/§4: same project, exact package, SHA-1 registered |
| `ApiException: 12501` | user cancelled the picker | Not an error — app already handles it |
| `ApiException: 17` (API_NOT_CONNECTED) | registration not propagated yet | Wait 5–15 min, rebuild, retry |
| "Access blocked: … not completed verification" | consent screen in Testing mode | Add test users or publish (§4 step 6) |
| Sign-in OK but backend rejects | `aud` mismatch on `/auth/google` | Backend must accept `438902996656-…` as audience (same as iOS) |

5. Propagation: new fingerprints usually work within minutes, occasionally up
   to a few hours.

---

## 7. Release keystore — GENERATED ✅ (pinned signing key)

A dedicated release keystore has been generated and handed to the owner
(**never commit it, never lose it**). Details of the pinned key:

| Item | Value |
|---|---|
| File | `metricorex-release.keystore` (PKCS12) |
| Alias | `metricorex` |
| SHA-1 | `48:F9:26:DD:D7:9D:F9:A4:1A:95:6B:87:93:25:68:B5:6E:DE:7C:C5` |
| SHA-256 | `58:E6:4E:52:E7:53:81:A7:49:A6:69:B0:1F:27:9D:27:58:3D:2D:CD:70:AD:6E:34:D2:D8:EA:CB:5A:AF:E0:32` |
| Validity | 10,000 days (until ~2053) |
| DN | CN=Metricorex, OU=Metroflow, O=Metricorex Ltd, L=Lagos, ST=Lagos, C=NG |

**Register the SHA-1 above in the console** (§4). Passwords are NOT stored in
this repo — the owner keeps them with the keystore file.

### CI signing is wired and graceful

- `android/app/build.gradle.kts` reads `ANDROID_KEYSTORE_PATH` /
  `ANDROID_KEYSTORE_PASSWORD` / `ANDROID_KEY_ALIAS` / `ANDROID_KEY_PASSWORD`
  env vars; when present the release build is signed with this keystore.
- `.github/workflows/flutter-build.yml` decodes `ANDROID_KEYSTORE_BASE64`
  (GitHub secret) into `$RUNNER_TEMP` and exports the env vars. **If the
  secrets are not configured the build still succeeds with debug signing** and
  prints a warning — set these 4 secrets to make CI artifacts SSO-capable:
  1. `ANDROID_KEYSTORE_BASE64` — base64 of the keystore file
     (`base64 -w0 metricorex-release.keystore > metricorex-release.keystore.b64`)
  2. `ANDROID_KEYSTORE_PASSWORD`
  3. `ANDROID_KEY_ALIAS` → `metricorex`
  4. `ANDROID_KEY_PASSWORD` (same value as the store password)

### Application ID finalized

`applicationId`/`namespace` = **`com.metricorex.app`** (matches the iOS bundle
ID). MainActivity moved to `kotlin/com/metricorex/app/MainActivity.kt`
(package `com.metricorex.app`). The committed `google-services.json` was
hand-patched to the new package name only to keep builds green — **it must be
replaced by a console-generated json** (§4) once the Android app + SHA-1 are
registered.

---

## 8. Keystore recovery / re-deriving the SHA-1

**The SHA-1 is not a separate secret — it is a fingerprint OF the keystore
file.** Anyone holding the keystore file + store password can always re-print
it:

```bash
keytool -list -v -keystore metricorex-release.keystore -alias metricorex
# enter the store password when prompted (or pass -storepass '...')
```

You can also read it from a signed APK without the keystore:

```bash
keytool -printcert -jarfile app-release.apk
```

**If the keystore file is lost:**

- **Before the app is live on Google Play:** nothing is permanently broken —
  generate a fresh keystore, register the NEW SHA-1 in the console (remove the
  old fingerprint), and update the GitHub secrets. Users installing updates
  over a previously sideloaded APK signed with the LOST key will need to
  uninstall first (Android refuses updates across different signing keys) —
  one more reason to pin the real keystore before any public distribution.
- **After Play App Signing is enabled** (first AAB upload to Play): Google
  holds the *app signing key*, and the keystore you upload with becomes the
  *upload key*. Losing the upload key is recoverable — Play Console →
  Release → Setup → App signing → **Request reset** of the upload key. The
  app signing key SHA-1 (visible on that same page) is what must remain
  registered in the Google console for SSO.
- **After public release with sideloaded APKs (no Play):** the lost keystore
  is unrecoverable — a new key means every installed copy must be manually
  uninstalled/reinstalled. Back up the keystore + password in a password
  manager AND a second private location BEFORE doing anything else.

**There is no way to regenerate the same key** — a "regenerated" keystore is a
different key with a different SHA-1. Keep the original file safe; that is the
whole point of pinning it.

