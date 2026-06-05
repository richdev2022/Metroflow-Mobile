import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../models/business_profile.dart';
import '../models/kyc_status.dart';
import '../models/subscription.dart';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../services/api.dart';
import '../services/biometrics.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

const _businessIndustries = [
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

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.title = 'Settings'});

  final String title;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nameController = TextEditingController();
  final _contactController = TextEditingController();
  final _industrySearchController = TextEditingController();
  final _otpController = TextEditingController();

  BusinessProfile? _settings;
  Subscription? _subscription;
  KycStatus? _kycStatus;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _biometricsEnabled = false;
  bool _biometricsAvailable = false;
  bool _hasBiometricHardware = false;
  String _editIndustry = '';
  String _editCurrency = 'NGN';
  String _otpPreference = 'email';
  String? _contactType;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _checkBiometricAvailability();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _contactController.dispose();
    _industrySearchController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometricAvailability() async {
    final hasHardware = await BiometricService.hasHardware();
    final enrolled = await BiometricService.isEnrolled();
    final enabled = await BiometricService.isEnabled();
    if (!mounted) return;
    setState(() {
      _hasBiometricHardware = hasHardware;
      _biometricsAvailable = enrolled;
      _biometricsEnabled = enabled;
    });
  }

  Future<void> _fetchData() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getSettings(),
        api.getCurrentSubscription(),
        api.getKycStatus(),
        api.getOtpPreference(),
      ]);

      final settingsData = results[0].data;
      if (settingsData['success'] == true && settingsData['settings'] != null) {
        final profile = BusinessProfile.fromJson(settingsData['settings'] as Map<String, dynamic>);
        _settings = profile;
        _nameController.text = profile.name;
        _editIndustry = profile.industry;
        _editCurrency = profile.currency.isEmpty ? 'NGN' : profile.currency;
      }

      final subscriptionData = results[1].data;
      if (subscriptionData['success'] == true && subscriptionData['subscription'] != null) {
        _subscription = Subscription.fromJson(subscriptionData['subscription'] as Map<String, dynamic>);
      }

      final kycData = results[2].data;
      if (kycData is Map<String, dynamic>) {
        _kycStatus = KycStatus.fromJson(kycData);
      }

      final otpPrefData = results[3].data;
      if (otpPrefData['success'] == true) {
        _otpPreference = (otpPrefData['preference'] as String?) ?? 'email';
      }
    } catch (e) {
      debugPrint('Failed to fetch settings: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleUpdateProfile() async {
    setState(() => _isSaving = true);
    try {
      await ApiService().updateSettings({
        'name': _nameController.text.trim(),
        'industry': _editIndustry,
        'currency': _editCurrency,
      });
      AppToast.show('Profile updated successfully', type: AppToastType.success);
      if (mounted) Navigator.of(context).pop();
      await _fetchData();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleRequestContactUpdate() async {
    final type = _contactType;
    final value = _contactController.text.trim();
    if (type == null || value.isEmpty) {
      AppToast.show('Please enter a valid ${type ?? 'contact'}', type: AppToastType.error);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ApiService().requestContactUpdateOtp(type, value);
      if (mounted) {
        Navigator.of(context).pop();
        _showOtpModal();
      }
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleVerifyContactUpdate() async {
    if (_otpController.text.trim().length != 6) {
      AppToast.show('Please enter a valid 6-digit OTP', type: AppToastType.error);
      return;
    }

    setState(() => _isSaving = true);
    try {
      await ApiService().verifyContactUpdateOtp(_otpController.text.trim());
      _otpController.clear();
      _contactType = null;
      AppToast.show('Contact updated successfully', type: AppToastType.success);
      if (mounted) Navigator.of(context).pop();
      await _fetchData();
    } catch (e) {
      _showError(e);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _handleUpdateOtpPreference(String preference) async {
    setState(() => _otpPreference = preference);
    try {
      await ApiService().updateOtpPreference(preference);
    } catch (e) {
      _showError(e);
    }
  }

  Future<void> _handleBiometricToggle(bool value) async {
    setState(() => _isSaving = true);
    if (value) {
      final hasHardware = await BiometricService.hasHardware();
      if (!hasHardware) {
        setState(() => _isSaving = false);
        _showInfo(
          'Biometrics Not Available',
          'This device does not support biometric authentication.',
        );
        return;
      }
      final enrolled = await BiometricService.isEnrolled();
      if (!enrolled) {
        setState(() => _isSaving = false);
        _showInfo(
          'Biometrics Not Set Up',
          'Please set up fingerprint or face recognition in your device settings first.',
        );
        return;
      }
      final result = await ref.read(authProvider.notifier).enableBiometricsWithResult();
      if (!result.success) {
        setState(() => _isSaving = false);
        _showError(result.error ?? 'Failed to enable biometric login');
        return;
      }
      setState(() => _biometricsEnabled = true);
      AppToast.show('Biometric login enabled', type: AppToastType.success);
    } else {
      await ref.read(authProvider.notifier).disableBiometrics();
      setState(() => _biometricsEnabled = false);
      AppToast.show('Biometric login disabled');
    }
    await _checkBiometricAvailability();
    if (mounted) setState(() => _isSaving = false);
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) context.go('/login');
    }
  }

  String get _kycTier {
    final status = _kycStatus;
    if (status == null) return 'Tier 0';
    if (status.isTier3Verified) return 'Tier 3';
    if (status.isTier2Verified) return 'Tier 2';
    if (status.isTier1Verified) return 'Tier 1';
    return 'Tier 0';
  }

  String get _kycUpgradeLabel {
    switch (_kycTier) {
      case 'Tier 0':
        return 'Upgrade to Tier 1 (Verify BVN/NIN)';
      case 'Tier 1':
        return 'Upgrade to Tier 2 (Verify both)';
      case 'Tier 2':
        return 'Upgrade to Tier 3 (Business KYC)';
      default:
        return 'Fully Verified';
    }
  }

  String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  void _showError(Object error) {
    AppToast.show(error.toString().replaceAll('Exception: ', ''), type: AppToastType.error);
  }

  void _showInfo(String title, String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final themeMode = ref.watch(themeProvider);
    final isDarkMode = themeMode == ThemeMode.dark;

    if (_isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: const SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: colors.surface,
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colors.text),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _fetchData,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    _profileSection(),
                    _sectionTitle('Verification & KYC'),
                    _kycCard(),
                    _sectionTitle('Business'),
                    _settingItem(
                      icon: Icons.business_outlined,
                      title: 'Business Profile',
                      subtitle: _settings?.industry,
                      onTap: _showEditProfileModal,
                    ),
                    _settingItem(
                      icon: Icons.mail_outline,
                      title: 'Update Email',
                      subtitle: _settings?.email,
                      onTap: () => _showContactModal('email'),
                    ),
                    _settingItem(
                      icon: Icons.call_outlined,
                      title: 'Update Phone',
                      subtitle: _settings?.phoneNumber,
                      onTap: () => _showContactModal('phone'),
                    ),
                    _settingItem(
                      icon: Icons.verified_user_outlined,
                      title: 'KYC Status',
                      subtitle: _titleCase(_kycStatus?.business.status ?? 'none'),
                      onTap: _kycTier == 'Tier 3'
                          ? null
                          : () => context.go(_kycTier == 'Tier 2' ? '/main/business-kyc' : '/kyc-prompt'),
                    ),
                    _sectionTitle('Transaction Security'),
                    _otpPreferenceCard(),
                    _sectionTitle('Subscription'),
                    _settingItem(
                      icon: Icons.credit_card_outlined,
                      title: _subscription?.planName ?? 'Free Plan',
                      subtitle: _subscription?.subscriptionStatus == 'active' ? 'Active' : 'Inactive',
                      onTap: () => context.go('/main/subscription'),
                    ),
                    _sectionTitle('Appearance'),
                    _settingItem(
                      icon: isDarkMode ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                      title: 'Dark Mode',
                      subtitle: 'Currently ${isDarkMode ? 'enabled' : 'disabled'}',
                      trailing: Switch(
                        value: isDarkMode,
                        onChanged: (value) {
                          ref
                              .read(themeProvider.notifier)
                              .toggleTheme(value ? ThemeMode.dark : ThemeMode.light);
                        },
                      ),
                    ),
                    _sectionTitle('Security'),
                    _settingItem(
                      icon: Icons.fingerprint,
                      title: 'Biometric Login',
                      subtitle: !_biometricsAvailable && !_hasBiometricHardware
                          ? 'Not available on this device'
                          : (!_biometricsAvailable
                              ? 'Not enrolled on device'
                              : (_biometricsEnabled ? 'Enabled' : 'Disabled')),
                      trailing: Switch(
                        value: _biometricsEnabled,
                        onChanged: (_isSaving || (!_biometricsAvailable && !_biometricsEnabled))
                            ? null
                            : _handleBiometricToggle,
                      ),
                    ),
                    _settingItem(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: () => context.go('/forgot-password'),
                    ),
                    _sectionTitle('Support'),
                    _settingItem(
                      icon: Icons.help_outline,
                      title: 'Help Center',
                      onTap: () => _showInfo('Coming Soon', 'Help Center will be available soon.'),
                    ),
                    _settingItem(
                      icon: Icons.chat_bubble_outline,
                      title: 'Contact Support',
                      onTap: () => _showInfo('Coming Soon', 'Contact Support will be available soon.'),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                      child: OutlinedButton.icon(
                        onPressed: _handleLogout,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.logout_outlined),
                        label: const Text('Logout'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileSection() {
    final colors = AppTheme.colors;
    final name = _settings?.name ?? 'Business';
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: colors.primary,
            child: Text(
              name.isEmpty ? 'B' : name[0].toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(color: colors.text, fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  _settings?.email ?? '',
                  style: TextStyle(color: colors.textSecondary, fontSize: 14),
                ),
              ],
            ),
          ),
          _roundIconButton(
            icon: Icons.edit,
            onTap: _showEditProfileModal,
          ),
        ],
      ),
    );
  }

  Widget _kycCard() {
    final colors = AppTheme.colors;
    final fullyVerified =
        _kycStatus?.user.bvnStatus == 'verified' && _kycStatus?.user.ninStatus == 'verified';

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.primary,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  _kycTier,
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                fullyVerified ? 'Fully Verified' : 'Verification Pending',
                style: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _kycRow('BVN Status', _kycStatus?.user.bvnStatus ?? 'none'),
          const SizedBox(height: 12),
          _kycRow('NIN Status', _kycStatus?.user.ninStatus ?? 'none'),
          const SizedBox(height: 12),
          _kycRow('Business KYC', _kycStatus?.business.status ?? 'none'),
          if (_kycTier != 'Tier 3') ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => context.go(_kycTier == 'Tier 2' ? '/main/business-kyc' : '/kyc-prompt'),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(_kycUpgradeLabel),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _kycRow(String label, String status) {
    final colors = AppTheme.colors;
    final verified = status == 'verified';
    final statusColor = verified ? AppColors.success : AppColors.warning;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _titleCase(status),
            style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 8),
      child: Text(
        title,
        style: TextStyle(color: colors.text, fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _settingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryBg,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(icon, color: colors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(color: colors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  (onTap == null
                      ? const SizedBox.shrink()
                      : Icon(Icons.chevron_right, color: colors.textSecondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _otpPreferenceCard() {
    final colors = AppTheme.colors;
    return Container(
      margin: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Receive Transaction OTP via:',
            style: TextStyle(color: colors.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Row(
            children: ['email', 'sms', 'both'].map((pref) {
              final selected = _otpPreference == pref;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _handleUpdateOtpPreference(pref),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? colors.primary.withValues(alpha: 0.08) : colors.background,
                        border: Border.all(color: selected ? colors.primary : colors.border),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        pref.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: selected ? colors.primary : colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _roundIconButton({required IconData icon, required VoidCallback onTap}) {
    final colors = AppTheme.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colors.primaryBg,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: colors.primary, size: 20),
      ),
    );
  }

  void _showEditProfileModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _modalShell(
          title: 'Edit Profile',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _fieldLabel('Business Name'),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(hintText: 'Business Name'),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Industry'),
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _showIndustryPicker(onSelected: () => setModalState(() {})),
                child: InputDecorator(
                  decoration: const InputDecoration(),
                  child: Text(
                    _editIndustry.isEmpty ? 'Select Industry' : _editIndustry,
                    style: TextStyle(
                      color: _editIndustry.isEmpty
                          ? AppTheme.colors.textSecondary
                          : AppTheme.colors.text,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _fieldLabel('Currency'),
              Row(
                children: ['NGN', 'USD'].map((currency) {
                  final selected = _editCurrency == currency;
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(currency),
                        selected: selected,
                        onSelected: (_) {
                          setState(() => _editCurrency = currency);
                          setModalState(() {});
                        },
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _handleUpdateProfile,
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Changes'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showContactModal(String type) {
    _contactType = type;
    _contactController.text = type == 'email' ? (_settings?.email ?? '') : (_settings?.phoneNumber ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _modalShell(
        title: 'Update ${type == 'email' ? 'Email' : 'Phone'}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _fieldLabel('New ${type == 'email' ? 'Email Address' : 'Phone Number'}'),
            TextField(
              controller: _contactController,
              decoration: InputDecoration(hintText: type == 'email' ? 'Email Address' : 'Phone Number'),
              keyboardType: type == 'email' ? TextInputType.emailAddress : TextInputType.phone,
              textCapitalization: TextCapitalization.none,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSaving ? null : _handleRequestContactUpdate,
              child: const Text('Send OTP'),
            ),
          ],
        ),
      ),
    );
  }

  void _showOtpModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _modalShell(
        title: 'Verify OTP',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code sent to your new $_contactType',
              style: TextStyle(color: AppTheme.colors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _otpController,
              decoration: const InputDecoration(hintText: 'Enter OTP'),
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isSaving ? null : _handleVerifyContactUpdate,
              child: const Text('Verify & Update'),
            ),
          ],
        ),
      ),
    );
  }

  void _showIndustryPicker({VoidCallback? onSelected}) {
    _industrySearchController.clear();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = _businessIndustries
                .where((industry) => industry.toLowerCase().contains(query.toLowerCase()))
                .toList();
            return _modalShell(
              title: 'Select Industry',
              heightFactor: 0.8,
              child: Column(
                children: [
                  TextField(
                    controller: _industrySearchController,
                    decoration: const InputDecoration(
                      hintText: 'Search industries...',
                      prefixIcon: Icon(Icons.search),
                    ),
                    onChanged: (value) => setModalState(() => query = value),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final industry = filtered[index];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () {
                            setState(() => _editIndustry = industry);
                            onSelected?.call();
                            Navigator.of(context).pop();
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.colors.background,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              industry,
                              style: TextStyle(color: AppTheme.colors.text, fontSize: 16),
                            ),
                          ),
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

  Widget _modalShell({
    required String title,
    required Widget child,
    double? heightFactor,
  }) {
    final colors = AppTheme.colors;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final content = Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: heightFactor == null ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(color: colors.text, fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: Icon(Icons.close, color: colors.text),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(24, 24, 24, bottomInset + 24),
      child: heightFactor == null
          ? content
          : FractionallySizedBox(heightFactor: heightFactor, child: content),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        label,
        style: TextStyle(
          color: AppTheme.colors.text,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
