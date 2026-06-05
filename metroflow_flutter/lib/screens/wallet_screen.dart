import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';
import 'package:metroflow_flutter/services/api.dart';
import 'package:metroflow_flutter/models/bank.dart';


class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool isLoading = true;
  bool isRefreshing = false;
  bool isKycLoading = true;
  bool isTransferLoading = false;
  bool isOtpLoading = false;
  bool isBusinessLoading = false;
  bool isVirtualAccountLoading = false;
  Map<String, dynamic> kycStatus = {'ninVerified': false, 'bvnVerified': false};
  Map<String, dynamic> wallets = {};
  List<Bank> banks = [];
  String bankSearchQuery = '';
  String selectedWalletType = 'user';
  String selectedBankCode = '';
  String accountNumber = '';
  String accountName = '';
  String amount = '';
  String remark = '';
  String otpCode = '';
  String businessAccountNumber = '';
  String businessName = '';

  bool showTransferModal = false;
  bool showOtpModal = false;
  bool showVirtualAccountModal = false;
  bool showBankSearchModal = false;
  bool showBusinessModal = false;

  @override
  void initState() {
    super.initState();
    checkKycStatus();
    fetchBanks();
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
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet data: $e');
    }
  }

  Future<void> fetchBanks() async {
    try {
      final api = ApiService();
      final response = await api.getBanks();
      if (response.data['success'] == true && mounted) {
        setState(() {
          banks = (response.data['data'] as List<dynamic>?)
                  ?.map((e) => Bank.fromJson(e as Map<String, dynamic>))
                  .toList() ??
              [];
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch banks: $e');
    }
  }

  Future<void> handleCreateVirtualAccount() async {
    setState(() => isVirtualAccountLoading = true);
    try {
      final api = ApiService();
      await api.createVirtualAccount();
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

  Future<void> handleResolveAccount() async {
    if (selectedBankCode.isEmpty || accountNumber.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select bank and enter account number')),
        );
      }
      return;
    }
    setState(() => isTransferLoading = true);
    try {
      final api = ApiService();
      final response = await api.resolveAccount(selectedBankCode, accountNumber);
      if (response.data['success'] == true && mounted) {
        setState(() {
          accountName = response.data['data']['account_name'];
        });
      }
    } catch (e) {
      debugPrint('Failed to resolve account: $e');
    } finally {
      if (mounted) {
        setState(() => isTransferLoading = false);
      }
    }
  }

  Future<void> handleRequestOtp() async {
    final wallet = selectedWalletType == 'user' ? wallets['user_wallet'] : wallets['business_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    setState(() => isOtpLoading = true);
    try {
      final api = ApiService();
      await api.requestTransferOtp(walletId: wallet['id']);
      if (mounted) {
        setState(() => showOtpModal = true);
      }
    } catch (e) {
      debugPrint('Failed to send OTP: $e');
    } finally {
      if (mounted) {
        setState(() => isOtpLoading = false);
      }
    }
  }

  Future<void> handleInitiateTransfer() async {
    final wallet = selectedWalletType == 'user' ? wallets['user_wallet'] : wallets['business_wallet'];
    if (wallet == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wallet not found')),
        );
      }
      return;
    }

    if (amount.isEmpty || otpCode.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill all fields')),
        );
      }
      return;
    }

    setState(() => isOtpLoading = true);
    try {
      final api = ApiService();
      await api.singleTransfer({
        'bank_code': selectedBankCode,
        'account_number': accountNumber,
        'account_name': accountName,
        'amount': double.tryParse(amount) ?? 0,
        'remark': remark,
        'otp': otpCode,
        'wallet_id': wallet['id'],
      });
      if (mounted) {
        setState(() {
          showTransferModal = false;
          showOtpModal = false;
          selectedBankCode = '';
          accountNumber = '';
          accountName = '';
          amount = '';
          remark = '';
          otpCode = '';
        });
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Transfer failed: $e');
    } finally {
      if (mounted) {
        setState(() => isOtpLoading = false);
      }
    }
  }

  void openTransferModal(String walletType) {
    setState(() {
      selectedWalletType = walletType;
      selectedBankCode = '';
      accountNumber = '';
      accountName = '';
      amount = '';
      remark = '';
      otpCode = '';
      showTransferModal = true;
    });
  }

  Future<void> handleCreateBusinessAccount() async {
    setState(() => isBusinessLoading = true);
    try {
      final businessVerified = kycStatus['businessVerified'] ?? false;
      if (!businessVerified) {
        if (mounted) context.go('/main/business-kyc');
        return;
      }
      if (mounted) {
        setState(() => showBusinessModal = true);
      }
    } catch (e) {
      debugPrint('Failed to check KYC status: $e');
    } finally {
      if (mounted) {
        setState(() => isBusinessLoading = false);
      }
    }
  }

  Future<void> handleSubmitBusinessAccount() async {
    if (businessAccountNumber.isEmpty || businessName.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill in all fields')),
        );
      }
      return;
    }

    setState(() => isBusinessLoading = true);
    try {
      final api = ApiService();
      await api.createBusinessWallet(businessAccountNumber, businessName);
      if (mounted) {
        setState(() {
          showBusinessModal = false;
          businessAccountNumber = '';
          businessName = '';
        });
        await fetchWalletData();
      }
    } catch (e) {
      debugPrint('Failed to create business account: $e');
    } finally {
      if (mounted) {
        setState(() => isBusinessLoading = false);
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
    final hasVirtualAccount = wallet != null && wallet['virtual_account_number'] != null;
    final isBusinessWallet = walletType == 'business';
    final businessVerified = kycStatus['businessVerified'] ?? false;
    final colors = AppTheme.colors;

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, colors.primaryLight],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: colors.primaryLight)),
              const SizedBox(height: 8),
              Text(
                _formatCurrency(wallet),
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              if (hasVirtualAccount) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Account Number:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(wallet['virtual_account_number'],
                              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Bank:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(wallet['bank_name'] ?? 'Squad (GTBank)',
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      if (wallet['account_name'] != null) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Account Name:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            Expanded(
                              child: Text(
                                wallet['account_name'],
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                                textAlign: TextAlign.right,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              if (hasVirtualAccount || !isBusinessWallet)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextButton(
                          onPressed: hasVirtualAccount ? () => context.go('/main/fund-wallet', extra: {'walletType': walletType}) : null,
                          child: const Text('Fund Wallet', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TextButton(
                          onPressed: hasVirtualAccount ? () => openTransferModal(walletType) : null,
                          child: const Text('Transfer', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        if (isBusinessWallet && !hasVirtualAccount)
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [colors.primary, colors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.lock, size: 32, color: Colors.white),
                  const SizedBox(height: 8),
                  const Text('Business Account Locked',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                  if (!businessVerified)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TextButton(
                        onPressed: () => context.go('/main/business-kyc'),
                        child: const Text('Submit Proof of Address',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
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

  Widget _buildTransferModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
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
                        Text('Send Money', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showTransferModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField('Select Bank', GestureDetector(
                              onTap: () => setState(() => showBankSearchModal = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  border: Border.all(color: colors.border),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      banks.firstWhere((b) => b.code == selectedBankCode, orElse: () => Bank(code: '', name: 'Select a bank')).name,
                                      style: TextStyle(color: selectedBankCode.isEmpty ? colors.textSecondary : colors.text, fontSize: 16),
                                    ),
                                    Icon(Icons.expand_more, color: colors.textSecondary),
                                  ],
                                ),
                              ),
                            )),
                            const SizedBox(height: 20),
                            _buildField('Account Number', Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    decoration: InputDecoration(
                                      hintText: 'Enter account number',
                                      hintStyle: TextStyle(color: colors.textSecondary),
                                    ),
                                    style: TextStyle(color: colors.text, fontSize: 16),
                                    keyboardType: TextInputType.number,
                                    onChanged: (value) => setState(() => accountNumber = value),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(color: colors.primary, borderRadius: BorderRadius.circular(12)),
                                  child: TextButton(
                                    onPressed: isTransferLoading ? null : handleResolveAccount,
                                    child: isTransferLoading
                                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                        : const Text('Verify', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                                  ),
                                ),
                              ],
                            )),
                            if (accountName.isNotEmpty) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle, size: 20, color: AppColors.success),
                                    const SizedBox(width: 8),
                                    Text(accountName, style: const TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 14)),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            _buildField('Amount', TextField(
                              decoration: InputDecoration(hintText: 'Enter amount', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              keyboardType: TextInputType.number,
                              onChanged: (value) => setState(() => amount = value),
                            )),
                            const SizedBox(height: 20),
                            _buildField('Remark (Optional)', TextField(
                              decoration: InputDecoration(hintText: 'Add a remark', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              onChanged: (value) => setState(() => remark = value),
                            )),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (isOtpLoading || accountName.isEmpty) ? null : handleRequestOtp,
                                child: isOtpLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Send OTP'),
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

  Widget _buildOtpModal(ThemeColors colors) {
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
                        Text('Enter OTP', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(icon: Icon(Icons.close, color: colors.text), onPressed: () => setState(() => showOtpModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField('OTP Code', TextField(
                              decoration: InputDecoration(hintText: 'Enter OTP', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              keyboardType: TextInputType.number,
                              maxLength: 6,
                              onChanged: (value) => setState(() => otpCode = value),
                            )),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isOtpLoading ? null : handleInitiateTransfer,
                                child: isOtpLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Confirm Transfer'),
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

  Widget _buildVirtualAccountModal(ThemeColors colors) {
    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.7,
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
                            Text('Create a virtual account to receive payments directly into your wallet.',
                                style: TextStyle(fontSize: 16, color: colors.textSecondary, height: 1.5)),
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

  Widget _buildBankSearchModal(ThemeColors colors) {
    final filteredBanks = banks
        .where((b) => b.name.toLowerCase().contains(bankSearchQuery.toLowerCase()))
        .toList();

    return Stack(
      children: [
        ModalBarrier(
          color: Colors.black.withValues(alpha: 0.5),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.8,
          minChildSize: 0.6,
          maxChildSize: 0.95,
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
                        Text('Select Bank', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () {
                            setState(() {
                              showBankSearchModal = false;
                              bankSearchQuery = '';
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: colors.surfaceVariant,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.search, color: colors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Search bank name...',
                                hintStyle: TextStyle(color: colors.textSecondary),
                              ),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              onChanged: (value) => setState(() => bankSearchQuery = value),
                              autofocus: true,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: ListView.builder(
                        controller: scrollController,
                        itemCount: filteredBanks.length,
                        itemBuilder: (context, index) {
                          final bank = filteredBanks[index];
                          final isSelected = selectedBankCode == bank.code;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedBankCode = bank.code;
                                showBankSearchModal = false;
                                bankSearchQuery = '';
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: colors.border))),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(bank.name, style: TextStyle(fontSize: 16, color: colors.text)),
                                  if (isSelected) Icon(Icons.check_circle, color: colors.primary, size: 20),
                                ],
                              ),
                            ),
                          );
                        },
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

  Widget _buildBusinessModal(ThemeColors colors) {
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
                        Text('Create Business Virtual Account',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text)),
                        IconButton(
                            icon: Icon(Icons.close, color: colors.text),
                            onPressed: () => setState(() => showBusinessModal = false)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Expanded(
                      child: SingleChildScrollView(
                        controller: scrollController,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildField('GTBank Account Number', TextField(
                              decoration: InputDecoration(hintText: 'Enter your GTBank account number', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              keyboardType: TextInputType.number,
                              onChanged: (value) => setState(() => businessAccountNumber = value),
                            )),
                            const SizedBox(height: 20),
                            _buildField('Business Name', TextField(
                              decoration: InputDecoration(hintText: 'Enter your business name', hintStyle: TextStyle(color: colors.textSecondary)),
                              style: TextStyle(color: colors.text, fontSize: 16),
                              onChanged: (value) => setState(() => businessName = value),
                            )),
                            const SizedBox(height: 24),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: isBusinessLoading ? null : handleSubmitBusinessAccount,
                                child: isBusinessLoading
                                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Create Business Account'),
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

  Widget _buildField(String label, Widget child) {
    final colors = AppTheme.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.text)),
        const SizedBox(height: 8),
        child,
      ],
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
                            child: _buildQuickAction(Icons.swap_horiz, 'View Transfers', () => context.go('/main/transfers')),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surface,
                          border: Border.all(color: colors.primary, width: 2, style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextButton.icon(
                          onPressed: handleCreateBusinessAccount,
                          icon: Icon(Icons.business, color: colors.primary),
                          label: const Text('Complete KYC to Create Business Virtual Account',
                                  style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                                  textAlign: TextAlign.center),
                        ),
                      ),
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
          ),
          if (showTransferModal) _buildTransferModal(colors),
          if (showOtpModal) _buildOtpModal(colors),
          if (showVirtualAccountModal) _buildVirtualAccountModal(colors),
          if (showBankSearchModal) _buildBankSearchModal(colors),
          if (showBusinessModal) _buildBusinessModal(colors),
        ],
      ),
    );
  }
}
