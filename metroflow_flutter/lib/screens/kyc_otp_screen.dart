import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../providers/kyc_provider.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class KycOtpScreen extends ConsumerStatefulWidget {
  const KycOtpScreen({super.key});

  @override
  ConsumerState<KycOtpScreen> createState() => _KycOtpScreenState();
}

class _KycOtpScreenState extends ConsumerState<KycOtpScreen> {
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  int _resendSeconds = 30;
  Timer? _resendTimer;
  String _type = 'bvn';
  String? _number;
  String? _phone;
  String? _firstName;
  String? _lastName;

  @override
  void initState() {
    super.initState();
    _startResendCountdown();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    final queryType = GoRouterState.of(context).uri.queryParameters['type'];
    if (extra is Map<String, dynamic>) {
      _type = ((extra['type'] as String?) ?? queryType ?? 'bvn').toLowerCase() == 'nin' ? 'nin' : 'bvn';
      _number = extra['number'] as String?;
      _phone = extra['phone'] as String?;
      _firstName = extra['firstName'] as String?;
      _lastName = extra['lastName'] as String?;
    } else {
      _type = (queryType ?? 'bvn').toLowerCase() == 'nin' ? 'nin' : 'bvn';
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _otpController.dispose();
    super.dispose();
  }

  void _startResendCountdown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendSeconds <= 1) {
        timer.cancel();
        if (mounted) setState(() => _resendSeconds = 0);
        return;
      }
      if (mounted) setState(() => _resendSeconds -= 1);
    });
  }

  Future<void> _handleResendOtp() async {
    if (_resendSeconds > 0 || _isResending) return;
    final number = _number;
    if (number == null || number.isEmpty) {
      AppToast.show('Please restart verification to request a new OTP');
      context.go('/kyc-prompt?type=$_type');
      return;
    }

    setState(() => _isResending = true);
    try {
      final response = await ApiService().initiateKyc(_type, number);
      final responseData = response.data as Map<String, dynamic>;
      setState(() {
        _phone = responseData['phone'];
        _firstName = responseData['firstName'];
        _lastName = responseData['lastName'];
      });
      AppToast.show('OTP resent successfully', type: AppToastType.success);
      _startResendCountdown();
    } catch (e) {
      debugPrint('Failed: $e');
    } finally {
      if (mounted) setState(() => _isResending = false);
    }
  }

  Future<void> _handleVerify() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      AppToast.show('Please enter a valid 6-digit OTP');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.verifyKycOtp(otp);
      if (response.statusCode == 200) {
        await ref.read(kycProvider.notifier).fetchKycStatus();
        final kycState = ref.read(kycProvider);
        if (kycState.status == null || !kycState.status!.isTier2Verified) {
          if (mounted) context.go('/kyc-prompt');
        } else if (kycState.status!.isTier3Verified) {
          if (mounted) context.go('/main');
        } else {
          if (mounted) context.go('/main/business-kyc');
        }
      }
    } catch (e) {
      debugPrint('Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final canSubmit = _otpController.text.length == 6 && !_isLoading;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colors.text),
                    onPressed: () {
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go('/kyc-prompt');
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Verify OTP',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              if (_firstName != null || _lastName != null || _phone != null) ...[
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: colors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Verification details',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (_firstName != null || _lastName != null)
                        Text(
                          '${_firstName ?? ''} ${_lastName ?? ''}'.trim(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: colors.text,
                          ),
                        ),
                      if (_phone != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Code sent to $_phone',
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],
              Text(
                'Enter the 6-digit code sent to your registered phone number or email address.',
                style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
              ),
              const SizedBox(height: 8),
              Text(
                'Verifying ${_type.toUpperCase()}',
                style: TextStyle(fontSize: 14, color: colors.primary, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 40),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colors.border, width: 1.5),
                ),
                child: TextField(
                  controller: _otpController,
                  autofocus: true,
                  textAlign: TextAlign.center,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '000000',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    border: InputBorder.none,
                  ),
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 12,
                    color: colors.text,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(height: 40),
              Opacity(
                opacity: canSubmit ? 1 : 0.5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF3B82F6)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: canSubmit ? _handleVerify : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      disabledBackgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white)
                        : const Text('Verify & Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              TextButton(
                onPressed: _resendSeconds == 0 && !_isResending ? _handleResendOtp : null,
                child: Text.rich(
                  TextSpan(
                    text: _resendSeconds > 0
                        ? 'Resend OTP in ${_resendSeconds}s'
                        : "Didn't receive code? ",
                    style: TextStyle(fontSize: 14, color: colors.textSecondary),
                    children: _resendSeconds > 0
                        ? const []
                        : [
                      TextSpan(
                        text: _isResending ? 'Resending...' : 'Resend OTP',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
