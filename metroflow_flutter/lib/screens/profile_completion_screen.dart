import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../providers/auth_provider.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/logger.dart';
import '../widgets/biometric_setup_prompt.dart';

/// Shared industry catalogue (mirrors the Settings screen list).
const businessIndustries = <String>[
  'Technology',
  'Healthcare',
  'Finance',
  'Education',
  'Retail',
  'Manufacturing',
  'Agriculture',
  'Energy',
  'Transportation',
  'Telecommunications',
  'Media & Entertainment',
  'Real Estate',
  'Construction',
  'Hospitality',
  'Professional Services',
  'E-commerce',
  'Fintech',
  'Healthtech',
  'Edtech',
  'Logistics',
  'Marketing',
  'Consulting',
  'Legal Services',
  'Accounting',
  'Insurance',
  'Banking',
  'Gaming',
  'Fashion',
  'Food & Beverage',
  'Tourism',
  'Art & Design',
  'Software Development',
  'Cybersecurity',
  'Cloud Computing',
  'Artificial Intelligence',
  'Data Science',
  'Blockchain',
  'Renewable Energy',
  'Environmental Services',
  'Oil & Gas',
  'Restaurants',
  'Hotels',
  'Courier',
  'Delivery',
  'Project Management',
  'Payment Processing',
  'Inventory Management',
  'Human Resources',
  'IT Services',
];

/// ---------------------------------------------------------------------------
/// Profile Completion — SSO onboarding gate.
///
/// Google sign-ups create the workspace with a DERIVED name ("Ada's
/// Workspace"), no industry, no phone number and no logo. The user MUST
/// finish this screen before the dashboard: business name, industry,
/// phone number and logo.
/// ---------------------------------------------------------------------------
class ProfileCompletionScreen extends ConsumerStatefulWidget {
  const ProfileCompletionScreen({super.key});

  @override
  ConsumerState<ProfileCompletionScreen> createState() =>
      _ProfileCompletionScreenState();
}

