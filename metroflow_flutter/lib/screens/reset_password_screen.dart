import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../widgets/auth_ui.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key, required this.email, required this.otp});
  final String email;
  final String otp;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool _validatePassword(String password) {
    final minLength = password.length >= 8;
    final hasLetter = RegExp(r'[a-zA-Z]').hasMatch(password);
    final hasNumber = RegExp(r'[0-9]').hasMatch(password);
    final hasSymbol = !RegExp(r'^[a-zA-Z0-9]+$').hasMatch(password);
    return minLength && hasLetter && hasNumber && hasSymbol;
  }

  Future<void> _handleSubmit() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Please fill in all fields'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (newPassword != confirmPassword) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Passwords do not match'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    if (!_validatePassword(newPassword)) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: const Text(
              'Password must be at least 8 characters with letter, number, and symbol'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.resetPassword(
          widget.email, widget.otp, newPassword);

      if (response.statusCode == 200) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Success'),
              content: const Text('Password reset successfully!'),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    context.go('/login');
                  },
                  child: const Text('OK'),
                ),
              ],
            ),
          );
        }
      } else {
        final data = response.data;
        throw Exception(data['message'] ?? 'Failed to reset password');
      }
    } catch (e) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Error'),
            content: Text(e.toString()),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Gradient accent band behind the header (clipped with a curve).
          ClipPath(
            clipper: _AuthHeaderCurve(),
            child: Container(
              height: 170,
              decoration: const BoxDecoration(
                gradient: BrandSplashGradient.buttonGradient,
              ),
            ),
          ),
          AuthScreenShell(
            onBack: () => context.pop(),
            children: [
              const SizedBox(height: 6),
              AuthBrandHeader(
                title: 'Set new password',
                subtitle: 'Create a new password for your account.',
              ),
              const SizedBox(height: 32),
              AuthPasswordField(
                controller: _newPasswordController,
                hint: 'New password',
              ),
              const SizedBox(height: 12),
              AuthPasswordField(
                controller: _confirmPasswordController,
                hint: 'Confirm new password',
                onSubmitted: (_) => _handleSubmit(),
              ),
              const SizedBox(height: 10),
              _PasswordHint(colors: AppTheme.colors),
              const SizedBox(height: 20),
              AuthGradientButton(
                label: 'Reset Password',
                loading: _isLoading,
                onPressed: _handleSubmit,
                icon: Icons.lock_reset_rounded,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small muted requirements hint under the password fields.
class _PasswordHint extends StatelessWidget {
  final ThemeColors colors;

  const _PasswordHint({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.info_outline_rounded,
            size: 14, color: colors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            'At least 8 characters, with a letter, a number and a symbol.',
            style: TextStyle(
              fontSize: 12,
              color: colors.textSecondary,
              height: 1.35,
            ),
          ),
        ),
      ],
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
      ..quadraticBezierTo(
          size.width / 2, size.height + 30, size.width, size.height - 40)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}
