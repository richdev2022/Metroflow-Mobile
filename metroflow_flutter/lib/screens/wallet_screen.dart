import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../theme/app_theme.dart';
import '../services/api.dart';
import '../widgets/pin_setup_sheet.dart';
import '../widgets/single_transfer_sheet.dart';
import '../widgets/transaction_limits_card.dart';

class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  bool isKycLoading = true;
  bool isVirtualAccountLoading = false;
  Map<String, dynamic> kycStatus = {'ninVerified': false, 'bvnVerified': false};
  Map<String, dynamic> wallets = {};
  /// Invited members must never see the business wallet — only owner/admin
  /// roles get the business wallet card (mirrors the backend flag).
  bool canManageBusinessWallet = false;
  String selectedAccountType = 'Personal';

  bool showVirtualAccountModal = false;

  /// Transfer modal host: the form itself lives in the shared
  /// [SingleTransferSheet] (also hosted by /main/single-transfer).
  bool showTransferModal = false;
  String _transferWalletType = 'user';

  /// Transaction PIN status (GET /settings/otp-enabled → pinCreated).
  /// null = still checking / check failed. When false the transfer action
  /// opens the PIN setup sheet instead of the transfer modal.
  bool? _pinCreated;
  bool _pinSheetShown = false;

  @override
  void initState() {
    super.initState();
    checkKycStatus();
    // PIN status gate: auto-prompt the setup sheet once per session when no
    // PIN exists yet (guarded so a dismissal never loops).
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePinSetup());
  }

  /// Checks GET /settings/otp-enabled; when `pinCreated == false` shows the
  /// PIN setup bottom sheet (once — [showPinSetupSheet] results are never
  /// re-prompted from here).
  Future<void> _ensurePinSetup() async {
    if (_pinSheetShown) return;
    _pinSheetShown = true;
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      final pinCreated = data is Map && data['pinCreated'] == true;
      if (!mounted) return;
      setState(() => _pinCreated = pinCreated);
      if (!pinCreated) {
        await showPinSetupSheet(context);
      }
    } catch (e) {
      debugPrint('PIN status check failed: $e');
      // Check failed — leave _pinCreated null so the transfer action is not
      // blocked by an inconclusive gate.
    }
  }

  /// Transfer action from a wallet card: gate on the PIN status first.
  void _openTransferFlow(String walletType) {
    if (_pinCreated == false) {
      showPinSetupSheet(context);
      return;
    }
    setState(() {
      _transferWalletType = walletType;
      showTransferModal = true;
    });
  }

  Future<void> checkKycStatus([bool showLoader = true]) async {
    if (showLoader) setState(() => isKycLoading = true);
    try {
      final api = ApiService();
      final response = await api.getKycStatus();
      final data = response.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>?;
      final business = data['business'] as Map<String, dynamic>?;
      final ninVerified = user?['ninStatus'] == 'verified' ||
          user?['nin_status'] == 'verified' ||
          data['nin_verified'] == true;
      final bvnVerified = user?['bvnStatus'] == 'verified' ||
          user?['bvn_status'] == 'verified' ||
          data['bvn_verified'] == true;
      final businessVerified = business?['status'] == 'verified' ||
          data['business_kyc_status'] == 'verified';
      setState(() {
        kycStatus = {
          'ninVerified': ninVerified,
          'bvnVerified': bvnVerified,
          'businessVerified': businessVerified
        };
      });
      if (ninVerified && bvnVerified) {
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Failed to fetch KYC status: $e');
    } finally {
      if (mounted) {
        setState(() {
          isKycLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Future<void> fetchWalletData() async {
    try {
      final api = ApiService();
      final response = await api.getWallet();
      if (mounted) {
        setState(() {
          wallets = response.data ?? {};
          canManageBusinessWallet = response.data?['canManageBusinessWallet'] == true;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet data: $e');
    }
  }

  Future<void> handleCreateVirtualAccount() async {
    setState(() => isVirtualAccountLoading = true);
    try {
      final api = ApiService();
      await api.createVirtualAccount(selectedAccountType);
      if (mounted) {
        setState(() => showVirtualAccountModal = false);
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Failed to create virtual account: $e');
    } finally {
      if (mounted) {
        setState(() => isVirtualAccountLoading = false);
      }
    }
  }

  String _formatCurrency(dynamic wallet) {
    if (wallet == null) return '₦0.00';
    final currency = (wallet['currency']?.toString() ?? 'NGN').toUpperCase();
    final balance = double.tryParse(wallet['balance']?.toString() ?? '0') ?? 0.0;
    switch (currency) {
      case 'USD':
        return '\$${balance.toStringAsFixed(2)}';
      case 'EUR':
        return '€${balance.toStringAsFixed(2)}';
      case 'GBP':
        return '£${balance.toStringAsFixed(2)}';
      default:
        return '₦${balance.toStringAsFixed(2)}';
    }
  }

  Widget _buildWalletCard(dynamic wallet, String label, String walletType) {
    final hasWallet = wallet != null;
    final virtualAccounts = (wallet?['virtual_accounts'] as List?) ?? [];
    final hasVirtualAccounts = virtualAccounts.isNotEmpty;
    final colors = AppTheme.colors;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: colors.textSecondary, fontWeight: FontWeight.w500)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.primaryBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasWallet ? 'Active' : 'Inactive',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _formatCurrency(wallet),
            style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: colors.text),
          ),
          if (hasVirtualAccounts) ...[
            const SizedBox(height: 24),
            ...virtualAccounts.map((account) {
                      final isActive = account['is_active'] == true;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isActive
                              ? colors.surfaceVariant
                              : colors.errorBg.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isActive ? colors.border : colors.error,
                            width: 1,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Account Number:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                Text(
                                  account['virtual_account_number'] ?? '',
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Bank:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                Text(
                                  _getBankName(account),
                                  style: TextStyle(
                                    color: colors.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                            if (account['account_name'] != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Account Name:', style: TextStyle(color: colors.textSecondary, fontSize: 12, fontWeight: FontWeight.w500)),
                                  Expanded(
                                    child: Text(
                                      account['account_name'] ?? '',
                                      style: TextStyle(
                                        color: colors.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      textAlign: TextAlign.right,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            if (!isActive)
                              Row(
                                children: [
                                  Icon(Icons.warning, color: colors.error, size: 16),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Do not use this account. It is currently inactive.',
                                      style: TextStyle(
                                        color: colors.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            if (isActive)
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: colors.success, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Active - Use this account',
                                    style: TextStyle(
                                      color: colors.success,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      );
                    }),
          ],
          const SizedBox(height: 20),
          if (hasWallet)
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: hasVirtualAccounts ? () => context.go('/main/fund-wallet', extra: {'walletType': walletType}) : null,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Fund Wallet', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: hasVirtualAccounts ? () => _openTransferFlow(walletType) : null,
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Transfer', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(color: colors.primary),
                      foregroundColor: colors.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  String _getBankName(dynamic account) {
    // Backend-resolved bank name (from provider metadata or bank-code lookup)
    final resolvedName = account['bank_name'];
    if (resolvedName != null && resolvedName.toString().trim().isNotEmpty) {
      return resolvedName.toString();
    }
    // Try to get bank name from provider metadata if available
    final provider = account['payment_provider'];
    final providerMetadata = account['provider_metadata'];
    if (provider == 'monnify' && providerMetadata is Map) {
      final responseBody = providerMetadata['responseBody'];
      if (responseBody is Map) {
        final accounts = responseBody['accounts'] as List?;
        if (accounts != null && accounts.isNotEmpty) {
          final firstAccount = accounts.first as Map;
          return firstAccount['bankName'] ?? 'Bank Transfer';
        }
      }
    }
    // Flutterwave stores the full VA response in metadata (data.bank_name)
    if (provider == 'flutterwave' && providerMetadata is Map) {
      final data = providerMetadata['data'];
      if (data is Map && data['bank_name'] != null) {
        return data['bank_name'].toString();
      }
    }
    // Default to bank code or a neutral label (provider names are never shown).
    final bankCode = account['bank_code'];
    if (bankCode == '058') return 'GTBank';
    if (bankCode == '035') return 'Wema Bank';
    if (bankCode == '232') return 'Sterling Bank';
    return 'Bank Transfer';
  }

  Widget _buildQuickAction(IconData icon, String label, VoidCallback onTap) {
    final colors = AppTheme.colors;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: colors.primary),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600, fontSize: 12),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildVirtualAccountModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.5,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Create Virtual Account', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showVirtualAccountModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Select the type of virtual account to create.',
                                style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5)),
                            const SizedBox(height: 24),
                            _buildAccountTypeOption('Personal', 'Personal Wallet', colors),
                            if (canManageBusinessWallet) ...[
                              const SizedBox(height: 12),
                              _buildAccountTypeOption('Business', 'Business Wallet', colors),
                            ],
                            const SizedBox(height: 32),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isVirtualAccountLoading ? null : handleCreateVirtualAccount,
                                child: isVirtualAccountLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Create Virtual Account'),
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
          },
        ),
      ],
    );
  }

  Widget _buildAccountTypeOption(String type, String label, ThemeColors colors) {
    final isSelected = selectedAccountType == type;
    return GestureDetector(
      onTap: () => setState(() => selectedAccountType = type),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary.withValues(alpha: 0.1) : colors.surface,
          border: Border.all(
            color: isSelected ? colors.primary : colors.border,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? colors.primary : colors.textSecondary,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (isKycLoading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
        ),
      );
    }

    if (!kycStatus['ninVerified'] || !kycStatus['bvnVerified']) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(color: colors.surface),
                child: const SizedBox.shrink(),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: Icon(Icons.lock, size: 64, color: colors.primary),
                      ),
                      const SizedBox(height: 24),
                      Text('KYC Verification Required',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      Text(
                          'To access your wallet and perform transactions, you need to verify both your NIN and BVN.',
                          style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.border),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(
                                  kycStatus['bvnVerified'] ? Icons.check_circle : Icons.warning,
                                  size: 20,
                                  color: kycStatus['bvnVerified'] ? AppColors.success : AppColors.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'BVN ${kycStatus['bvnVerified'] ? 'Verified' : 'Not Verified'}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colors.text),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Icon(
                                  kycStatus['ninVerified'] ? Icons.check_circle : Icons.warning,
                                  size: 20,
                                  color: kycStatus['ninVerified'] ? AppColors.success : AppColors.error,
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  'NIN ${kycStatus['ninVerified'] ? 'Verified' : 'Not Verified'}',
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: colors.text),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(color: colors.primary.withValues(alpha: 0.3), offset: const Offset(0, 4), blurRadius: 8),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(colors: [colors.primary, colors.primaryLight], begin: Alignment.topLeft, end: Alignment.bottomRight),
                            ),
                            child: TextButton(
                              onPressed: () => context.go('/kyc-prompt'),
                              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                              child: const Text('Complete KYC Now',
                                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                            ),
                          ),
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

    return Scaffold(
      body: Stack(
        children: [
          SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => isRefreshing = true);
                await checkKycStatus(false);
              },
              color: colors.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(color: colors.surface),
                      child: const SizedBox.shrink(),
                    ),
                    _buildWalletCard(wallets['user_wallet'], 'Personal Wallet', 'user'),
                    if (canManageBusinessWallet)
                      _buildWalletCard(wallets['business_wallet'], 'Business Wallet', 'business'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(Icons.credit_card, 'Create Virtual Account',
                                () => setState(() => showVirtualAccountModal = true)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(Icons.swap_horiz, 'View Transfers',
                              () => context.push('/main/transfers')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildQuickAction(Icons.people_alt_rounded, 'Beneficiaries',
                              () => context.push('/main/beneficiaries')),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildQuickAction(Icons.receipt_long_rounded, 'Fees & Pricing',
                              () => context.push('/main/fees')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Web-parity inflow/outflow transaction limits card —
                    // the tier's funding + transfer limits with live daily
                    // head-room (same panel as the web wallet page).
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16),
                      child: TransactionLimitsCard(),
                    ),
                    const SizedBox(height: 16),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
          if (showTransferModal)
            SingleTransferSheet(
              initialWalletType: _transferWalletType,
              onClosed: () => setState(() => showTransferModal = false),
              onSuccess: () {
                setState(() => showTransferModal = false);
                fetchWalletData();
              },
            ),
          if (showVirtualAccountModal) _buildVirtualAccountModal(colors),
        ],
      ),
    );
  }
}
