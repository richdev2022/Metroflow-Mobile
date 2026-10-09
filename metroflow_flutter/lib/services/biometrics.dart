import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api.dart';

class BiometricResult {
  final bool success;
  final String? error;

  const BiometricResult({required this.success, this.error});
}

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

  /// ANDROID MULTI-ATTEMPT FIX: local_auth cannot run two platform prompts
  /// at once. When a second authenticate() is issued while one is still in
  /// flight (double-tap, widget rebuild, screen race), Android fails the
  /// pending fingerprint read — the user then had to authenticate several
  /// times before sign-in went through. The guard makes any overlapping
  /// call a no-op that waits for the ORIGINAL attempt's result instead of
  /// cancelling it.
  static Future<BiometricResult>? _inFlight;

  // ---------------------------------------------------------------------------
  // CAPABILITY PROBE CACHE (process lifetime) — ANDROID MULTI-TRIGGER FIX.
  //
  // hasHardware()/isDeviceSupported()/isEnrolled()/getAvailableTypes() each
  // hit platform channels. The pre-flight sequence every authenticate() used
  // to run (canAuthenticate -> isAvailable -> hasHardware ->
  // isDeviceSupported -> canCheckBiometrics -> getAvailableBiometrics) fired
  // 4-6 platform calls BEFORE the prompt went up — and on several OEMs
  // (Samsung/Xiaomi) poking the biometric manager channel cancels a
  // fingerprint prompt that is still pending, forcing the user through
  // biometric multiple times. The probes are now memoized for the lifetime
  // of the process; failures are never cached (a transient channel error
  // still retries).
  //
  // The underlying facts can only change while the process lives when the
  // user enrolls/removes biometrics in SYSTEM settings — i.e. exactly when
  // the app is backgrounded. main.dart calls [resetCapabilityCache] on every
  // app RESUME so the next attempt re-probes fresh.
  // ---------------------------------------------------------------------------
  static bool? _cachedHasHardware;
  static bool? _cachedDeviceSupported;
  static List<BiometricType>? _cachedAvailableBiometrics;

  /// Drops the memoized capability probes. Called on app resume (main.dart)
  /// so an enrollment change made in system settings is picked up again.
  static void resetCapabilityCache() {
    _cachedHasHardware = null;
    _cachedDeviceSupported = null;
    _cachedAvailableBiometrics = null;
  }

  /// Memoized [LocalAuthentication.getAvailableBiometrics] — the single point
  /// every enrollment-dependent check funnels through.
  static Future<List<BiometricType>> _probeAvailableBiometrics() async {
    final cached = _cachedAvailableBiometrics;
    if (cached != null) return cached;
    final biometrics = await _auth.getAvailableBiometrics();
    _cachedAvailableBiometrics = biometrics;
    return biometrics;
  }

  static Future<bool> hasHardware() async {
    if (kIsWeb) {
      return false;
    }
    final cached = _cachedHasHardware;
    if (cached != null) return cached;
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) {
        _cachedDeviceSupported = false;
        _cachedHasHardware = false;
        return false;
      }

      // Try canCheckBiometrics first
      bool canCheck = false;
      try {
        canCheck = await _auth.canCheckBiometrics;
      } catch (e) {
        debugPrint('Error checking canCheckBiometrics: $e');
      }

      bool result;
      if (canCheck) {
        // Check for available biometrics
        try {
          final biometrics = await _probeAvailableBiometrics();
          result = biometrics.isNotEmpty;
        } catch (e) {
          debugPrint('Error getting available biometrics: $e');
          result = true; // If we can check, assume available
        }
      } else {
        // Fallback: if canCheck fails, just return supported status
        result = supported;
      }
      _cachedHasHardware = result;
      return result;
    } catch (e) {
      debugPrint('Failed to check biometric hardware: $e');
      return false; // never cache failures
    }
  }

  /// True when the device can present ANY local-auth prompt: biometrics OR
  /// the device PIN/pattern/password fallback (stickyAuth +
  /// biometricOnly:false). Low-end devices without fingerprint hardware but
  /// with a screen lock can therefore still use biometric unlock.
  static Future<bool> isDeviceSupported() async {
    if (kIsWeb) {
      return false;
    }
    final cached = _cachedDeviceSupported;
    if (cached != null) return cached;
    try {
      final supported = await _auth.isDeviceSupported();
      _cachedDeviceSupported = supported;
      return supported;
    } catch (e) {
      debugPrint('Failed to check device support: $e');
      return false;
    }
  }

  /// [isAvailable] OR the device-credential (PIN/pattern) fallback.
  static Future<bool> canAuthenticate() async {
    if (await isAvailable()) return true;
    return isDeviceSupported();
  }

  static Future<bool> isEnrolled() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final biometrics = await _probeAvailableBiometrics();
      return biometrics.isNotEmpty;
    } catch (e) {
      debugPrint('Failed to check biometric enrollment: $e');
      return false;
    }
  }

  static Future<bool> isAvailable() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final hasHardware = await BiometricService.hasHardware();
      if (!hasHardware) return false;
      
      final isEnrolled = await BiometricService.isEnrolled();
      return isEnrolled;
    } catch (e) {
      debugPrint('Failed to check biometric availability: $e');
      return false;
    }
  }

  static Future<List<BiometricType>> getAvailableTypes() async {
    if (kIsWeb) {
      return [];
    }
    try {
      return await _probeAvailableBiometrics();
    } catch (e) {
      debugPrint('Failed to get biometric types: $e');
      return [];
    }
  }

  static Future<BiometricResult> authenticate([String promptMessage = 'Authenticate to continue']) async {
    if (kIsWeb) {
      return const BiometricResult(
        success: false,
        error: 'Biometric authentication is not available on web',
      );
    }

    // Overlapping call while a prompt is already up: reuse its result rather
    // than issuing a second platform call that fails the first one (Android).
    final pending = _inFlight;
    if (pending != null) {
      try {
        return await pending;
      } catch (_) {
        // Fall through and try a fresh attempt below.
      } finally {
        // Only clear if this is still the same attempt (no newer one started).
        if (identical(_inFlight, pending)) _inFlight = null;
      }
    }

    final attempt = _authenticateOnce(promptMessage);
    _inFlight = attempt;
    try {
      return await attempt;
    } finally {
      if (identical(_inFlight, attempt)) _inFlight = null;
    }
  }

  /// Maps a local_auth platform exception to a user-facing BiometricResult.
  ///
  /// Matched on the TYPED enum (LocalAuthExceptionCode) — the previous
  /// toString().contains('NotEnrolled') style never matched: the enum's
  /// toString is "LocalAuthExceptionCode.noBiometricsEnrolled" (lowercase
  /// camelCase), so every failure fell through to the generic message and
  /// users could not tell "canceled" from "not enrolled / locked out".
  static BiometricResult _mapLocalAuthError(LocalAuthException e) {
    switch (e.code) {
      case LocalAuthExceptionCode.noBiometricHardware:
      case LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable:
      case LocalAuthExceptionCode.deviceError:
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is not available on this device',
        );
      case LocalAuthExceptionCode.noBiometricsEnrolled:
      case LocalAuthExceptionCode.noCredentialsSet:
        return const BiometricResult(
          success: false,
          error: 'Please set up biometrics in your device settings first',
        );
      case LocalAuthExceptionCode.temporaryLockout:
      case LocalAuthExceptionCode.biometricLockout:
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is temporarily locked. Please try again later.',
        );
      case LocalAuthExceptionCode.userCanceled:
        return const BiometricResult(
          success: false,
          error: 'Authentication was canceled',
        );
      case LocalAuthExceptionCode.uiUnavailable:
        return const BiometricResult(
          success: false,
          error: 'The biometric prompt could not open — please try again',
        );
      default:
        break;
    }

    // Fallback to description or generic message
    final description = e.description;
    return BiometricResult(
      success: false,
      error: description != null && description.isNotEmpty
          ? description
          : 'Biometric authentication failed',
    );
  }

  static Future<BiometricResult> _authenticateOnce(String promptMessage) async {
    try {
      // NOTE: no stopAuthentication() here. Firing it immediately before
      // authenticate() raced the platform channel on Android — a fingerprint
      // that WAS verified could be reported as cancelled, forcing the user
      // through biometric several times before login succeeded. local_auth
      // serialises its own calls; the in-flight guard above handles overlap.

      // Device-credential fallback: allow the device PIN/pattern when
      // biometrics are unavailable/failed (stickyAuth survives backgrounding,
      // useErrorDialogs guides the user). THIS is the compatibility fix for
      // low-end devices — biometricOnly stays false.
      final canAuth = await BiometricService.canAuthenticate();
      if (!canAuth) {
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is not available on this device',
        );
      }

      debugPrint('Starting biometric authentication...');

      // -------------------------------------------------------------------
      // ANDROID INSTANT-CANCEL RACE FIX (the "scan 2-3 times" bug):
      // a BiometricPrompt raised while the FragmentActivity is still
      // settling (right after launch/unlock/resume, or while a keyboard/
      // transition animation is in flight) is silently CANCELLED BY THE
      // SYSTEM before the user ever sees it — the call returns `false` or
      // throws UserCanceled within a few milliseconds. A real user cancel
      // takes far longer (the dialog must first become visible). So: any
      // failure arriving under the 250ms window is treated as a
      // system-killed prompt and retried automatically (max 2 retries) —
      // the user no longer has to tap the fingerprint button repeatedly.
      // Before each raise we also let the current frame settle, which is
      // the surface condition Android requires for the prompt to stick.
      // -------------------------------------------------------------------
      for (int attempt = 0; ; attempt++) {
        try {
          await WidgetsBinding.instance.endOfFrame;
        } catch (_) {
          // endOfFrame is unavailable in some test shells — never fatal.
        }
        if (attempt > 0) {
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }

        final sw = Stopwatch()..start();
        bool result;
        try {
          // STICKY AUTH (Android multi-trigger fix): in local_auth 3.x the
          // `persistAcrossBackgrounding` flag IS AuthenticationOptions.stickyAuth
          // — it is forwarded verbatim (local_auth maps stickyAuth:
          // persistAcrossBackgrounding into the platform options and
          // local_auth_android passes it as the `sticky` platform arg). It keeps
          // the system sheet alive when the app is backgrounded mid-prompt
          // instead of cancelling and re-prompting. biometricOnly stays FALSE
          // on purpose: the device-credential (PIN/pattern) fallback is
          // intentional.
          result = await _auth.authenticate(
            localizedReason: promptMessage,
            biometricOnly: false,
            persistAcrossBackgrounding: true,
            sensitiveTransaction: false,
          );
        } on LocalAuthException catch (e) {
          sw.stop();
          // Retry any INSTANT system-side failure. The system-killed prompt
          // surfaces as userCanceled/systemCanceled/timeout/uiUnavailable and
          // can arrive AFTER the sheet begins animating in (300-600ms on
          // mid/low-end Android) — the old 250ms window missed most of them,
          // which is why users had to tap fingerprint 2-3 times. A real
          // user cancel takes >1s (the dialog must first be visible).
          const retryable = {
            LocalAuthExceptionCode.userCanceled,
            LocalAuthExceptionCode.systemCanceled,
            LocalAuthExceptionCode.timeout,
            LocalAuthExceptionCode.uiUnavailable,
            LocalAuthExceptionCode.authInProgress,
          };
          final instantFailure = sw.elapsedMilliseconds < 900;
          if (retryable.contains(e.code) && instantFailure && attempt < 3) {
            debugPrint(
              'Biometric prompt killed before showing '
              '(${e.code}, ${sw.elapsedMilliseconds}ms, attempt $attempt) — auto-retrying',
            );
            continue;
          }
          debugPrint('Biometric LocalAuthException: code=${e.code}, desc=${e.description}');
          return _mapLocalAuthError(e);
        }
        sw.stop();

        debugPrint('Biometric result: $result '
            '(${sw.elapsedMilliseconds}ms, attempt $attempt)');

        if (result) {
          return const BiometricResult(success: true);
        }

        // Unsuccessful without an exception. Only retry when the failure
        // arrives "instantly" — the signature of a system-killed prompt.
        // A dialog the user saw and dismissed takes longer than 900ms.
        if (sw.elapsedMilliseconds < 900 && attempt < 3) {
          debugPrint('Biometric prompt cancelled before showing '
              '(instant false, ${sw.elapsedMilliseconds}ms, attempt $attempt) — auto-retrying');
          continue;
        }
        return const BiometricResult(
          success: false,
          error: 'Authentication canceled or failed',
        );
      }
    } on LocalAuthException catch (e) {
      debugPrint('Biometric LocalAuthException (outer): code=${e.code}');
      return _mapLocalAuthError(e);
    } catch (e) {
      debugPrint('Biometric authentication generic error: $e');
      return const BiometricResult(
        success: false,
        error: 'An unexpected error occurred during authentication',
      );
    }
  }

  /// Biometrics enabled — PER-ACCOUNT when a userId is given (the per-account
  /// key is the ONLY source: no legacy fallback, so a fresh account starts
  /// OFF even if a previous account on this device opted in). Without a
  /// userId this is the raw legacy device-wide flag.
  static Future<bool> isEnabled([String? userId]) async {
    try {
      final storage = StorageService();
      final enabled = (userId != null && userId.isNotEmpty)
          ? await storage.getBiometricsEnabledForAccount(userId)
          : await storage.getBiometricsEnabled();
      debugPrint('Biometrics enabled${userId != null ? ' for account $userId' : ''}: $enabled');
      return enabled;
    } catch (e) {
      debugPrint('Failed to check biometrics enabled status: $e');
      return false;
    }
  }

  /// Human-readable device name for the backend enroll payload.
  static String deviceName() {
    try {
      final host = Platform.localHostname;
      if (host.trim().isNotEmpty) return host;
    } catch (_) {}
    return platformName();
  }

  /// 'android' | 'ios' | other — matches the backend enroll schema.
  static String platformName() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'android';
  }

  static Future<bool> enableBiometrics() async {
    final result = await enableBiometricsWithResult();
    return result.success;
  }

  static Future<BiometricResult> enableBiometricsWithResult([String? userId]) async {
    try {
      debugPrint('Attempting to enable biometrics...');
      final isAvailable = await BiometricService.isAvailable();
      if (!isAvailable) {
        debugPrint('Biometrics unavailable or not enrolled');
        await StorageService().setBiometricsEnabled(false);
        return const BiometricResult(
          success: false,
          error: 'Please set up fingerprint or face recognition in your device settings first.',
        );
      }

      final authResult = await BiometricService.authenticate('Enable biometric login');

      if (authResult.success) {
        if (userId != null && userId.isNotEmpty) {
          await StorageService().setBiometricsEnabledForAccount(userId, true);
        } else {
          await StorageService().setBiometricsEnabled(true);
        }
        debugPrint('Biometrics enabled successfully');
        return const BiometricResult(success: true);
      }

      debugPrint('Biometric authentication failed during enable: ${authResult.error}');
      return authResult;
    } catch (e) {
      debugPrint('Failed to enable biometrics: $e');
      return const BiometricResult(success: false, error: 'Failed to enable biometric login');
    }
  }

  static Future<void> disableBiometrics() async {
    try {
      await StorageService().setBiometricsEnabled(false);
      debugPrint('Biometrics disabled');
    } catch (e) {
      debugPrint('Failed to disable biometrics: $e');
    }
  }

  static Future<bool> hasPromptBeenShown([String? userId]) async {
    try {
      final storage = StorageService();
      return (userId != null && userId.isNotEmpty)
          ? await storage.getBiometricsPromptShownForAccount(userId)
          : await storage.getBiometricsPromptShown();
    } catch (e) {
      debugPrint('Failed to check prompt status: $e');
      return false;
    }
  }

  static Future<void> markPromptAsShown([String? userId]) async {
    try {
      final storage = StorageService();
      if (userId != null && userId.isNotEmpty) {
        await storage.setBiometricsPromptShownForAccount(userId, true);
      } else {
        await storage.setBiometricsPromptShown(true);
      }
    } catch (e) {
      debugPrint('Failed to mark prompt as shown: $e');
    }
  }

  static Future<void> resetPromptStatus() async {
    try {
      await StorageService().removeBiometricsPromptShown();
    } catch (e) {
      debugPrint('Failed to reset prompt status: $e');
    }
  }

  /// Per-account prompt reset — used when an enrollment is wiped so the
  /// NEXT login for THIS account offers the setup prompt again.
  static Future<void> resetPromptStatusFor(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometricsPromptShown_$userId');
    } catch (e) {
      debugPrint('Failed to reset per-account prompt status: $e');
    }
  }
}
