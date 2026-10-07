import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../main.dart';
import '../services/api.dart';
import '../models/wallet.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';
import '../utils/payment_launcher.dart';

class FundWalletScreen extends ConsumerStatefulWidget {
  final String walletType;
  const FundWalletScreen({super.key, required this.walletType});

  @override
  ConsumerState<FundWalletScreen> createState() => _FundWalletScreenState();
}

class _FundWalletScreenState extends ConsumerState<FundWalletScreen> {
  final _amountController = TextEditingController();
  bool _isLoading = false;
  Wallet? _selectedWallet;
  String _method = 'card';

  // BOTH wallets are loaded so the user can switch which one they fund
  // BEFORE entering an amount (web parity). Defaults to the walletType this
  // screen was opened with.
  Wallet? _userWallet;
  Wallet? _businessWallet;
  late String _walletType = widget.walletType == 'business' ? 'business' : 'user';

  @override
  void initState() {
    super.initState();
    _fetchWalletInfo();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _fetchWalletInfo() async {
    try {
      final api = ApiService();
      final response = await api.getWallet();
      if (response.statusCode == 200) {
        final data = response.data;
        if (!mounted) return;
        setState(() {
          // GET /wallet returns { user_wallet, business_wallet } (snake_case).
          if (data['user_wallet'] != null) {
            _userWallet = Wallet.fromJson(data['user_wallet'] as Map<String, dynamic>);
          }
          if (data['business_wallet'] != null) {
            _businessWallet = Wallet.fromJson(data['business_wallet'] as Map<String, dynamic>);
          }
          // Keep the requested wallet when it exists; otherwise fall back to
          // whichever wallet the backend actually returned.
          final preferred = _walletType == 'business' ? _businessWallet : _userWallet;
          _selectedWallet = preferred ?? _userWallet ?? _businessWallet;
          if (_selectedWallet != null) {
            _walletType = (_selectedWallet == _businessWallet) ? 'business' : 'user';
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet info: $e');
    }
  }

  void _switchWallet(String type) {
    final wallet = type == 'business' ? _businessWallet : _userWallet;
    if (wallet == null) return;
    setState(() {
      _walletType = type;
      _selectedWallet = wallet;
    });
  }

  Future<void> _handleContinue() async {
    final amountText = _amountController.text;
    if (amountText.isEmpty || double.tryParse(amountText) == null || double.parse(amountText) <= 0) {
      AppToast.show('Please enter a valid amount', type: AppToastType.warning);
      return;
    }

    // Neither wallet is loaded (offline / API failure) — nothing to fund.
    if (_selectedWallet == null) {
      AppToast.show('Wallet not loaded — please try again', type: AppToastType.warning);
      return;
    }

    if (_method == 'bank') {
      _showBankInfo();
      return;
    }

    setState(() => _isLoading = true);
    try {
      // The backend resolves the active payment provider itself — no
      // `provider` field is sent. redirect_url points at the web app's
      // payment callback (web parity); mobile verifies via the reference API.
      final api = ApiService();
      final response = await api.fundWallet(
        double.parse(amountText),
        _selectedWallet!.id,
        redirectUrl: '$webAppOrigin/payment/callback',
      );
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['payment_url'] != null) {
          final reference = data['reference'] as String?;
          if (kIsWeb) {
            final paymentUrl = data['payment_url'] as String;
            await openExternalPaymentUrl(paymentUrl);
            _showWebPaymentPrompt(paymentUrl, reference);
            return;
          }
          if (mounted) {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (ctx) => _FundWalletWebView(
                  url: data['payment_url'],
                  reference: reference,
                  onComplete: () {
                    if (mounted) context.go('/main');
                  },
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Fund wallet error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showWebPaymentPrompt(String url, String? reference) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Complete Card Payment'),
        content: SelectableText(
          'Open this payment link in your browser, complete the payment, then tap Verify Payment.\n\n$url',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Clipboard.setData(ClipboardData(text: url));
              AppToast.show('Payment link copied', type: AppToastType.success);
            },
            child: const Text('Copy Link'),
          ),
          ElevatedButton(
            onPressed: reference == null
                ? null
                : () async {
                    Navigator.of(dialogContext).pop();
                    await _verifyCardPayment(reference);
                  },
            child: const Text('Verify Payment'),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyCardPayment(String reference) async {
    setState(() => _isLoading = true);
    try {
      final response = await ApiService().verifyWalletPayment(reference, suppressToast: true);
      if (_isWalletVerificationSuccessful(response)) {
        AppToast.show(_walletVerificationMessage(response), type: AppToastType.success);
        if (mounted) context.go('/main');
      } else {
        AppToast.show(_walletVerificationMessage(response, fallback: 'Payment verification pending'));
      }
    } catch (e) {
      if (_isAlreadyVerifiedError(e)) {
        AppToast.show('Wallet funded successfully', type: AppToastType.success);
        if (mounted) context.go('/main');
      } else {
        AppToast.show('Payment verification pending. Please refresh your wallet balance.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showBankInfo() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _BankInfoModal(
        wallet: _selectedWallet,
        onClose: () => Navigator.pop(ctx),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencySymbol = (_selectedWallet?.currency ?? 'NGN').toUpperCase() == 'USD'
        ? '\u0024'
        : '\u20A6';
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              Text(
                'Choose how you want to fund your $_walletType wallet',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              _buildWalletSwitcher(),
              const SizedBox(height: 16),
              _buildMethodCard(
                icon: Icons.credit_card_outlined,
                title: 'Card Payment',
                subtitle: 'Instant funding via Debit/Credit Card',
                isActive: _method == 'card',
                onTap: () => setState(() => _method = 'card'),
              ),
              const SizedBox(height: 16),
              _buildMethodCard(
                icon: Icons.account_balance_outlined,
                title: 'Bank Transfer',
                subtitle: 'Transfer to your virtual account',
                isActive: _method == 'bank',
                onTap: () => setState(() => _method = 'bank'),
              ),
              const SizedBox(height: 40),
              const Text('Amount to Fund', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppTheme.colors.border),
                  borderRadius: BorderRadius.circular(16),
                  color: AppTheme.colors.surface,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(currencySymbol,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _amountController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          hintText: '0.00',
                          border: InputBorder.none,
                        ),
                        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                children: ['5000', '10000', '20000', '50000'].map((val) {
                  final isActive = _amountController.text == val;
                  return GestureDetector(
                    onTap: () => _amountController.text = val,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppTheme.colors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isActive ? AppColors.primary : AppTheme.colors.border),
                      ),
                      child: Text(
                        '$currencySymbol${double.parse(val).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        style: TextStyle(
                          color: isActive ? AppColors.primary : AppTheme.colors.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: _isLoading ? null : _handleContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: _isLoading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/main'),
        ),
        const Text('Fund Wallet', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Compact segmented control to pick WHICH wallet is being funded
  /// (Personal | Business) with live balances — defaults to the walletType
  /// the screen was opened with; the funding flow uses the selection.
  Widget _buildWalletSwitcher() {
    final options = <_WalletSwitcherOption>[
      if (_userWallet != null)
        _WalletSwitcherOption(
          type: 'user',
          label: 'Personal',
          balance: _userWallet!.balance,
          currency: _userWallet!.currency,
        ),
      if (_businessWallet != null)
        _WalletSwitcherOption(
          type: 'business',
          label: 'Business',
          balance: _businessWallet!.balance,
          currency: _businessWallet!.currency,
        ),
    ];
    if (options.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.colors.border),
      ),
      child: Row(
        children: options.map((option) {
          final isActive = _walletType == option.type;
          return Expanded(
            child: GestureDetector(
              onTap: () => _switchWallet(option.type),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      option.label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: isActive ? Colors.white : AppTheme.colors.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${option.currency == 'USD' ? '\u0024' : '\u20A6'}${option.balance.toStringAsFixed(2)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isActive
                            ? Colors.white.withValues(alpha: 0.85)
                            : AppTheme.colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: isActive ? AppColors.primary : AppTheme.colors.border, width: 1.5),
          color: isActive ? AppColors.primary.withValues(alpha: 0.03) : AppTheme.colors.surface,
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isActive ? AppColors.primary : AppColors.primaryBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isActive ? Colors.white : AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.colors.border, width: 2),
              ),
              child: isActive
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.primary),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _WalletSwitcherOption {
  final String type;
  final String label;
  final double balance;
  final String currency;

  const _WalletSwitcherOption({
    required this.type,
    required this.label,
    required this.balance,
    required this.currency,
  });
}

bool _isWalletVerificationSuccessful(Response response) {
  final statusCode = response.statusCode ?? 0;
  final data = response.data;
  if (data is Map) {
    if (data['success'] == true || data['verified'] == true || data['credited'] == true) {
      return true;
    }

    final status = '${data['status'] ?? data['payment_status'] ?? ''}'.toLowerCase();
    if (status == 'success' || status == 'successful' || status == 'verified' || status == 'completed') {
      return true;
    }

    final message = '${data['message'] ?? data['error'] ?? ''}'.toLowerCase();
    if (message.contains('success') ||
        message.contains('verified') ||
        message.contains('credited') ||
        message.contains('already')) {
      return true;
    }

    if (data['success'] == false) {
      return message.contains('success') ||
          message.contains('verified') ||
          message.contains('credited') ||
          message.contains('already');
    }
  }

  return statusCode >= 200 && statusCode < 300;
}

String _walletVerificationMessage(
  Response response, {
  String fallback = 'Wallet funded successfully',
}) {
  final data = response.data;
  if (data is Map) {
    final message = data['message'] ?? data['error'];
    if (message is String && message.trim().isNotEmpty) return message;
  }
  return fallback;
}

bool _isAlreadyVerifiedError(Object error) {
  if (error is! DioException) return false;
  final data = error.response?.data;
  final message = data is Map ? '${data['message'] ?? data['error'] ?? ''}' : '$data';
  final normalized = message.toLowerCase();
  return normalized.contains('already') ||
      normalized.contains('verified') ||
      normalized.contains('credited') ||
      normalized.contains('success');
}

String _getBankName(VirtualAccount? account) {
  if (account == null) return '';
  final provider = account.paymentProvider;
  final providerMetadata = account.providerMetadata;
  // Backend-resolved bank name (from provider metadata or bank-code lookup)
  if (account.bankName != null && account.bankName!.trim().isNotEmpty) {
    return account.bankName!;
  }
  if (provider == 'monnify' && providerMetadata is Map<String, dynamic>) {
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
  if (provider == 'flutterwave' && providerMetadata is Map<String, dynamic>) {
    final data = providerMetadata['data'];
    if (data is Map && data['bank_name'] != null) {
      return data['bank_name'].toString();
    }
  }
  final bankCode = account.bankCode;
  if (bankCode == '058') return 'GTBank';
  if (bankCode == '035') return 'Wema Bank';
  if (bankCode == '232') return 'Sterling Bank';
  // Provider names are never shown to customers — fall back to a neutral label.
  return 'Bank Transfer';
}

class _BankInfoModal extends StatelessWidget {
  final Wallet? wallet;
  final VoidCallback onClose;

  const _BankInfoModal({required this.wallet, required this.onClose});

  @override
  Widget build(BuildContext context) {
    final activeAccount = wallet?.virtualAccounts.firstWhere(
      (a) => a.isActive == true,
      orElse: () => wallet?.virtualAccounts.isNotEmpty == true ? wallet!.virtualAccounts.first : VirtualAccount(),
    );
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        // Theme-aware: was hardcoded Colors.white — in dark mode the sheet
        // stayed white while title/values inherited near-white text colors
        // (white-on-white). surface = white in light, dark navy in dark.
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bank Transfer Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(onPressed: onClose, icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.colors.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.colors.border),
            ),
            child: Column(
              children: [
                const Text(
                  'Transfer money to the account below',
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                _buildDetailItem('BANK NAME', _getBankName(activeAccount)),
                const SizedBox(height: 20),
                _buildDetailItem(
                  'ACCOUNT NUMBER',
                  activeAccount?.virtualAccountNumber ?? 'N/A',
                  isBig: true,
                ),
                const SizedBox(height: 20),
                _buildDetailItem('ACCOUNT NAME', activeAccount?.accountName ?? 'Metricorex Wallet'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onClose,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: const Text("I've made the transfer", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, {bool isBig = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1)),
        const SizedBox(height: 4),
        isBig
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(value,
                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                  IconButton(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: value));
                      AppToast.show('Copied');
                    },
                    icon: const Icon(Icons.copy_outlined, color: AppColors.primary),
                  ),
                ],
              )
            : Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _FundWalletWebView extends StatefulWidget {
  final String url;
  final String? reference;
  final VoidCallback onComplete;

  const _FundWalletWebView({
    required this.url,
    required this.reference,
    required this.onComplete,
  });

  @override
  State<_FundWalletWebView> createState() => _FundWalletWebViewState();
}

class _FundWalletWebViewState extends State<_FundWalletWebView> {
  bool _isLoading = true;
  late final WebViewController _controller;
  bool _isVerifying = false;
  bool _succeeded = false;
  // Callback URLs already handed to verification — prevents double-firing
  // when the provider redirect triggers the delegate more than once.
  final Set<String> _handledUrls = <String>{};

  /// ONLY our own callback endpoints signal "payment finished". Broad
  /// substring matches like 'success'/'callback'/'verify' used to trip on
  /// bank 3DS/OTP pages mid-checkout, latched the handler, and left the
  /// webview stuck on a dead (blank) navigation afterwards.
  static const List<String> _callbackPathMarkers = <String>[
    '/api/wallet/verify',
    '/payment/callback',
  ];

  bool _isCallbackUrl(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final path = uri.path.toLowerCase();
    if (_callbackPathMarkers.any(path.contains)) return true;
    // Any URL carrying our own funding reference is a callback signal too.
    final ref = uri.queryParameters['reference'] ?? uri.queryParameters['tx_ref'];
    return ref != null && ref.startsWith('FUND-');
  }

  @override
  void initState() {
    super.initState();
    // Set webview open flag
    (myAppKey.currentState as dynamic)?.setWebViewOpen(true);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) async {
            final url = request.url;
            if (_isCallbackUrl(url)) {
              final key = Uri.tryParse(url)?.toString() ?? url;
              if (!_handledUrls.contains(key)) {
                _handledUrls.add(key);
                // Verify AFTER the frame — calling setState synchronously
                // from the navigation delegate is unsafe.
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _verifyPayment();
                });
              }
              // Never render the backend/browser callback page inside this
              // webview — the app verifies and returns on its own.
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  void dispose() {
    // Clear webview open flag
    (myAppKey.currentState as dynamic)?.setWebViewOpen(false);
    super.dispose();
  }

  /// Re-verifies the transaction against the backend (which re-checks the
  /// provider). Retryable — a pending result never locks the user out; they
  /// can also tap "Verify" manually at any time.
  Future<void> _verifyPayment() async {
    if (_isVerifying || _succeeded) return;
    final reference = widget.reference;
    if (reference == null || reference.isEmpty) {
      AppToast.show('Payment reference missing — please contact support.');
      return;
    }
    if (mounted) setState(() => _isVerifying = true);
    try {
      final api = ApiService();
      final response = await api.verifyWalletPayment(reference, suppressToast: true);
      final data = response.data;
      final explicitlyCancelled =
          data is Map && data['cancelled'] == true && data['success'] != true;

      if (_isWalletVerificationSuccessful(response)) {
        AppToast.show(
          _walletVerificationMessage(response),
          type: AppToastType.success,
        );
        if (mounted) {
          setState(() {
            _succeeded = true;
            _isVerifying = false;
          });
          // Brief success beat, then auto-close back into the app.
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onComplete();
          }
        }
        return;
      }

      AppToast.show(
        explicitlyCancelled
            ? (data is Map && data['message'] is String
                ? data['message'] as String
                : 'Payment cancelled — no money was deducted.')
            : _walletVerificationMessage(response,
                fallback: 'Payment verification pending — tap Verify to retry'),
      );
    } catch (e) {
      debugPrint('Payment verification failed: $e');
      if (_isAlreadyVerifiedError(e)) {
        AppToast.show('Wallet funded successfully', type: AppToastType.success);
        if (mounted) {
          setState(() {
            _succeeded = true;
            _isVerifying = false;
          });
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (mounted) {
            Navigator.of(context).pop();
            widget.onComplete();
          }
        }
      } else {
        AppToast.show(
          'Payment verification pending — complete the checkout, then tap Verify.',
        );
      }
    } finally {
      if (mounted && !_succeeded) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Fund Wallet'),
        centerTitle: true,
        actions: [
          if (!_succeeded && widget.reference != null)
            TextButton.icon(
              onPressed: _isVerifying ? null : _verifyPayment,
              icon: _isVerifying
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.verified_outlined, color: Colors.white),
              label: const Text(
                'Verify',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading && !_isVerifying && !_succeeded)
            const Center(child: CircularProgressIndicator()),
          if (_isVerifying)
            _PaymentStatusOverlay(
              icon: const CircularProgressIndicator(),
              title: 'Verifying your payment...',
              message:
                  'Checking with the payment provider. This only takes a moment — '
                  'you will return to your wallet automatically.',
            ),
          if (_succeeded)
            _PaymentStatusOverlay(
              icon: Icon(Icons.check_circle, size: 56, color: Colors.green[600]),
              title: 'Wallet funded successfully',
              message: 'Returning you to the app...',
            ),
        ],
      ),
    );
  }
}

class _PaymentStatusOverlay extends StatelessWidget {
  final Widget icon;
  final String title;
  final String message;

  const _PaymentStatusOverlay({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      color: Colors.black.withValues(alpha: 0.45),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Card(
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              icon,
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.text,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
