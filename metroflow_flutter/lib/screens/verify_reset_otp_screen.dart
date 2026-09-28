import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../widgets/auth_ui.dart';

class VerifyResetOtpScreen extends ConsumerStatefulWidget {
  const VerifyResetOtpScreen({super.key, required this.email});
  final String email;

  @override
  ConsumerState<VerifyResetOtpScreen> createState() =>
      _VerifyResetOtpScreenState();
}

class _VerifyResetOtpScreenState extends ConsumerState<VerifyResetOtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _resendLoading = false;
  int _countdown = 60;
  bool _canResend = false;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted && _countdown > 0 && !_canResend) {
        setState(() => _countdown--);
        _startCountdown();
      } else if (_countdown == 0) {
        if (mounted) setState(() => _canResend = true);
      }
    });
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _handleVerify() async {
    if (_otpController.text.length != 6) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Error'),
          content: const Text('Please enter a valid 6-digit OTP'),
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
      final response = await api.verifyResetOtp(widget.email, _otpController.text);

      if (response.statusCode == 200) {
        if (mounted) {
          context.go('/reset-password', extra: {
            'email': widget.email,
            'otp': _otpController.text,
          });
        }
      } else {
        final data = response.data;
        throw Exception(data['message'] ?? 'Failed to verify OTP');
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

  Future<void> _handleResend() async {
    setState(() => _resendLoading = true);
    try {
      final api = ApiService();
      await api.forgotPassword(widget.email);
      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Success'),
            content: const Text('OTP resent successfully'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      setState(() {
        _countdown = 60;
        _canResend = false;
        _startCountdown();
      });
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
      if (mounted) setState(() => _resendLoading = false);
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
                title: 'Verify code',
                subtitle:
                    'Enter the verification code sent to ${widget.email}',
              ),
              const SizedBox(height: 32),
              _OtpField(controller: _otpController),
              const SizedBox(height: 24),
              AuthGradientButton(
                label: 'Verify Code',
                loading: _isLoading,
                onPressed: _handleVerify,
                icon: Icons.verified_outlined,
              ),
              const SizedBox(height: 24),
              _ResendRow(
                colors: AppTheme.colors,
                canResend: _canResend,
                countdown: _countdown,
                loading: _resendLoading,
                onResend: _handleResend,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResendRow extends StatelessWidget {
  final ThemeColors colors;
  final bool canResend;
  final int countdown;
  final bool loading;
  final VoidCallback onResend;

  const _ResendRow({
    required this.colors,
    required this.canResend,
    required this.countdown,
    required this.loading,
    required this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          "Didn't receive the code? ",
          style: TextStyle(color: colors.textSecondary, fontSize: 14),
        ),
        if (canResend)
          GestureDetector(
            onTap: loading ? null : onResend,
            child: loading
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'Resend',
                    style: TextStyle(
                      color: colors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          )
        else
          Text(
            'Resend in $countdown\u{00A0}s',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),
      ],
    );
  }
}

class _OtpField extends StatelessWidget {
  final TextEditingController controller;

  const _OtpField({required this.controller});

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border, width: 1.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: 'Enter 6-digit code',
          hintStyle: TextStyle(color: colors.textSecondary, fontSize: 15),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          counterText: '',
        ),
        keyboardType: TextInputType.number,
        maxLength: 6,
        textAlign: TextAlign.center,
        autofocus: true,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          letterSpacing: 8,
          color: AppColors.primary,
        ),
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
      ..quadraticBezierTo(
          size.width / 2, size.height + 30, size.width, size.height - 40)
      ..lineTo(size.width, 0)
      ..close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldDelegate) => false;
}
