import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:io' show Platform;

import '../theme/app_theme.dart';

/// "Continue with Apple" button — shown on the login screen ONLY on iOS
/// (Guideline 4.8: an app offering third-party SSO on iOS must also offer
/// Sign in with Apple; Android keeps its Google-only layout).
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue with Apple',
    this.isLoading = false,
  });

  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;

  /// Sign In with Apple is only offered on iOS. kIsWeb guard first —
  /// Platform must never be touched on web.
  static bool get isSupported => !kIsWeb && Platform.isIOS;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.black,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.45),
          side: BorderSide(color: Colors.black, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            else
              const FaIcon(
                FontAwesomeIcons.apple,
                size: 18,
                color: Colors.white,
              ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
