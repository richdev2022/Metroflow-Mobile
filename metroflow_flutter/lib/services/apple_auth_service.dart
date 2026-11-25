import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Result of a successful Apple sign-in — the raw materials the backend's
/// `POST /auth/apple` route needs to verify the user and mint an app session.
class AppleSignInResult {
  const AppleSignInResult({
    required this.identityToken,
    required this.authorizationCode,
    required this.userIdentifier,
    this.givenName,
    this.familyName,
    this.email,
  });

  /// Apple's signed JWT identifying the user — verified server-side against
  /// Apple's public keys (the same role the Google ID token plays).
  final String identityToken;

  /// One-time code the backend MAY exchange for a refresh token; sent for
  /// auditability/parity with Apple's server-to-server flow.
  final String authorizationCode;

  /// Stable Apple user identifier (same value for every future sign-in on
  /// apps under the same Apple Developer team).
  final String userIdentifier;

  /// ONLY present on the FIRST grant (user hides email / subsequent grants
  /// return nulls) — the client must forward them on that first grant so the
  /// backend can store a displayable name.
  final String? givenName;
  final String? familyName;

  /// The user's email (real or Apple relay address). First grant + any
  /// later sign-in where Apple still shares it.
  final String? email;
}

/// Error thrown when Apple sign-in fails for a reason that is safe to show
/// directly to the user ([message] is already friendly).
class AppleSignInException implements Exception {
  AppleSignInException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thin wrapper around `sign_in_with_apple` used for Apple SSO (iOS).
///
/// Mirrors [GoogleAuthService]: returns null when the user cancels, throws
/// [AppleSignInException] with a user-friendly message on real failures, and
/// hands back the [AppleSignInResult] to be exchanged on the backend via
/// `POST /auth/apple { identityToken, authorizationCode, user }`.
class AppleAuthService {
  static final AppleAuthService _instance = AppleAuthService._internal();
  factory AppleAuthService() => _instance;

  AppleAuthService._internal();

  /// Sign In with Apple is only offered on iOS (Guideline 4.8 requires it
  /// exactly where third-party logins are shown; Android uses Google SSO).
  /// kIsWeb guard first — Platform must never be touched on web.
  bool get isSupported => !kIsWeb && Platform.isIOS;

  /// Opens the Apple sign-in sheet (with full name + email scopes so the
  /// backend can register the account) and resolves the credential.
  ///
  /// Returns `null` when the user cancelled the sheet — not an error.
  Future<AppleSignInResult?> signIn() async {
    if (!isSupported) {
      throw AppleSignInException(
        'Sign in with Apple is available on iPhone and iPad. Please continue '
        'with your email and password.',
      );
    }

    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const <AppleIDAuthorizationScopes>[
          AppleIDAuthorizationScopes.fullName,
          AppleIDAuthorizationScopes.email,
        ],
      );

      final identityToken = _utf8(credential.identityToken);
      final authorizationCode = _utf8(credential.authorizationCode);
      if (identityToken == null || identityToken.isEmpty) {
        throw AppleSignInException(
          'Apple sign-in did not return an identity token. Please try again '
          'or continue with your email and password.',
        );
      }

      return AppleSignInResult(
        identityToken: identityToken,
        authorizationCode: authorizationCode ?? '',
        userIdentifier: credential.userIdentifier,
        givenName: _clean(credential.givenName),
        familyName: _clean(credential.familyName),
        email: _clean(credential.email),
      );
    } on SignInWithAppleCanceledException {
      // User closed the Apple sheet — not an error.
      return null;
    } on SignInWithAppleNotSupportedException {
      throw AppleSignInException(
        'Sign in with Apple is not available on this device. Please continue '
        'with your email and password.',
      );
    } on PlatformException catch (e) {
      // Belt & braces: some plugin paths surface cancellation as a raw
      // PlatformException (iOS ASAuthorizationError.canceled = 1001).
      final detailCode = (e.details is Map)
          ? (e.details as Map)['code']
          : e.details;
      if (e.code.toUpperCase().contains('CANCEL') || detailCode == 1001) {
        return null;
      }
      throw AppleSignInException(_mapError(e));
    } on AppleSignInException {
      rethrow;
    } catch (e) {
      throw AppleSignInException(_mapError(e));
    }
  }

  static String? _utf8(List<int>? bytes) {
    if (bytes == null || bytes.isEmpty) return null;
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String? _clean(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _mapError(Object error) {
    final raw = error.toString().toLowerCase();
    if (raw.contains('network') ||
        raw.contains('-1009') ||
        raw.contains('nsurlerrordomain')) {
      return 'Network error while contacting Apple. Please check your '
          'internet connection and try again.';
    }
    if (raw.contains('invalid_response') || raw.contains('key')) {
      return 'Sign in with Apple is blocked by the app configuration. Please '
          'update the app or contact support.';
    }
    return 'Apple sign-in failed. Please try again or continue with your '
        'email and password.';
  }

  /// Apple sign-in holds no persistent client session (the sheet is shown
  /// fresh every time), so logout is a no-op — kept for parity with
  /// [GoogleAuthService.signOut] call sites.
  Future<void> signOut() async {}
}