class _ProfileCompletionScreenState
    extends ConsumerState<ProfileCompletionScreen> {
  final _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _industry;
  String? _logoPath;
  String? _existingLogoUrl;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _prefill() async {
    // GET /settings answers { success, settings: <business>, profile: <user> }.
    // This screen previously read data['data']['business'] — a shape the
    // backend never returns — so the form ALWAYS opened blank ("call get
    // profile to fill existing profile information").
    try {
      final response = await _api.getSettings();
      final data = response.data;
      if (data is Map && data['success'] == true && data['settings'] is Map) {
        final business = data['settings'] as Map;
        if (mounted) {
          setState(() {
            _nameController.text = (business['name'] ?? '').toString();
            final industry = (business['industry'] ?? '').toString();
            _industry = industry.isEmpty ? null : industry;
            _phoneController.text = (business['phone_number'] ??
                    business['phoneNumber'] ??
                    '')
                .toString();
            _existingLogoUrl = (business['logo_url'] ?? business['logoUrl'] ?? '')
                .toString();
            _loaded = true;
          });
        } else if (mounted) {
          setState(() => _loaded = true);
        }
      } else if (mounted) {
        setState(() => _loaded = true);
      }
    } catch (e) {
      Logger.error('Profile completion prefill failed: $e');
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _pickLogo() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (picked == null) return;
      if (!mounted) return;
      setState(() {
        _logoPath = picked.path;
        _existingLogoUrl = null;
      });
    } catch (e) {
      Logger.error('Logo pick failed: $e');
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_industry == null || _industry!.isEmpty) {
      AppToast.show('Please select your industry', type: AppToastType.error);
      return;
    }
    if (_logoPath == null &&
        (_existingLogoUrl == null || _existingLogoUrl!.isEmpty)) {
      AppToast.show('Please upload your business logo', type: AppToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final response = await _api.completeBusinessProfile(
        name: _nameController.text.trim(),
        industry: _industry!.trim(),
        phoneNumber: _phoneController.text.trim(),
        logoPath: _logoPath,
      );
      final data = response.data;
      final ok = data is Map && data['success'] == true;
      if (!mounted) return;
      if (ok) {
        ref.read(authProvider.notifier).markProfileCompleted();
        AppToast.show('Profile completed — welcome aboard!',
            type: AppToastType.success);

        // Seamless continuation: offer the per-account biometric activation
        // right here, then land on the dashboard. (Previously this navigated
        // to /login hoping the login screen would re-prompt — but the login
        // auto-prompt was removed, so users were stranded on the login form.)
        if (!mounted) return;
        await maybeOfferBiometricSetup(context, ref);
        if (!mounted) return;
        context.go('/main');
      } else {
        final error = data is Map
            ? (data['error'] ?? data['message'])?.toString()
            : null;
        AppToast.show(error ?? 'Could not complete profile — try again',
            type: AppToastType.error);
      }
    } catch (e) {
      if (!mounted) return;
      AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// SKIP: dismiss the prompt server-side (never re-nags on the next login)
  /// and go straight to the dashboard. Server failure is non-blocking.
  Future<void> _skipForNow() async {
    setState(() => _saving = true);
    try {
      await ApiService().dismissProfilePrompt();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _saving = false);
    await maybeOfferBiometricSetup(context, ref);
    if (!mounted) return;
    context.go('/main');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text('Complete your profile',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Welcome! Add your business details to finish setting up your workspace. This takes less than a minute.',
                  style: TextStyle(
                      fontSize: 13.5, height: 1.5, color: colors.textSecondary),
                ),
                const SizedBox(height: 24),
                Center(
                  child: GestureDetector(
                    onTap: _saving ? null : _pickLogo,
                    child: Container(
                      width: 104,
                      height: 104,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        shape: BoxShape.circle,
                        border: Border.all(color: colors.border, width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _logoPath != null
                          ? Image.file(File(_logoPath!), fit: BoxFit.cover)
                          : (_existingLogoUrl != null && _existingLogoUrl!.isNotEmpty
                              ? Image.network(_existingLogoUrl!, fit: BoxFit.cover)
                              : Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.add_a_photo_rounded,
                                        color: colors.primary, size: 30),
                                    const SizedBox(height: 6),
                                    Text('Logo',
                                        style: TextStyle(
                                            fontSize: 11.5,
                                            color: colors.textSecondary)),
                                  ],
                                )),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    'Business logo *',
                    style:
                        TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
                const SizedBox(height: 20),
                _label('Business name *', colors),
                TextFormField(
                  controller: _nameController,
                  enabled: _loaded,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Business name is required' : null,
                  decoration: _inputDecoration(
                      'e.g. Acme Enterprises Ltd', colors),
                ),
                const SizedBox(height: 16),
                _label('Industry *', colors),
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _saving ? null : _pickIndustry,
                  child: InputDecorator(
                    decoration: _inputDecoration('Select industry', colors),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _industry ?? 'Select industry',
                            style: TextStyle(
                              fontSize: 15,
                              color: _industry == null
                                  ? colors.textSecondary
                                  : colors.text,
                            ),
                          ),
                        ),
                        Icon(Icons.expand_more_rounded,
                            color: colors.textSecondary, size: 22),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                _label('Phone number *', colors),
                TextFormField(
                  controller: _phoneController,
                  enabled: _loaded,
                  keyboardType: TextInputType.phone,
                  validator: (v) => (v == null || v.trim().length < 7)
                      ? 'Enter a valid phone number'
                      : null,
                  decoration: _inputDecoration('e.g. 08012345678', colors),
                ),
                const SizedBox(height: 12),
                // SKIP: finishing the business profile must never trap the
                // user — the profile can be completed later from Settings.
                TextButton(
                  onPressed: _saving ? null : _skipForNow,
                  child: Text(
                    'Skip for now — I\'ll do it later in Settings',
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.4, color: Colors.white))
                        : const Text('Save & Continue',
                            style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text,
          style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: colors.textSecondary)),
    );
  }

  InputDecoration _inputDecoration(String hint, ThemeColors colors) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: colors.textSecondary, fontSize: 14.5),
      filled: true,
      fillColor: colors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: colors.border),
      ),
    );
  }

  Future<void> _pickIndustry() async {
    final colors = AppTheme.colors;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        var query = '';
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final filtered = businessIndustries
                .where((i) => i.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.75,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      autofocus: false,
                      decoration: const InputDecoration(
                        hintText: 'Search industries...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (v) => setSheetState(() => query = v),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (sheetContext, index) {
                        final industry = filtered[index];
                        return ListTile(
                          title: Text(industry),
                          trailing: industry == _industry
                              ? const Icon(Icons.check_rounded,
                                  color: AppColors.primary)
                              : null,
                          onTap: () {
                            setState(() => _industry = industry);
                            Navigator.pop(sheetContext);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
