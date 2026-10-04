import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/payment_transaction.dart';
import '../theme/app_theme.dart';

class TransactionDetailScreen extends StatelessWidget {
  const TransactionDetailScreen({super.key, required this.transaction});

  final PaymentTransaction transaction;

  static String formatAmount(PaymentTransaction transaction) {
    double? amountDouble;
    try {
      if (transaction.amount is String) {
        amountDouble = double.tryParse(transaction.amount);
      } else if (transaction.amount is num) {
        amountDouble = (transaction.amount as num).toDouble();
      }
    } catch (e) {
      amountDouble = 0.0;
    }
    amountDouble ??= 0.0;
    final amountStr = amountDouble.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${transaction.currency} $amountStr';
  }

  static String formatFee(PaymentTransaction transaction) {
    double? feeDouble;
    try {
      if (transaction.fee is String) {
        feeDouble = double.tryParse(transaction.fee);
      } else if (transaction.fee is num) {
        feeDouble = (transaction.fee as num).toDouble();
      }
    } catch (e) {
      feeDouble = 0.0;
    }
    feeDouble ??= 0.0;
    final feeStr = feeDouble.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${transaction.currency} $feeStr';
  }

  static String formatDate(String date) {
    try {
      final dt = DateTime.parse(date).toLocal();
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return date.isEmpty ? 'N/A' : date;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final status = transaction.status.toLowerCase();

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              color: colors.surface,
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: colors.text),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Transaction Receipt',
                      style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: colors.text),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border),
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: _statusColor(status).withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(_statusIcon(status), color: _statusColor(status), size: 28),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            formatAmount(transaction),
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            transaction.status.toUpperCase(),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _statusColor(status)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      colors,
                      title: 'Transaction Details',
                      rows: [
                        _row('Type', transaction.transactionType?.toUpperCase()),
                        _row('Direction', transaction.direction?.toUpperCase()),
                        _row('Description', transaction.description),
                        _row('Reference', transaction.reference),
                        _row('Fee', formatFee(transaction)),
                        _row('Created', formatDate(transaction.createdAt)),
                        if (transaction.updatedAt != null) _row('Updated', formatDate(transaction.updatedAt!)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _section(
                      colors,
                      title: 'IDs',
                      rows: [
                        _row('Transaction ID', transaction.id),
                        if (transaction.businessId != null) _row('Business ID', transaction.businessId),
                        if (transaction.planId != null) _row('Plan ID', transaction.planId),
                        if (transaction.walletId != null) _row('Wallet ID', transaction.walletId),
                        if (transaction.userId != null) _row('User ID', transaction.userId),
                      ],
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

  Widget _section(ThemeColors colors, {required String title, required List<_DetailRow> rows}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: colors.text)),
          const SizedBox(height: 12),
          ...rows.map((row) => _detailLine(colors, row.label, row.value)),
        ],
      ),
    );
  }

  Widget _detailLine(ThemeColors colors, String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value == null || value.isEmpty ? 'N/A' : value,
              textAlign: TextAlign.right,
              style: TextStyle(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  _DetailRow _row(String label, String? value) => _DetailRow(label, value);

  Color _statusColor(String status) {
    switch (status) {
      case 'success':
        return AppColors.success;
      case 'failed':
        return AppColors.error;
      case 'processing':
      case 'pending':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'success':
        return Icons.check_circle_outline;
      case 'failed':
        return Icons.error_outline;
      default:
        return Icons.schedule_outlined;
    }
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value);

  final String label;
  final String? value;
}
