import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../models/transfer.dart';
import '../theme/app_theme.dart';

class TransferDetailScreen extends StatelessWidget {
  const TransferDetailScreen({super.key, required this.transfer});

  final Transfer transfer;

  static String formatAmount(Transfer transfer) {
    final amount = transfer.amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '${transfer.currency} $amount';
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
    final status = transfer.status.toLowerCase();

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
                      'Transfer Receipt',
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
                            formatAmount(transfer),
                            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.primary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            transfer.status.toUpperCase(),
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _statusColor(status)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _section(
                      colors,
                      title: 'Recipient',
                      rows: [
                        _row('Name', transfer.recipientName),
                        _row('Account Number', transfer.recipientAccount),
                        _row('Bank Code', transfer.recipientBank),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _section(
                      colors,
                      title: 'Transfer Details',
                      rows: [
                        _row('Reference', transfer.reference),
                        _row('Remark', transfer.remark),
                        _row('Source Type', transfer.sourceType),
                        _row('Source ID', transfer.sourceId),
                        _row('Wallet ID', transfer.walletId),
                        _row('Fee', '${transfer.currency} ${transfer.fee.toStringAsFixed(2)}'),
                        _row('Created', formatDate(transfer.createdAt)),
                        _row('Updated', formatDate(transfer.updatedAt)),
                      ],
                    ),
                    if (transfer.failureReason != null && transfer.failureReason!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _section(
                        colors,
                        title: 'Failure Reason',
                        rows: [_row('Reason', transfer.failureReason)],
                      ),
                    ],
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
            width: 120,
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
