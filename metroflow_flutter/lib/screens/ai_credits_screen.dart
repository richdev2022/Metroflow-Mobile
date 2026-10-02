import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';

/// MetricAi Credit Packs — one-time AI usage top-ups charged from the wallet.
/// Credits are consumed automatically by MetricAi whenever the plan's
/// daily/monthly allowance runs out (see backend lib/ai-usage.ts).
class AiCreditsScreen extends StatefulWidget {
  const AiCreditsScreen({super.key});

  @override
  State<AiCreditsScreen> createState() => _AiCreditsScreenState();
}

class _AiCreditsScreenState extends State<AiCreditsScreen> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _packs = [];
  int _balance = 0;
  bool _isLoading = true;
  String? _buyingPackId;

  @override
  void initState() {
    super.initState();
    _fetchPacks();
  }

  Future<void> _fetchPacks() async {
    setState(() => _isLoading = true);
    try {
      final response = await _api.getAiCreditPacks();
      if (response.data['success'] == true && mounted) {
        setState(() {
          _packs = (response.data['packs'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
          _balance = (response.data['balance']?['balance'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (e) {
      debugPrint('Failed to load AI credit packs: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _money(dynamic v, [String currency = 'NGN']) {
    final n = double.tryParse(v?.toString() ?? '0') ?? 0;
    final symbol = currency == 'USD'
        ? r'$'
        : currency == 'EUR'
            ? '€'
            : currency == 'GBP'
                ? '£'
                : '₦';
    return '$symbol${n.toStringAsFixed(n.truncateToDouble() == n ? 0 : 2)}';
  }

  Future<void> _buy(Map<String, dynamic> pack) async {
    final packId = pack['id']?.toString() ?? '';
    setState(() => _buyingPackId = packId);
    try {
      final response = await _api.purchaseAiCreditPack(packId);
      if (response.data['success'] == true && mounted) {
        final added = response.data['credits_added'];
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$added MetricAi credits added to your balance')),
        );
        await _fetchPacks();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _buyingPackId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        foregroundColor: colors.text,
        elevation: 0,
        title: const Text('MetricAi Credits'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : RefreshIndicator(
              color: colors.primary,
              onRefresh: _fetchPacks,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  // Balance card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.primary.withValues(alpha: 0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR CREDIT BALANCE',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Colors.white.withValues(alpha: 0.8),
                                letterSpacing: 1)),
                        const SizedBox(height: 6),
                        Text('$_balance credits',
                            style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                        const SizedBox(height: 4),
                        Text(
                          'Used automatically when your plan\u2019s AI allowance runs out. Never expires.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text('Top-up packs',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.text)),
                  const SizedBox(height: 10),
                  ..._packs.map((pack) {
                    final price = double.tryParse(pack['price']?.toString() ?? '0') ?? 0;
                    final discounted = (pack['discounted_price'] as num?)?.toDouble() ?? price;
                    final savings = price - discounted;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: colors.primaryBg,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.auto_awesome, color: colors.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(pack['name']?.toString() ?? 'Pack',
                                    style: TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w700,
                                        color: colors.text)),
                                const SizedBox(height: 2),
                                Text(
                                  '${(pack['credits'] as num?)?.toInt() ?? 0} credits · ${_money(discounted, pack['currency']?.toString() ?? 'NGN')}${savings > 0 ? ' (save ${_money(savings, pack['currency']?.toString() ?? 'NGN')})' : ''}',
                                  style: TextStyle(
                                      fontSize: 12.5, color: colors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed:
                                _buyingPackId == pack['id']?.toString() ? null : () => _buy(pack),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              foregroundColor: Colors.white,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            ),
                            child: _buyingPackId == pack['id']?.toString()
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Text('Buy',
                                    style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  Text(
                    'Purchases are charged from your wallet. A receipt is recorded in your transactions.',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
    );
  }
}
