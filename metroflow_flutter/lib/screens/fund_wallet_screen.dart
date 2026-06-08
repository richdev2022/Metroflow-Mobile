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
        final walletData = widget.walletType == 'business'
            ? data['business_wallet']
            : data['user_wallet'];
        if (walletData == null) return;
        setState(() {
          _selectedWallet = Wallet.fromJson(walletData as Map<String, dynamic>);
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch wallet info: $e');
    }
  }

  Future<void> _handleContinue() async {
    final amountText = _amountController.text;
    if (amountText.isEmpty || double.tryParse(amountText) == null || double.parse(amountText) <= 0) {
      AppToast.show('Please enter a valid amount', type: AppToastType.warning);
      return;
    }

    if (_method == 'bank') {
      _showBankInfo();
      return;
    }

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final response = await api.fundWallet(double.parse(amountText), widget.walletType);
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
                'Choose how you want to fund your ${widget.walletType} wallet',
                style: const TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 32),
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
                    const Text('\u20A6', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
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
                        '\u20A6${double.parse(val).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
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

class _BankInfoModal extends StatelessWidget {
  final Wallet? wallet;
  final VoidCallback onClose;

  const _BankInfoModal({required this.wallet, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
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
                _buildDetailItem('BANK NAME', wallet?.bankName ?? 'Squad (GTBank)'),
                const SizedBox(height: 20),
                _buildDetailItem(
                  'ACCOUNT NUMBER',
                  wallet?.virtualAccountNumber ?? 'N/A',
                  isBig: true,
                ),
                const SizedBox(height: 20),
                _buildDetailItem('ACCOUNT NAME', wallet?.accountName ?? 'Metroflow Wallet'),
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
                    onPressed: () => AppToast.show('Copied'),
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
  bool _completed = false;

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
            if (url.contains('success') || url.contains('callback') || url.contains('verify')) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _handlePaymentComplete(url);
              });
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

  Future<void> _handlePaymentComplete(String url) async {
    if (_completed || _isVerifying) return;
    _completed = true;
    if (mounted) setState(() => _isVerifying = true);
    var shouldResetVerifying = true;
    try {
      final uri = Uri.parse(url);
      final reference = uri.queryParameters['reference'] ??
          uri.queryParameters['tx_ref'] ??
          widget.reference;
      if (reference != null) {
        final api = ApiService();
        final response = await api.verifyWalletPayment(reference, suppressToast: true);
        if (_isWalletVerificationSuccessful(response)) {
          AppToast.show(
            _walletVerificationMessage(response),
            type: AppToastType.success,
          );
          if (mounted) {
            shouldResetVerifying = false;
            Navigator.of(context).pop();
            widget.onComplete();
          }
        } else {
          AppToast.show(
            _walletVerificationMessage(response, fallback: 'Payment verification pending'),
          );
        }
      }
    } catch (e) {
      debugPrint('Payment verification failed: $e');
      if (_isAlreadyVerifiedError(e)) {
        AppToast.show('Wallet funded successfully', type: AppToastType.success);
        if (mounted) {
          shouldResetVerifying = false;
          Navigator.of(context).pop();
          widget.onComplete();
        }
      } else {
        AppToast.show('Payment verification pending. Please refresh your wallet balance.');
      }
    } finally {
      if (shouldResetVerifying && mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.colors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Fund Wallet'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading || _isVerifying)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
