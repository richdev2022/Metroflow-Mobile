import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'api.dart';

class BiometricResult {
  final bool success;
  final String? error;

  BiometricResult({required this.success, this.error});
}

class BiometricService {
  static final LocalAuthentication _auth = LocalAuthentication();

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
      return BiometricResult(
        success: false,
        error: 'Biometric authentication is not available on web',
      );
    }
    try {
      // First stop any existing authentication
      try {
        await _auth.stopAuthentication();
      } catch (e) {
        // Ignore stop errors
      }
      
      final isAvailable = await BiometricService.isAvailable();
      if (!isAvailable) {
        return BiometricResult(
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
        return BiometricResult(success: true);
      } else {
        return BiometricResult(
          success: false,
          error: 'Authentication canceled or failed',
        );
      }
    } on LocalAuthException catch (e) {
      debugPrint('Biometric LocalAuthException: code=${e.code}, desc=${e.description}');
      final codeString = e.code.toString();
      
      // Handle specific errors
      if (codeString.contains('NotAvailable')) {
        return BiometricResult(
          success: false,
          error: 'Biometric authentication is not available on this device',
        );
      } else if (codeString.contains('NotEnrolled')) {
        return BiometricResult(
          success: false,
          error: 'Please set up biometrics in your device settings first',
        );
      } else if (codeString.contains('LockedOut')) {
        return BiometricResult(
          success: false,
          error: 'Biometric authentication is temporarily locked. Please try again later.',
        );
      } else if (codeString.contains('PermanentlyLockedOut')) {
        return BiometricResult(
          success: false,
          error: 'Biometric authentication is permanently locked. Please use your device password.',
        );
      } else if (codeString.contains('UserCanceled')) {
        return BiometricResult(
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
      return BiometricResult(
        success: false,
        error: 'An unexpected error occurred during authentication',
      );
    }
  }

  static Future<bool> isEnabled() async {
    try {
      final enabled = await StorageService().getBiometricsEnabled();
      debugPrint('Biometrics enabled: $enabled');
      return enabled;
    } catch (e) {
      debugPrint('Failed to check biometrics enabled status: $e');
      return false;
    }
  }

  static Future<bool> enableBiometrics() async {
    final result = await enableBiometricsWithResult();
    return result.success;
  }

  static Future<BiometricResult> enableBiometricsWithResult() async {
    try {
      debugPrint('Attempting to enable biometrics...');
      final isAvailable = await BiometricService.isAvailable();
      if (!isAvailable) {
        debugPrint('Biometrics unavailable or not enrolled');
        await StorageService().setBiometricsEnabled(false);
        return BiometricResult(
          success: false,
          error: 'Please set up fingerprint or face recognition in your device settings first.',
        );
      }

      final authResult = await BiometricService.authenticate('Enable biometric login');
      
      if (authResult.success) {
        await StorageService().setBiometricsEnabled(true);
        debugPrint('Biometrics enabled successfully');
        return BiometricResult(success: true);
      }
      
      debugPrint('Biometric authentication failed during enable: ${authResult.error}');
      return authResult;
    } catch (e) {
      debugPrint('Failed to enable biometrics: $e');
      return BiometricResult(success: false, error: 'Failed to enable biometric login');
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

  static Future<bool> hasPromptBeenShown() async {
    try {
      return await StorageService().getBiometricsPromptShown();
    } catch (e) {
      debugPrint('Failed to check prompt status: $e');
      return false;
    }
  }

  static Future<void> markPromptAsShown() async {
    try {
      await StorageService().setBiometricsPromptShown(true);
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
}
