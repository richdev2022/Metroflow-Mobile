import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/kyc_provider.dart';
import '../providers/auth_provider.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../utils/app_toast.dart';

enum KycFlowStep { prompt, initiate, otp }

class KycPromptScreen extends ConsumerStatefulWidget {
  const KycPromptScreen({super.key});

  @override
  ConsumerState<KycPromptScreen> createState() => _KycPromptScreenState();
}

class _KycPromptScreenState extends ConsumerState<KycPromptScreen> {
  KycFlowStep _currentStep = KycFlowStep.prompt;
  String? _selectedType;
  final _numberController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isLoading = false;
  bool _isResending = false;
  int _resendSeconds = 30;
  Timer? _resendTimer;
  String? _phone;
  String? _firstName;
  String? _lastName;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(kycProvider.notifier).fetchKycStatus());
  }

  @override
  void dispose() {
    _numberController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
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

  Future<void> _handleSkipToDashboard() async {
    await ref.read(authProvider.notifier).skipKyc();
    if (!mounted) return;
    context.go('/main');
  }

  Future<void> _handleLogout() async {
    await ref.read(authProvider.notifier).logout();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _handleInitiateKyc(String type) async {
    final number = _numberController.text.replaceAll(RegExp(r'\D'), '');
    if (number.length != 11) {
      AppToast.show('Please enter a valid 11-digit ${type == 'bvn' ? 'BVN' : 'NIN'}');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.initiateKyc(type, number);
      final responseData = response.data as Map<String, dynamic>;
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _phone = responseData['phone'];
            _firstName = responseData['firstName'];
            _lastName = responseData['lastName'];
            _currentStep = KycFlowStep.otp;
          });
          _startResendCountdown();
        }
      });
    } catch (e) {
      debugPrint('KYC initiate error: $e');
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleResendOtp() async {
    if (_resendSeconds > 0 || _isResending || _selectedType == null || _numberController.text.isEmpty) return;

    setState(() => _isResending = true);
    try {
      final response = await ApiService().initiateKyc(_selectedType!, _numberController.text.replaceAll(RegExp(r'\D'), ''));
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

  Future<void> _handleVerifyOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length != 6) {
      AppToast.show('Please enter a valid 6-digit OTP');
      return;
    }

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.verifyKycOtp(otp);
      if (response.statusCode == 200) {
        await ref.read(kycProvider.notifier).fetchKycStatus();
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final kycState = ref.read(kycProvider);
            if (kycState.status?.isTier2Verified ?? false) {
              context.go('/main/business-kyc');
            } else {
              setState(() {
                _currentStep = KycFlowStep.prompt;
                _selectedType = null;
                _numberController.clear();
                _otpController.clear();
              });
              _resendTimer?.cancel();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Failed: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _resetFlow() {
    setState(() {
      _currentStep = KycFlowStep.prompt;
      _selectedType = null;
      _numberController.clear();
      _otpController.clear();
    });
    _resendTimer?.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final bvnVerified = ref.watch(kycProvider.select((state) => state.status?.user.bvnStatus == 'verified'));
    final ninVerified = ref.watch(kycProvider.select((state) => state.status?.user.ninStatus == 'verified'));
    final isLoading = ref.watch(kycProvider.select((state) => state.isLoading && state.status == null));

    if (isLoading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: MediaQuery.of(context).size.height - 48),
            child: _currentStep == KycFlowStep.prompt
                ? _buildPrompt(colors, bvnVerified, ninVerified)
                : _currentStep == KycFlowStep.initiate
                ? _buildInitiate(colors)
                : _buildOtp(colors),
          ),
        ),
      ),
    );
  }

  Widget _buildPrompt(ThemeColors colors, bool bvnVerified, bool ninVerified) {
    return Column(
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
                  context.go('/main');
                }
              },
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                'Identity Verification',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          bvnVerified || ninVerified
              ? 'Verify your remaining identity document to upgrade to Tier 2.'
              : 'Complete KYC verification to access your wallet and all features.',
          style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
        ),
        const SizedBox(height: 40),
        _buildOptionCard(
          context: context,
          title: 'Verify with BVN',
          subtitle: 'Bank Verification Number',
          isVerified: bvnVerified,
          onTap: () {
            setState(() {
              _selectedType = 'bvn';
              _currentStep = KycFlowStep.initiate;
            });
          },
        ),
        const SizedBox(height: 16),
        _buildOptionCard(
          context: context,
          title: 'Verify with NIN',
          subtitle: 'National Identification Number',
          isVerified: ninVerified,
          onTap: () {
            setState(() {
              _selectedType = 'nin';
              _currentStep = KycFlowStep.initiate;
            });
          },
        ),
        const SizedBox(height: 40),
        if (bvnVerified && ninVerified)
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [colors.primary, AppColors.primaryLight],
              ),
            ),
            child: ElevatedButton(
              onPressed: () => context.go('/main'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text(
                'Continue to Home',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        if ((bvnVerified || ninVerified) && !(bvnVerified && ninVerified))
          Column(
            children: [
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
                        colors: [colors.primary, AppColors.primaryLight],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: ElevatedButton(
                      onPressed: _handleSkipToDashboard,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                      ),
                      child: const Text(
                        'Skip to Dashboard',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _handleLogout,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                  ),
                  child: const Text(
                    'Logout',
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.error,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          )
        else if (!bvnVerified && !ninVerified)
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: _handleLogout,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 18),
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.error,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildInitiate(ThemeColors colors) {
    final type = _selectedType ?? 'bvn';
    final title = '${type.toUpperCase()} Verification';
    final subtitle = type == 'bvn'
        ? 'Please enter your 11-digit Bank Verification Number to verify your identity.'
        : 'Please enter your 11-digit National Identification Number to verify your identity.';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: colors.text),
              onPressed: _resetFlow,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
              ),
            ),
          ],
        ),
        const SizedBox(height: 32),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 16, color: Colors.grey, height: 1.5),
        ),
        const SizedBox(height: 40),
        Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.border, width: 1.5),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _numberController,
            keyboardType: TextInputType.number,
            maxLength: 11,
            decoration: InputDecoration(
              hintText: type == 'bvn' ? 'Enter 11-digit BVN' : 'Enter 11-digit NIN',
              hintStyle: TextStyle(color: colors.textSecondary),
              prefixIcon: Icon(Icons.description_outlined, color: colors.textSecondary),
              border: InputBorder.none,
            ),
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500, letterSpacing: 1),
          ),
        ),
        const SizedBox(height: 40),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isLoading ? null : () => _handleInitiateKyc(type),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Text('Send Verification Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _buildOtp(ThemeColors colors) {
    final type = _selectedType ?? 'bvn';
    final canSubmit = _otpController.text.length == 6 && !_isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: colors.text),
              onPressed: () {
                setState(() {
                  _currentStep = KycFlowStep.initiate;
                });
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
          'Verifying ${type.toUpperCase()}',
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
              onPressed: canSubmit ? _handleVerifyOtp : null,
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
    );
  }

  Widget _buildOptionCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool isVerified,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colors;

    return InkWell(
      onTap: isVerified ? null : onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isVerified ? AppColors.successBg : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isVerified ? colors.success : colors.border,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isVerified ? colors.success : colors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle, style: TextStyle(fontSize: 14, color: colors.textSecondary)),
                ],
              ),
            ),
            Icon(
              isVerified ? Icons.check_circle : Icons.chevron_right,
              color: isVerified ? colors.success : colors.textSecondary,
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
