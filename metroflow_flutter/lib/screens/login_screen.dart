import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../components/google_sign_in_button.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/biometrics.dart';
import '../services/api.dart';
import '../services/app_update_service.dart';
import '../widgets/auth_ui.dart';
import '../widgets/maintenance_gate.dart';
import 'permission_primer.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;
  bool _biometricLoading = false;
  bool _biometricsAvailable = false;
  bool _showBiometricsSetupModal = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadUserName();
    // BIOMETRICS ARE CLICK-TO-USE ONLY (user requirement): no auto-trigger of
    // the fingerprint prompt when the login screen opens. The user explicitly
    // taps "Sign in with Biometrics" — that button runs _handleBiometricLogin
    // (local_auth prompt -> POST /auth/biometric/login). Auto-prompting at
    // initState also raced the button: two overlapping local_auth calls on
    // Android make the first fingerprint read fail, which forced users to
    // authenticate multiple times before sign-in went through.
  }

  Future<void> _loadUserName() async {
    final userName = await StorageService().getUserName();
    if (userName != null && mounted) {
      _emailController.text = userName;
    }
  }

  Future<void> _checkBiometrics() async {
    final available = await BiometricService.canAuthenticate();
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
      });
    }
  }

  Future<void> _checkKycAndNavigate() async {
    // ONBOARDING CHANGE: a freshly-registered (or not-yet-KYC'd) account now
    // goes STRAIGHT to the dashboard. BVN/NIN/proof-of-address are no longer
    // part of the login journey — KYC is only demanded when the user tries to
    // USE a financial feature (wallet, transfers, payroll, payment links,
    // subscriptions...), which main_screen's finance gate enforces.
    //
    // PERSONAL PROFILE GATE (invited members): the backend decides via
    // /auth/me — business admins never get requiresProfileCompletion, so
    // they keep the BUSINESS completion flow (/profile-complete, gated in
    // the login handlers). Invited members land on the PERSONAL completion
    // screen (photo, name, read-only email, phone OTP, skip). Skipped
    // prompts are remembered server-side and never re-nag.
    //
    // PER-ACCOUNT BIOMETRIC PROMPT: the setup offer is keyed by the account
    // that just signed in — every NEW account is asked to activate biometrics
    // on its first login, even if a previous account on this device already
    // enabled (or dismissed) it. The prompt re-appears for an account until
    // it either enables biometrics or explicitly skips ONCE (remembered
    // per-account, not device-wide).
    try {
      // Personal completion gate first (best-effort — never blocks login).
      try {
        final meResponse = await ApiService().getMe();
        final meData = meResponse.data is Map ? meResponse.data['data'] : null;
        if (meData is Map && meData['requiresProfileCompletion'] == true) {
          if (mounted) {
            context.go('/profile-completion');
            return;
          }
        }
      } catch (_) {}

      final userId = ref.read(authProvider).userId ?? await StorageService().getUserId();
      final isEnabled = await BiometricService.isEnabled(userId);
      final promptShown = await BiometricService.hasPromptBeenShown(userId);
      final canAuth = await BiometricService.canAuthenticate();

      if (canAuth && !isEnabled && !promptShown) {
        if (mounted) {
          setState(() {
            _showBiometricsSetupModal = true;
          });
        }
      } else {
        if (mounted) context.go('/main');
      }
    } catch (e) {
      if (mounted) context.go('/main');
    }
  }

  Future<void> _handleBiometricLogin() async {
    setState(() {
      _biometricLoading = true;
    });

    try {
      // Server-backed flow: local_auth prompt (with device-PIN fallback) →
      // POST /auth/biometric/login with the stored per-device token.
      final result = await ref.read(authProvider.notifier).loginWithBiometrics();
      if (result.success) {
        await _checkKycAndNavigate();
        await PermissionPrimer.maybeShow();
      } else {
        if (mounted) {
          await _showAlert('Sign in', result.error ?? 'Biometric authentication failed');
        }
      }
    } catch (e) {
      if (mounted) {
        await _showAlert(
            'Error', 'An error occurred during biometric authentication');
      }
    } finally {
      if (mounted) {
        setState(() {
          _biometricLoading = false;
        });
      }
    }
  }

  Future<void> _handleSetupBiometrics() async {
    setState(() {
      _biometricLoading = true;
    });

    try {
      final result = await ref.read(authProvider.notifier).enableBiometricsWithResult();
      if (result.success) {
        await BiometricService.markPromptAsShown();
        if (mounted) {
          setState(() {
            _showBiometricsSetupModal = false;
          });
          await _showAlert(
              'Success', 'Biometric login enabled successfully!',
              onExtra: () => context.go('/main'));
        }
      } else {
        if (mounted) {
          await _showAlert('Error', result.error ?? 'Failed to enable biometric login');
        }
      }
    } catch (e) {
      if (mounted) {
        await _showAlert('Error', 'An error occurred');
      }
    } finally {
      if (mounted) {
        setState(() {
          _biometricLoading = false;
        });
      }
    }
  }

  Future<void> _handleSkipBiometrics() async {
    await BiometricService.markPromptAsShown();
    if (!mounted) return;
    setState(() {
      _showBiometricsSetupModal = false;
    });
    if (mounted) context.go('/main');
  }

  Future<void> _showAlert(String title, String message,
      {VoidCallback? onExtra}) async {
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onExtra?.call();
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogin() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      await _showAlert('Error', 'Please enter email and password');
      return;
    }

    // MAINTENANCE GATE (web parity): never let a sign-in through during a
    // maintenance window. The global overlay covers the app anyway; this
    // re-check closes the 60s polling gap so the user gets instant feedback
    // instead of a 503 from the server.
    if (await MaintenanceGate.checkNow()) {
      await _showAlert(
          'Under maintenance',
          'Metricorex is undergoing scheduled maintenance. '
          'Please try again in a little while.');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(authProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );

      await _checkKycAndNavigate();
      // One-time permissions primer (never blocks — flag-gated inside).
      await PermissionPrimer.maybeShow();
      // In-app update prompt: checked shortly after landing so the target
      // screen settles first. Silent on any failure; force-updates always
      // show, optional ones respect per-version dismissal.
      Future.delayed(const Duration(seconds: 2), () {
        AppUpdateService.instance.checkAndPrompt(source: 'login');
      });
    } catch (e) {
      final errorMsg = e.toString();
      if (errorMsg.contains('OTP required')) {
        if (mounted) {
          context.push('/verify-otp',
              extra: _emailController.text.trim());
        }
      } else {
        await _showAlert('Login Error', errorMsg);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Google SSO: sign in with the Google account picker, then reuse the
  /// exact same post-login routing as password login (KYC check → biometrics
  /// prompt / kyc-prompt / main). Password-setup hint is handled by the
  /// provider itself (non-blocking).
  Future<void> _handleGoogleSignIn() async {
    if (_isGoogleLoading) return;

    // MAINTENANCE GATE (same rationale as password login above).
    if (await MaintenanceGate.checkNow()) {
      await _showAlert(
          'Under maintenance',
          'Metricorex is undergoing scheduled maintenance. '
          'Please try again in a little while.');
      return;
    }

    setState(() {
      _isGoogleLoading = true;
    });

    try {
      final success = await ref.read(authProvider.notifier).loginWithGoogle();
      if (!success) return; // user cancelled — no error, stay on screen

      // SSO PROFILE-COMPLETION GATE (role-aware): invited members complete
      // their PERSONAL profile (photo, name, read-only email, phone OTP,
      // skip); business admins complete the BUSINESS profile (name,
      // industry, phone, logo). The backend now returns role-aware flags on
      // /auth/google — requiresProfileCompletion wins over profileCompleted.
      final meResponse = await ApiService().getMe();
      final meData = meResponse.data is Map ? meResponse.data['data'] : null;
      if (meData is Map && meData['requiresProfileCompletion'] == true) {
        if (mounted) {
          context.go('/profile-completion');
          return;
        }
      }
      final profileCompleted = ref.read(authProvider).profileCompleted;
      if (profileCompleted == false) {
        if (mounted) context.go('/profile-complete');
        return;
      }

      await _checkKycAndNavigate();
      // One-time permissions primer (never blocks — flag-gated inside).
      await PermissionPrimer.maybeShow();
      // Same post-login update prompt as password login (de-duped inside
      // AppUpdateService when the startup hook already ran).
      Future.delayed(const Duration(seconds: 2), () {
        AppUpdateService.instance.checkAndPrompt(source: 'google-login');
      });
    } catch (e) {
      if (mounted) {
        await _showAlert('Google Sign-In', _friendlyError(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isGoogleLoading = false;
        });
      }
    }
  }

  String _friendlyError(Object e) {
    // DioException: surface the backend's message (or a friendly fallback) —
    // NEVER the raw "DioException [bad response] ..." toString, which users
    // cannot act on. Safe against non-JSON bodies (HTML error pages etc.).
    if (e is DioException) {
      final data = e.response?.data;
      final dynamic message = data is Map
          ? (data['message'] ?? data['error'])
          : (data is String && data.isNotEmpty && !data.startsWith('<')
              ? data
              : null);
      if (message is String && message.trim().isNotEmpty &&
          !message.startsWith('DioException')) {
        return message.trim();
      }
      if (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout) {
        return 'Network error. Please check your connection and try again.';
      }
      if (e.response?.statusCode != null && e.response!.statusCode! >= 500) {
        return 'Server error. Please try again in a moment.';
      }
      return 'Sign-in failed. Please try again.';
    }
    final message = e.toString();
    if (message.startsWith('Exception: ')) {
      return message.substring('Exception: '.length);
    }
    return message;
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final biometricsEnabled = ref.watch(authProvider).biometricsEnabled;

    return Scaffold(
      body: Stack(
        children: [
          // Gradient accent band behind the header (clipped with a curve).
          ClipPath(
            clipper: _AuthHeaderCurve(),
            child: Container(
              height: 190,
              decoration: const BoxDecoration(
                gradient: BrandSplashGradient.buttonGradient,
              ),
            ),
          ),
          AuthScreenShell(
            onBack: null,
            children: [
              const SizedBox(height: 6),
              const AuthBrandHeader(
                title: 'Welcome back',
                subtitle: 'Sign in to keep your business moving.',
              ),
              const SizedBox(height: 32),
              AuthTextField(
                controller: _emailController,
                hint: 'Email',
                icon: Icons.alternate_email_rounded,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 14),
              AuthPasswordField(
                controller: _passwordController,
                hint: 'Password',
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // push (NOT go): keep the login screen on the stack so the
                    // back arrow on forgot-password actually pops back.
                    context.push('/forgot-password');
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              AuthGradientButton(
                label: 'Sign In',
                loading: _isLoading,
                onPressed: _handleLogin,
                icon: Icons.login_rounded,
              ),
              if (_biometricsAvailable) ...[
                const SizedBox(height: 16),
                _BiometricButton(
                  loading: _biometricLoading,
                  enabled: biometricsEnabled,
                  onPressed: () async {
                    if (biometricsEnabled) {
                      await _handleBiometricLogin();
                    } else {
                      await _showAlert(
                        'Enable Biometrics',
                        'Please sign in with your password first, then enable biometric login in Settings.',
                      );
                    }
                  },
                ),
              ],
              const SizedBox(height: 22),
              const OrDivider(),
              const SizedBox(height: 16),
              GoogleSignInButton(
                onPressed: _handleGoogleSignIn,
                isLoading: _isGoogleLoading,
              ),
              const SizedBox(height: 22),
              AuthSwitchPrompt(
                question: "Don't have an account?",
                actionLabel: 'Sign Up',
                onTap: () {
                  context.go('/register');
                },
              ),
            ],
          ),
          if (_showBiometricsSetupModal)
            ModalBarrier(
              color: Colors.black.withValues(alpha: 0.6),
            ),
          if (_showBiometricsSetupModal)
            Center(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(28),
                constraints: const BoxConstraints(maxWidth: 480),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      offset: const Offset(0, 10),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: colors.primaryBg,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.fingerprint, size: 42, color: colors.primary),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Enable Biometric Login',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Would you like to enable biometric login for faster access to your account?',
                      style: TextStyle(fontSize: 14, color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 26),
                    AuthGradientButton(
                      label: 'Enable Biometrics',
                      loading: _biometricLoading,
                      onPressed: _handleSetupBiometrics,
                      icon: Icons.fingerprint_rounded,
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _handleSkipBiometrics,
                      child: Text(
                        'Skip for Now',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Soft curved bottom edge for the gradient header band.
class _AuthHeaderCurve extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(0, size.height - 40)
      ..quadraticBezierTo(size.width / 2, size.height + 30, size.width, size.height - 40)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}

/// Outlined biometric sign-in button (kept visually quiet vs the main CTA).
class _BiometricButton extends StatelessWidget {
  final bool loading;
  final bool enabled;
  final Future<void> Function() onPressed;

  const _BiometricButton({
    required this.loading,
    required this.enabled,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: loading
            ? null
            : () async {
                await onPressed();
              },
        style: OutlinedButton.styleFrom(
          foregroundColor: enabled ? colors.primary : colors.textSecondary,
          backgroundColor: enabled ? colors.primaryBg : colors.surface,
          side: BorderSide(
            color: enabled
                ? colors.primary.withValues(alpha: 0.5)
                : colors.border,
            width: 1.4,
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        icon: loading
            ? SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(color: colors.primary, strokeWidth: 2),
              )
            : const Icon(Icons.fingerprint_outlined, size: 22),
        label: Text(
          enabled ? 'Sign in with Biometrics' : 'Biometrics not enabled',
          style: TextStyle(
            color: enabled ? colors.primary : colors.textSecondary,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class KeyboardAvoidingWidget extends StatelessWidget {
  final Widget child;

  const KeyboardAvoidingWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    );
  }
}
