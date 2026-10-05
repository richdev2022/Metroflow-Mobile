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

  static Future<bool> hasHardware() async {
    if (kIsWeb) {
      return false;
    }
    try {
      final supported = await _auth.isDeviceSupported();
      if (!supported) return false;

      // Try canCheckBiometrics first
      bool canCheck = false;
      try {
        canCheck = await _auth.canCheckBiometrics;
      } catch (e) {
        debugPrint('Error checking canCheckBiometrics: $e');
      }

      if (canCheck) {
        // Check for available biometrics
        try {
          final biometrics = await _auth.getAvailableBiometrics();
          return biometrics.isNotEmpty;
        } catch (e) {
          debugPrint('Error getting available biometrics: $e');
          return true; // If we can check, assume available
        }
      }

      // Fallback: if canCheck fails, just return supported status
      return supported;
    } catch (e) {
      debugPrint('Failed to check biometric hardware: $e');
      return false;
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
    try {
      return await _auth.isDeviceSupported();
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
      final biometrics = await _auth.getAvailableBiometrics();
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
      return await _auth.getAvailableBiometrics();
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

      final result = await _auth.authenticate(
        localizedReason: promptMessage,
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        sensitiveTransaction: false,
      );

      debugPrint('Biometric result: $result');

      if (result) {
        return const BiometricResult(success: true);
      } else {
        return const BiometricResult(
          success: false,
          error: 'Authentication canceled or failed',
        );
      }
    } on LocalAuthException catch (e) {
      debugPrint('Biometric LocalAuthException: code=${e.code}, desc=${e.description}');
      final codeString = e.code.toString();
      
      // Handle specific errors
      if (codeString.contains('NotAvailable')) {
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is not available on this device',
        );
      } else if (codeString.contains('NotEnrolled')) {
        return const BiometricResult(
          success: false,
          error: 'Please set up biometrics in your device settings first',
        );
      } else if (codeString.contains('LockedOut')) {
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is temporarily locked. Please try again later.',
        );
      } else if (codeString.contains('PermanentlyLockedOut')) {
        return const BiometricResult(
          success: false,
          error: 'Biometric authentication is permanently locked. Please use your device password.',
        );
      } else if (codeString.contains('UserCanceled')) {
        return const BiometricResult(
          success: false,
          error: 'Authentication was canceled',
        );
      }

      // Fallback to description or generic message
      final description = e.description;
      return BiometricResult(
        success: false,
        error: description != null && description.isNotEmpty
            ? description
            : 'Biometric authentication failed',
      );
    } catch (e) {
      debugPrint('Biometric authentication generic error: $e');
      return const BiometricResult(
        success: false,
        error: 'An unexpected error occurred during authentication',
      );
    }
  }

  /// Biometrics enabled — PER-ACCOUNT when a userId is given (falls back to
  /// the legacy device-wide flag for installs that never stored a per-account
  /// value). Without a userId this is the raw legacy flag.
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
