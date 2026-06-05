import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';
import 'package:metroflow_flutter/services/api.dart';
import 'package:metroflow_flutter/models/fee_config.dart';

class FeesScreen extends ConsumerStatefulWidget {
  const FeesScreen({super.key});

  @override
  ConsumerState<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends ConsumerState<FeesScreen> {
  List<FeeConfig> _fees = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchFees();
  }

  Future<void> _fetchFees() async {
    try {
      final api = ApiService();
      final response = await api.getFees();
      if (response.data['success'] == true && mounted) {
        final data = response.data['data'] as List<dynamic>?;
        setState(() {
          _fees = data
              ?.map((e) => FeeConfig.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch fees: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _formatFeeValue(FeeConfig fee) {
    final config = fee.config;
    switch (fee.configType) {
      case 'flat':
        return '${fee.currency} ${(config.amount ?? 0).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
      case 'percentage_cap':
        final pct = config.percentage?.toStringAsFixed(0) ?? '0';
        final cap = config.cap ?? 0;
        return '$pct% (Max ${fee.currency} ${cap.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')})';
      case 'flat_conditional':
        if (config.conditions != null && config.conditions!.isNotEmpty) {
          final cond = config.conditions!.first;
          return '${fee.currency} ${cond.fee.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
        }
        return 'Conditional';
      case 'range':
        if (config.ranges != null && config.ranges!.isNotEmpty) {
          final fees = config.ranges!.map((r) => r.fee).toList();
          final minFee = fees.reduce((a, b) => a < b ? a : b);
          final maxFee = fees.reduce((a, b) => a > b ? a : b);
          return '${fee.currency} ${minFee.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')} - ${fee.currency} ${maxFee.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
        }
        return 'Variable';
      default:
        return 'N/A';
    }
  }

  String _formatFeeDescription(FeeConfig fee) {
    final config = fee.config;
    switch (fee.configType) {
      case 'range':
        if (config.ranges == null || config.ranges!.isEmpty) return '';
        return config.ranges!
            .map((r) {
              final min = r.min.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
              final max = r.max >= 999999999 ? 'Above' : '${fee.currency} ${r.max.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}';
              final feeVal = r.fee.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
              return '${fee.currency} $min - $max: ${fee.currency} $feeVal';
            })
            .join('\n');
      case 'flat_conditional':
        if (config.conditions == null || config.conditions!.isEmpty) return '';
        return config.conditions!
            .map((c) {
              final feeVal = c.fee.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
              final threshold = c.threshold.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
              return 'A fee of ${fee.currency} $feeVal applies for transactions ${c.operator} ${fee.currency} $threshold';
            })
            .join('\n');
      case 'percentage_cap':
        final pct = config.percentage?.toStringAsFixed(0) ?? '0';
        final cap = (config.cap ?? 0).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
        return 'A $pct% fee applies, capped at ${fee.currency} $cap.';
      case 'flat':
        final amount = (config.amount ?? 0).toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
        return 'A flat fee of ${fee.currency} $amount applies to all transactions.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return const Scaffold(
        body: SafeArea(
          child: Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(color: colors.surface),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colors.text),
                    onPressed: () => context.go('/main'),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Applicable Fees',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _fees.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.local_offer_outlined, size: 64, color: colors.textSecondary),
                          const SizedBox(height: 16),
                          Text(
                            'No fee information available at the moment.',
                            style: TextStyle(fontSize: 16, color: colors.textSecondary),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(24),
                      itemCount: _fees.length,
                      itemBuilder: (context, index) {
                        final fee = _fees[index];
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: colors.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      fee.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colors.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _formatFeeValue(fee),
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: colors.primary,
                                    ),
                                    textAlign: TextAlign.end,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _formatFeeDescription(fee),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: colors.textSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
