import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../providers/auth_provider.dart';
import '../services/biometrics.dart';
import '../services/api.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  bool _biometricLoading = false;
  bool _biometricsAvailable = false;
  bool _showBiometricsSetupModal = false;

  @override
  void initState() {
    super.initState();
    _checkBiometrics();
    _loadUserName();
    _autoTriggerBiometrics();
  }

  Future<void> _autoTriggerBiometrics() async {
    // Wait for the next frame to ensure the UI is built
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    
    final biometricsEnabled = ref.read(authProvider).biometricsEnabled;
    final hasBiometrics = await BiometricService.isAvailable();
    
    if (biometricsEnabled && hasBiometrics && mounted) {
      await _handleBiometricLogin();
    }
  }

  Future<void> _loadUserName() async {
    final userName = await StorageService().getUserName();
    if (userName != null && mounted) {
      _emailController.text = userName;
    }
  }

  Future<void> _checkBiometrics() async {
    final available = await BiometricService.isAvailable();
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
      });
    }
  }

  Future<void> _checkKycAndNavigate() async {
    try {
      final api = ApiService();
      final response = await api.getKycStatus();
      final data = response.data;
      final user = data['user'] as Map<String, dynamic>?;

      if (user == null && data['bvn_verified'] == null && data['nin_verified'] == null) {
        if (mounted) context.go('/main');
        return;
      }

      final bvnVerified = user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          data['bvn_verified'] == true;
      final ninVerified = user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          data['nin_verified'] == true;
      final isTier1Verified = bvnVerified || ninVerified;

      if (!isTier1Verified) {
        if (mounted) context.go('/kyc-prompt');
      } else {
        final promptShown = await BiometricService.hasPromptBeenShown();
        final isEnabled = await BiometricService.isEnabled();
        final hasBiometrics = await BiometricService.isAvailable();

        if (hasBiometrics && !promptShown && !isEnabled) {
          if (mounted) {
            setState(() {
              _showBiometricsSetupModal = true;
            });
          }
        } else {
          if (mounted) context.go('/main');
        }
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
      final success = await ref.read(authProvider.notifier).loginWithBiometrics();
      if (success) {
        await _checkKycAndNavigate();
      } else {
        if (mounted) {
          await _showAlert('Error', 'Biometric authentication failed');
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

    setState(() {
      _isLoading = true;
    });

    try {
      await ref.read(authProvider.notifier).login(
            _emailController.text.trim(),
            _passwordController.text.trim(),
          );

      await _checkKycAndNavigate();
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
          SafeArea(
            child: KeyboardAvoidingWidget(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
                child: Column(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha:0.3),
                            offset: const Offset(0, 8),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(28),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: const Icon(Icons.login_outlined, size: 48, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Metroflow',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: colors.primary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Welcome back! Please sign in to continue',
                      style: TextStyle(fontSize: 16, color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.border, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.mail_outline, color: colors.textSecondary),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _emailController,
                              decoration: InputDecoration(
                                hintText: 'Email',
                                hintStyle: TextStyle(color: colors.textSecondary),
                                border: InputBorder.none,
                              ),
                              keyboardType: TextInputType.emailAddress,
                              style: TextStyle(color: colors.text),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      decoration: BoxDecoration(
                        color: colors.surface,
                        border: Border.all(color: colors.border, width: 1.5),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Icon(Icons.lock_outline, color: colors.textSecondary),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              decoration: InputDecoration(
                                hintText: 'Password',
                                hintStyle: TextStyle(color: colors.textSecondary),
                                border: InputBorder.none,
                              ),
                              style: TextStyle(color: colors.text),
                            ),
                          ),
                          IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: colors.textSecondary,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscurePassword = !_obscurePassword;
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {
                          context.go('/forgot-password');
                        },
                        child: Text(
                          'Forgot Password?',
                          style: TextStyle(color: colors.primary),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha: 0.25),
                            offset: const Offset(0, 8),
                            blurRadius: 16,
                            spreadRadius: 0,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 18),
                            ),
                            onPressed: _isLoading ? null : _handleLogin,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(color: Colors.white),
                                  )
                                : const Text(
                                    'Sign In',
                                    style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    if (_biometricsAvailable) ...[
                      const SizedBox(height: 24),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: biometricsEnabled ? colors.primary : colors.border, width: 2),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: TextButton.icon(
                          onPressed: _biometricLoading
                              ? null
                                  : (biometricsEnabled
                                      ? _handleBiometricLogin
                                      : () async {
                                          await _showAlert(
                                            'Enable Biometrics',
                                            'Please sign in with your password first, then enable biometric login in Settings.',
                                          );
                                        }),
                          icon: _biometricLoading
                              ? SizedBox(
                                  height: 24,
                                  width: 24,
                                  child: CircularProgressIndicator(color: colors.primary),
                                )
                              : Icon(Icons.fingerprint_outlined, size: 24, color: biometricsEnabled ? colors.primary : colors.textSecondary),
                          label: Text(
                            biometricsEnabled ? 'Sign in with Biometrics' : 'Biometrics not enabled',
                            style: TextStyle(
                              color: biometricsEnabled ? colors.primary : colors.textSecondary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Don't have an account? ",
                          style: TextStyle(color: colors.textSecondary, fontSize: 15),
                        ),
                        TextButton(
                          onPressed: () {
                            context.go('/register');
                          },
                          child: Text(
                            'Sign Up',
                            style: TextStyle(color: colors.primary, fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_showBiometricsSetupModal)
            ModalBarrier(
              color: Colors.black.withValues(alpha:0.6),
            ),
          if (_showBiometricsSetupModal)
            Center(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(32),
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
                    Icon(Icons.fingerprint, size: 56, color: colors.primary),
                    const SizedBox(height: 20),
                    const Text(
                      'Enable Biometric Login',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Would you like to enable biometric login for faster access to your account?',
                      style: TextStyle(fontSize: 15, color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: colors.primary.withValues(alpha:0.3),
                            offset: const Offset(0, 4),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.primary, colors.primaryLight],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            onPressed: _biometricLoading ? null : _handleSetupBiometrics,
                            child: _biometricLoading
                                ? const SizedBox(
                                    height: 24,
                                    width: 24,
                                    child: CircularProgressIndicator(color: Colors.white),
                                  )
                                : const Text(
                                    'Enable Biometrics',
                                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _handleSkipBiometrics,
                      child: Text(
                        'Skip for Now',
                        style: TextStyle(color: colors.textSecondary, fontSize: 16, fontWeight: FontWeight.w500),
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
