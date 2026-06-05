import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../services/api.dart';
import '../models/subscription.dart';
import '../models/plan.dart';
import '../models/card_model.dart';
import '../models/payment_transaction.dart';
import '../theme/app_theme.dart';

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen> {
  bool _isLoading = true;
  Subscription? _currentSubscription;
  List<Plan> _plans = [];
  List<CardModel> _cards = [];
  List<PaymentTransaction> _transactions = [];
  String? _selectedPlanId;
  int _page = 1;
  bool _hasMore = true;
  String _statusFilter = 'all';
  bool _isLoadingMore = false;
  bool _isUpgrading = false;
  bool _isAddingCard = false;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getCurrentSubscription(),
        api.getSubscriptionPlans(),
        api.getSubscriptionCards(),
      ], eagerError: false);

      final subRes = results[0];
      if (subRes.statusCode == 200) {
        final data = subRes.data;
        if (data['success'] == true && data['subscription'] != null) {
          setState(() {
            _currentSubscription = Subscription.fromJson(data['subscription'] as Map<String, dynamic>);
          });
        }
      }

      final plansRes = results[1];
      if (plansRes.statusCode == 200) {
        final data = plansRes.data;
        if (data['success'] == true) {
          final plansJson = data['plans'] as List<dynamic>? ?? [];
          setState(() {
            _plans = [];
            for (var planJson in plansJson) {
              _plans.add(Plan.fromJson(planJson as Map<String, dynamic>));
            }
          });
        }
      }

      final cardsRes = results[2];
      if (cardsRes.statusCode == 200) {
        final data = cardsRes.data;
        if (data['success'] == true) {
          final cardsJson = data['cards'] as List<dynamic>? ?? [];
          setState(() {
            _cards = [];
            for (var cardJson in cardsJson) {
              _cards.add(CardModel.fromJson(cardJson as Map<String, dynamic>));
            }
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch subscription data: $e');
    }
    
    try {
      await _fetchTransactions(1, refresh: true);
    } catch (e) {
      debugPrint('Failed to fetch transactions: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTransactions(int pageNumber, {bool refresh = false}) async {
    if (refresh) {
      // handled by parent
    } else {
      setState(() => _isLoadingMore = true);
    }

    try {
      final api = ApiService();
      final params = <String, dynamic>{
        'page': pageNumber,
        'perPage': 5,
      };
      if (_statusFilter != 'all') params['status'] = _statusFilter;

      final response = await api.getSubscriptionTransactions(params: params);
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          final txList = data['transactions'] as List<dynamic>? ?? data['data'] as List<dynamic>? ?? [];
          
          final newTx = <PaymentTransaction>[];
          for (var txJson in txList) {
            newTx.add(PaymentTransaction.fromJson(txJson as Map<String, dynamic>));
          }
          
          setState(() {
            if (refresh) {
              _transactions = newTx;
            } else {
              _transactions = [..._transactions, ...newTx];
            }
            _hasMore = newTx.length == 5;
            _page = pageNumber;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch transactions: $e');
    } finally {
      setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _handleUpgrade(Plan plan, String action) async {
    // If downgrade to free, use downgrade endpoint
    if (action == 'Downgrade' && plan.name.toLowerCase().contains('free')) {
      await _handleDowngrade();
      return;
    }
    
    setState(() {
      _selectedPlanId = plan.id;
      _isUpgrading = true;
    });
    try {
      final api = ApiService();
      final response = await api.initiateSubscriptionPayment(plan.id, plan.currency ?? 'NGN');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['checkout_url'] != null) {
          Fluttertoast.showToast(msg: 'Opening payment...');
          _showPaymentWebView(data['checkout_url']);
        }
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      setState(() => _isUpgrading = false);
    }
  }

  Future<void> _handleAddCard() async {
    setState(() => _isAddingCard = true);
    try {
      final api = ApiService();
      final response = await api.addSubscriptionCard();
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true && data['checkout_url'] != null) {
          _showPaymentWebView(data['checkout_url']);
        }
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      setState(() => _isAddingCard = false);
    }
  }

  void _showPaymentWebView(String url) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => _PaymentWebViewScreen(
          url: url,
          onComplete: _fetchData,
        ),
      ),
    );
  }

  Future<void> _handleCancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Subscription'),
        content: const Text(
          'Are you sure you want to cancel your subscription? You will lose access to premium features at the end of your billing period.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep Subscription')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isCancelling = true);
    try {
      final api = ApiService();
      await api.cancelSubscription();
      Fluttertoast.showToast(msg: 'Subscription cancelled successfully');
      await _fetchData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      setState(() => _isCancelling = false);
    }
  }

  Future<void> _handleDowngrade() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Downgrade Plan'),
        content: const Text('Are you sure you want to downgrade to the Free Plan?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Downgrade'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ApiService();
      await api.downgradeSubscription();
      Fluttertoast.showToast(msg: 'Downgraded to free plan successfully');
      await _fetchData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _handleSetActiveCard(String cardId) async {
    try {
      final api = ApiService();
      await api.setActiveSubscriptionCard(cardId);
      Fluttertoast.showToast(msg: 'Card set as active');
      await _fetchData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _handleRemoveCard(String cardId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Card'),
        content: const Text('Are you sure you want to remove this card?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      final api = ApiService();
      await api.removeSubscriptionCard(cardId);
      Fluttertoast.showToast(msg: 'Card removed');
      await _fetchData();
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  Future<void> _handleExportTransactions() async {
    try {
      final api = ApiService();
      final response = await api.exportSubscriptionTransactions();
      if (response.statusCode == 200) {
        Fluttertoast.showToast(msg: 'Export started');
      }
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildHeader(),
                    if (_currentSubscription != null) _buildCurrentPlan(),
                    const SizedBox(height: 32),
                    _buildPlans(),
                    const SizedBox(height: 32),
                    _buildPaymentMethods(),
                    const SizedBox(height: 32),
                    _buildTransactionHistory(),
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
        const Expanded(
          child: Text(
            'Subscription',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildCurrentPlan() {
    final sub = _currentSubscription!;
    final isActive = sub.subscriptionStatus == 'active';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Current Plan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                sub.planName,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: (isActive ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  (sub.subscriptionStatus[0].toUpperCase() + sub.subscriptionStatus.substring(1)),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isActive ? AppColors.success : AppColors.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '\u20A6${sub.planPrice}/month',
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const SizedBox(height: 16),
          ...sub.features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_outlined, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Text(f),
                  ],
                ),
              )),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.colors.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Next renewal: ${DateTime.tryParse(sub.nextDueSubscriptionDate ?? '')?.toLocal().toString().split(' ')[0] ?? 'N/A'}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          if (sub.planName != 'Free') ...[
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isCancelling ? null : _handleDowngrade,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Downgrade to Free', style: TextStyle(color: AppColors.primary)),
              ),
            ),
            if (isActive) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _isCancelling ? null : _handleCancel,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.error),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Cancel Subscription', style: TextStyle(color: AppColors.error)),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildPlans() {
    if (_plans.isEmpty) return const SizedBox.shrink();
    
    // Sort plans by price (lowest to highest)
    final sortedPlans = [..._plans]..sort((a, b) => a.price.compareTo(b.price));
    
    // Find current plan
    final currentPlanId = _currentSubscription?.planId;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Available Plans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        ...sortedPlans.map((plan) {
          final isActive = currentPlanId == plan.id;
          final isSelected = _selectedPlanId == plan.id;
          
          // Determine if this is upgrade or downgrade
          final currentPrice = _currentSubscription?.price ?? 0;
          final action = isActive ? null : (plan.price > currentPrice ? 'Upgrade' : 'Downgrade');
          
          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.colors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isActive ? AppColors.primary : (isSelected ? AppColors.primary : Colors.transparent),
                width: isActive ? 2 : (isSelected ? 2 : 1),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(plan.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('Active', style: TextStyle(fontSize:12, fontWeight:FontWeight.w600, color: AppColors.primary)),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(plan.description, style: const TextStyle(fontSize: 14, color: Colors.grey)),
                const SizedBox(height: 12),
                Text(
                  '${plan.currency ?? 'USD'} ${plan.price.toStringAsFixed(0)}${plan.duration != null ? '/${plan.duration}' : ''}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
                const SizedBox(height: 12),
                ...plan.features.map((f) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outlined, size: 16, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(child: Text(f, style: const TextStyle(fontSize: 13))),
                        ],
                      ),
                    )),
                if (action != null) ...[
                  const SizedBox(height:16),
                  ElevatedButton(
                    onPressed: _isUpgrading ? null : () => _handleUpgrade(plan, action),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isUpgrading && _selectedPlanId == plan.id
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(action, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Payment Methods', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            TextButton(
              onPressed: _isAddingCard ? null : _handleAddCard,
              child: const Text('Add Card', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_cards.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Column(
              children: [
                Icon(Icons.credit_card_outlined, size: 48, color: AppTheme.colors.textSecondary),
                const SizedBox(height: 12),
                Text('No payment methods added', style: TextStyle(color: AppTheme.colors.textSecondary)),
              ],
            ),
          )
        else
          ..._cards.map((card) {
            final isActive = card.isActive;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.credit_card_outlined, size: 24, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022 ${card.last4}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                        Text(
                          '${card.cardType} \u2022 Exp ${card.expMonth}/${card.expYear}',
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primaryBg,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('Active',
                          style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500)),
                    )
                  else
                    TextButton(
                      onPressed: () => _handleSetActiveCard(card.id),
                      child: const Text('Set Active', style: TextStyle(fontSize: 14, color: AppColors.primary)),
                    ),
                  IconButton(
                    onPressed: () => _handleRemoveCard(card.id),
                    icon: const Icon(Icons.delete_outline, color: AppColors.error),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTransactionHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Transaction History', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            IconButton(
              onPressed: _handleExportTransactions,
              icon: const Icon(Icons.download_outlined, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: ['all', 'success', 'failed'].map((f) {
            final isActive = _statusFilter == f;
            return GestureDetector(
              onTap: () {
                setState(() => _statusFilter = f);
                _fetchTransactions(1, refresh: true);
              },
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary : AppTheme.colors.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isActive ? AppColors.primary : AppTheme.colors.border),
                ),
                child: Text(
                  f.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: isActive ? Colors.white : AppTheme.colors.textSecondary,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        ..._transactions.map((tx) {
          final isSuccess = tx.status == 'success';
          
          // Parse amount safely
          double? amountDouble;
          try {
            if (tx.amount is String) {
              amountDouble = double.tryParse(tx.amount);
            } else if (tx.amount is num) {
              amountDouble = (tx.amount as num).toDouble();
            }
          } catch (e) {
            debugPrint('Error parsing amount: $e');
          }
          amountDouble ??= 0.0;
          
          return InkWell(
            onTap: () => context.push('/main/transaction-detail', extra: tx),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.colors.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (tx.transactionType ?? 'PAYMENT').toUpperCase(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateTime.tryParse(tx.createdAt)?.toLocal().toString().split(' ')[0] ?? tx.createdAt,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '\u20A6${amountDouble.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: (isSuccess ? AppColors.success : AppColors.error).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          tx.status,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSuccess ? AppColors.success : AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }),
        if (_transactions.isEmpty)
          Padding(
            padding: const EdgeInsets.all(32),
            child: Text('No transactions found', style: TextStyle(color: AppTheme.colors.textSecondary, fontSize: 14)),
          ),
        if (_hasMore)
                  TextButton(
                    onPressed: _isLoadingMore ? null : () => _fetchTransactions(_page + 1),
                    child: _isLoadingMore
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Load More', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600)),
                  ),
      ],
    );
  }
}

class _PaymentWebViewScreen extends StatefulWidget {
  final String url;
  final Future<void> Function() onComplete;

  const _PaymentWebViewScreen({required this.url, required this.onComplete});

  @override
  State<_PaymentWebViewScreen> createState() => _PaymentWebViewScreenState();
}

class _PaymentWebViewScreenState extends State<_PaymentWebViewScreen> {
  bool _isLoading = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppTheme.colors.surface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Secure Payment'),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }

  late final WebViewController _controller;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            final url = request.url;
            if ((url.contains('success') || url.contains('callback') || url.contains('verify'))) {
              _handlePaymentComplete(url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _handlePaymentComplete(String url) async {
    try {
      final uri = Uri.parse(url);
      final reference = uri.queryParameters['reference'];
      if (reference != null) {
        final api = ApiService();
        await api.verifySubscriptionPayment(reference);
      }
      Fluttertoast.showToast(msg: 'Payment verified successfully');
    } catch (e) {
      Fluttertoast.showToast(
        msg: e.toString().replaceAll('Exception: ', ''),
        backgroundColor: AppColors.error,
      );
    } finally {
      await widget.onComplete();
      if (mounted) Navigator.pop(context);
    }
  }
}