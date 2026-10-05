import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/api.dart' show StorageService;
import '../services/biometrics.dart';

/// Per-account "Enable Biometric Login" offer.
///
/// The login screen used to be the ONLY place the activation prompt lived,
/// and it only fired after a password login that went straight to /main.
/// Accounts that reach the dashboard through OTHER paths — freshly registered
/// (OTP verify), invited members finishing their personal profile, business
/// admins finishing the business profile — never saw the prompt. This helper
/// centralises the offer so ANY post-login path can show it.
///
/// Usage:
///   await maybeOfferBiometricSetup(context, ref);
///   if (context.mounted) context.go('/main');
///
/// The offer is gated by the SAME per-account flags the login screen uses
/// (BiometricService.isEnabled(userId) / hasPromptBeenShown(userId)), so a
/// user who enabled or skipped once is never re-prompted for that account.
Future<void> maybeOfferBiometricSetup(BuildContext context, WidgetRef ref) async {
  try {
    final userId = ref.read(authProvider).userId ?? await StorageService().getUserId();
    final canAuth = await BiometricService.canAuthenticate();
    if (!canAuth) return;
    final enabled = await BiometricService.isEnabled(userId);
    if (enabled) return;
    final promptShown = await BiometricService.hasPromptBeenShown(userId);
    if (promptShown) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        bool busy = false;
        return StatefulBuilder(
          builder: (dialogContext, setState) => PopScope(
            canPop: !busy,
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              contentPadding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: Theme.of(dialogContext).colorScheme.primary.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.fingerprint,
                        size: 42, color: Theme.of(dialogContext).colorScheme.primary),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Enable Biometric Login',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Would you like to enable biometric login for faster access to your account?',
                    style: TextStyle(
                        fontSize: 14,
                        color: Theme.of(dialogContext).colorScheme.onSurfaceVariant),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fingerprint_rounded),
                      label: const Text('Enable Biometrics'),
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              final result = await ref
                                  .read(authProvider.notifier)
                                  .enableBiometricsWithResult();
                              final uid = ref.read(authProvider).userId ??
                                  await StorageService().getUserId();
                              await BiometricService.markPromptAsShown(uid);
                              if (!dialogContext.mounted) return;
                              Navigator.of(dialogContext).pop();
                              if (!result.success && context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(
                                      result.error ?? 'Could not enable biometric login')),
                                );
                              }
                            },
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final uid = ref.read(authProvider).userId ??
                                await StorageService().getUserId();
                            await BiometricService.markPromptAsShown(uid);
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          },
                    child: const Text(
                      'Skip for Now',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  } catch (_) {
    // The offer must never block the login journey.
  }
}
