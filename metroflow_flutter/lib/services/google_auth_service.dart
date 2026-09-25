import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// Error thrown when Google sign-in fails for a reason that is safe to show
/// directly to the user (the [message] is already friendly).
class GoogleSignInException implements Exception {
  GoogleSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around `google_sign_in` used for Google SSO.
///
/// - Requests the standard `email profile openid` scopes.
/// - [signIn] resolves with the Google **ID token** (JWT) to be exchanged on
///   the backend via `POST /auth/google { credential }`.
/// - Returns `null` when the user cancels the account picker.
/// - Maps Play-Services / configuration failures to friendly messages
///   (e.g. devices without Google Play services) instead of leaking raw
///   platform exceptions.
class GoogleAuthService {
  static final GoogleAuthService _instance = GoogleAuthService._internal();
  factory GoogleAuthService() => _instance;

  GoogleAuthService._internal()
      : _googleSignIn = GoogleSignIn(
          scopes: <String>['email', 'profile', 'openid'],
          // On Android an ID token is only issued when the *Web* client ID is
          // provided. Configure it in Google Cloud Console and set
          // EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID in .env (optional on iOS/Web).
          serverClientId: _resolveWebClientId(),
        );

  final GoogleSignIn _googleSignIn;

  static String? _resolveWebClientId() {
    try {
      final value = dotenv.env['EXPO_PUBLIC_GOOGLE_WEB_CLIENT_ID'];
      if (value == null || value.trim().isEmpty) return null;
      return value.trim();
    } catch (_) {
      // dotenv not initialised (e.g. unit tests) — degrade gracefully.
      return null;
    }
  }

  /// Opens the Google account picker and returns the Google ID token.
  ///
  /// Returns `null` when the user cancels the flow. Throws a
  /// [GoogleSignInException] with a user-friendly message on failure.
  Future<String?> signIn() async {
    try {
      final GoogleSignInAccount? account = await _googleSignIn.signIn();
      if (account == null) {
        // User closed the account picker / cancelled sign-in.
        return null;
      }

      final GoogleSignInAuthentication auth = await account.authentication;
      final String? idToken = auth.idToken;

      if (idToken == null || idToken.isEmpty) {
        // Force a clean state so the next attempt re-opens the account picker.
        await signOut();
        throw GoogleSignInException(
          'Google Sign-In did not return an ID token. Please check the '
          'app\u2019s Google client configuration and try again.',
        );
      }

      return idToken;
    } on GoogleSignInException {
      rethrow;
    } catch (e) {
      if (_isCancelled(e)) return null;
      throw GoogleSignInException(_mapError(e));
    }
  }

  bool _isCancelled(Object error) {
    final raw = error.toString().toLowerCase();
    return raw.contains('sign_in_cancelled') ||
        raw.contains('apiexception: 12501') ||
        raw.contains('code 12501');
  }

  String _mapError(Object error) {
    final raw = error.toString().toLowerCase();

    // Devices without (or with broken) Google Play services — ApiException 10
    // is DEVELOPER_ERROR (also raised when the app isn't registered with the
    // right SHA-1/package name), 17 is API_NOT_CONNECTED.
    if (raw.contains('sign_in_failed') ||
        raw.contains('apiexception: 10') ||
        raw.contains('apiexception: 17') ||
        raw.contains('developer_error')) {
      return 'Google Sign-In is not available on this device. Please make '
          'sure Google Play services are installed and up to date, then try '
          'again — or continue with your email and password.';
    }
    if (raw.contains('network_error') || raw.contains('apiexception: 7')) {
      return 'Network error while contacting Google. Please check your '
          'internet connection and try again.';
    }
    if (raw.contains('missingpluginexception')) {
      return 'Google Sign-In is not supported on this platform.';
    }
    return 'Google Sign-In failed. Please try again or continue with your '
        'email and password.';
  }

  /// Signs out of the current Google session (does NOT affect the app's own
  /// session — used on logout so the account picker appears again next time).
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      debugPrint('GoogleAuthService.signOut failed: $e');
    }
  }

  /// Revokes access entirely (best effort, used for hard resets).
  Future<void> disconnect() async {
    try {
      await _googleSignIn.disconnect();
    } catch (e) {
      debugPrint('GoogleAuthService.disconnect failed: $e');
    }
  }
}
