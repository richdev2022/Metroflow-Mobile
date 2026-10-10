import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../providers/auth_provider.dart';
import '../widgets/biometric_setup_prompt.dart';

/// First-login PERSONAL profile completion (invited team members).
///
/// Product rules implemented here:
///  - Invited users (role != owner/admin) complete a PERSONAL profile:
///    photo, name, email (READ-ONLY) and phone number verified by SMS OTP.
///  - The email field is never editable — it is fixed by the account.
///  - The phone verification CTA sends an OTP and flips the user to
///    verified once the code is confirmed.
///  - "Skip for now" dismisses the prompt server-side; the profile can be
///    finished later from Settings → Profile.
/// Business admins never see this screen — they keep the business profile
/// (registration collects it and Settings → Edit Profile manages it).
class PersonalProfileCompletionScreen extends ConsumerStatefulWidget {
  const PersonalProfileCompletionScreen({super.key});

  @override
  ConsumerState<PersonalProfileCompletionScreen> createState() =>
      _PersonalProfileCompletionScreenState();
}

class _PersonalProfileCompletionScreenState
    extends ConsumerState<PersonalProfileCompletionScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isUploadingAvatar = false;
  bool _otpSent = false;
  bool _isSendingOtp = false;
  bool _isVerifyingOtp = false;
  bool _phoneVerified = false;

  String _email = '';
  String? _avatarUrl;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final response = await ApiService().getMe();
      final me = response.data is Map && response.data['data'] is Map
          ? Map<String, dynamic>.from(response.data['data'] as Map)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _email = (me['email'] ?? '').toString();
        _nameController.text = (me['name'] ?? '').toString();
        _phoneController.text = (me['phoneNumber'] ?? '').toString();
        _phoneVerified = me['phoneVerified'] == true;
        final url = me['avatarUrl']?.toString();
        _avatarUrl =
            (url != null && url.isNotEmpty) ? ApiService.resolveMediaUrl(url) : null;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('ProfileCompletion load failed: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    try {
      final picker = ImagePicker();
      final source = await showModalBottomSheet<ImageSource>(
        context: context,
        builder: (sheetContext) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.gallery),
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(sheetContext).pop(ImageSource.camera),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
      if (source == null || !mounted) return;
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;

      setState(() => _isUploadingAvatar = true);
      final url = await ApiService().uploadProfileAvatar(File(picked.path));
      if (!mounted) return;
      if (url != null && url.isNotEmpty) {
        setState(() => _avatarUrl = url);
        AppToast.show('Profile picture updated', type: AppToastType.success);
      } else {
        AppToast.show('Could not upload picture. Try again.',
            type: AppToastType.error);
      }
    } catch (e) {
      debugPrint('Avatar upload failed: $e');
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _sendPhoneOtp() async {
    final phone = _phoneController.text.trim();
    if (phone.length < 7) {
      AppToast.show('Enter a valid phone number first', type: AppToastType.error);
      return;
    }
    setState(() => _isSendingOtp = true);
    try {
      await ApiService().sendProfilePhoneOtp(phone);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _otpController.clear();
      });
      AppToast.show('Verification code sent to $phone',
          type: AppToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  Future<void> _verifyPhoneOtp() async {
    final otp = _otpController.text.trim();
    if (otp.length < 4) {
      AppToast.show('Enter the 6-digit code we sent you',
          type: AppToastType.error);
      return;
    }
    setState(() => _isVerifyingOtp = true);
    try {
      await ApiService().verifyProfilePhoneOtp(_phoneController.text.trim(), otp);
      if (!mounted) return;
      setState(() {
        _phoneVerified = true;
        _otpSent = false;
      });
      AppToast.show('Phone number verified', type: AppToastType.success);
    } catch (e) {
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isVerifyingOtp = false);
    }
  }

  Future<void> _saveAndContinue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      AppToast.show('Your name is required', type: AppToastType.error);
      return;
    }
    setState(() => _isSaving = true);
    try {
      await ApiService().saveMyProfile(
        name: name,
        phoneNumber: _phoneController.text.trim(),
      );
      // Keep the app shell (greeting/avatar) in sync.
      try {
        await ref.read(authProvider.notifier).getMe(forceRefresh: true);
      } catch (_) {}
      if (!mounted) return;
      AppToast.show('Profile saved', type: AppToastType.success);
      _finish();
    } catch (e) {
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _skipForNow() async {
    setState(() => _isSaving = true);
    try {
      await ApiService().dismissProfilePrompt();
    } catch (_) {
      // Skipping must never trap the user — server failure is non-blocking.
    }
    if (!mounted) return;
    setState(() => _isSaving = false);
    _finish();
  }

  /// Hand control back to the normal post-login flow. The per-account
  /// biometric activation offer is shown HERE (before the dashboard) — the
  /// login screen's prompt only fires on the password-login path, so invited
  /// members finishing their profile never saw it.
  Future<void> _finish() async {
    if (!mounted) return;
    await maybeOfferBiometricSetup(context, ref);
    if (!mounted) return;
    context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Complete your profile',
          style: TextStyle(
            color: colors.text,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Welcome! Set up your personal profile so teammates can recognise you.',
                      style: TextStyle(color: colors.textSecondary, fontSize: 14, height: 1.5),
                    ),
                    const SizedBox(height: 24),

                    // ---- Avatar ----
                    Center(
                      child: GestureDetector(
                        onTap: _isUploadingAvatar ? null : _pickAndUploadAvatar,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 44,
                              backgroundColor: colors.primaryBg,
                              backgroundImage: _avatarUrl != null
                                  ? NetworkImage(_avatarUrl!)
                                  : null,
                              child: _isUploadingAvatar
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2))
                                  : _avatarUrl == null
                                      ? Icon(Icons.person, size: 44, color: colors.primary)
                                      : null,
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: colors.background, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        'Add a profile photo',
                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // ---- Name ----
                    _fieldLabel('Full name', colors),
                    TextField(
                      controller: _nameController,
                      style: TextStyle(color: colors.text),
                      decoration: _inputDecoration('Your name', colors, isDark),
                    ),
                    const SizedBox(height: 16),

                    // ---- Email (READ-ONLY by design) ----
                    _fieldLabel('Email', colors),
                    TextField(
                      controller: TextEditingController(text: _email),
                      enabled: false,
                      style: TextStyle(color: colors.textSecondary),
                      decoration: _inputDecoration(_email, colors, isDark).copyWith(
                        suffixIcon: Icon(Icons.lock_outline,
                            size: 18, color: colors.textSecondary),
                        helperText: 'Email can\'t be changed — it identifies your account',
                        helperStyle: TextStyle(color: colors.textSecondary, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // ---- Phone + verification ----
                    _fieldLabel('Phone number', colors),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            readOnly: _phoneVerified,
                            style: TextStyle(color: colors.text),
                            decoration: _inputDecoration(
                                _phoneVerified ? 'Verified' : '+234 800 000 0000',
                                colors,
                                isDark),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_phoneVerified)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                            decoration: BoxDecoration(
                              color: colors.successBg,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.check_circle, size: 16, color: colors.success),
                                const SizedBox(width: 4),
                                Text('Verified',
                                    style: TextStyle(
                                        color: colors.success,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                              ],
                            ),
                          )
                        else
                          ElevatedButton(
                            onPressed: _isSendingOtp ? null : _sendPhoneOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isSendingOtp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Send OTP',
                                    style: TextStyle(fontSize: 13)),
                          ),
                      ],
                    ),
                    if (_otpSent) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _otpController,
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              style: TextStyle(
                                  color: colors.text,
                                  fontSize: 18,
                                  letterSpacing: 8),
                              decoration:
                                  _inputDecoration('6-digit code', colors, isDark)
                                      .copyWith(counterText: ''),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: _isVerifyingOtp ? null : _verifyPhoneOtp,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                            ),
                            child: _isVerifyingOtp
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Verify',
                                    style: TextStyle(fontSize: 13)),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 28),

                    // ---- Save & continue ----
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _isSaving ? null : _saveAndContinue,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Text('Save & Continue',
                                style: TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 8),

                    // ---- Skip CTA ----
                    TextButton(
                      onPressed: _isSaving ? null : _skipForNow,
                      child: Text(
                        'Skip for now — I\'ll do it later in Settings',
                        style: TextStyle(color: colors.textSecondary, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _fieldLabel(String label, ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label,
          style: TextStyle(
              color: colors.text, fontSize: 13, fontWeight: FontWeight.w600)),
    );
  }

  InputDecoration _inputDecoration(String hint, ThemeColors colors, bool isDark) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.textSecondary),
      filled: true,
      fillColor: isDark ? colors.surface : colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.primary),
      ),
    );
  }
}
