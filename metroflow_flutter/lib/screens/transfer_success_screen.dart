import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/transfer.dart';
import '../theme/app_theme.dart';

class TransferSuccessScreen extends StatelessWidget {
  const TransferSuccessScreen({
    super.key,
    this.bulkResponse,
    this.singleResponse,
  });

  final BulkTransferResponse? bulkResponse;
  final SingleTransferResponse? singleResponse;

  // Status-aware display: the backend can legitimately return a FAILED
  // transfer (provider rejection, processing error). Showing a green
  // "Transfer Successful" with the raw failure text was misleading.
  String get _status {
    final s = (singleResponse?.data?.status ?? '').toLowerCase();
    if (s.isNotEmpty) return s;
    if (bulkResponse != null) return 'queued';
    return (singleResponse?.success ?? false) ? 'success' : 'failed';
  }

  bool get _isFailed => _status == 'failed';
  bool get _isProcessing =>
      _status == 'processing' || _status == 'pending' || _status == 'queued';

  String get _screenTitle {
    if (_isFailed) return 'Transfer Failed';
    if (_isProcessing) return 'Transfer Processing';
    return 'Transfer Successful';
  }

  String get _headline {
    if (_isFailed) return 'Transfer Failed';
    if (_isProcessing) return 'Transfer Processing';
    return bulkResponse?.message ?? singleResponse?.message ?? 'Transfer Initiated';
  }

  static String formatAmount(double amount, String currency) {
    return '$currency ${amount.toStringAsFixed(0).replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    )}';
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
                    icon: Icon(Icons.close, color: colors.text),
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      _screenTitle,
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
                    _buildHeader(colors),
                    const SizedBox(height: 16),
                    if (bulkResponse != null)
                      ..._buildBulkContent(colors, bulkResponse!)
                    else if (singleResponse != null)
                      ..._buildSingleContent(colors, singleResponse!),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    final IconData headerIcon;
    final Color iconColor;
    final Color iconBg;
    if (_isFailed) {
      headerIcon = Icons.error_outline;
      iconColor = AppColors.error;
      iconBg = AppColors.error.withValues(alpha: 0.12);
    } else if (_isProcessing) {
      headerIcon = Icons.schedule_rounded;
      iconColor = AppColors.warning;
      iconBg = AppColors.warning.withValues(alpha: 0.12);
    } else {
      headerIcon = Icons.check_circle_outline;
      iconColor = AppColors.success;
      iconBg = AppColors.success.withValues(alpha: 0.12);
    }

    return Container(
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
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(headerIcon, color: iconColor, size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            _headline,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.text),
            textAlign: TextAlign.center,
          ),
          if (_isFailed) ...[
            const SizedBox(height: 10),
            Text(
              // With server-side auto-reversal the debit (amount + fee) is
              // returned to the wallet automatically.
              'The full amount, including the fee, is being returned to your wallet automatically.',
              style: TextStyle(fontSize: 13, color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildBulkContent(ThemeColors colors, BulkTransferResponse response) {
    final data = response.data;
    if (data == null) return [];

    return [
      _section(
        colors,
        title: 'Summary',
        rows: [
          _row('Queued Transfers', '${data.queued}'),
          _row('Type', data.type),
          _row('Wallet ID', data.walletId),
        ],
      ),
      const SizedBox(height: 16),
      _section(
        colors,
        title: 'Totals',
        rows: [
          _row('Amount', formatAmount(data.totals.amount, 'NGN')),
          _row('Fee', formatAmount(data.totals.fee, 'NGN')),
          _row('Total', formatAmount(data.totals.total, 'NGN')),
        ],
      ),
      const SizedBox(height: 16),
      _section(
        colors,
        title: 'Transfers (${data.transfers.length})',
        children: data.transfers.map((transfer) => _queuedTransferCard(colors, transfer)).toList(),
      ),
    ];
  }

  List<Widget> _buildSingleContent(ThemeColors colors, SingleTransferResponse response) {
    final data = response.data;
    if (data == null) return [];

    return [
      _section(
        colors,
        title: 'Transfer Details',
        rows: [
          _row('ID', data.id),
          _row('Reference', data.reference),
          _row('Amount', formatAmount(data.amount, data.currency)),
          _row('Fee', formatAmount(data.fee, data.currency)),
          _row('Total', formatAmount(data.total, data.currency)),
          _row('Status', data.status.toUpperCase()),
          _row('Wallet ID', data.walletId),
          _row('Created At', formatDate(data.createdAt)),
          _row('Updated At', formatDate(data.updatedAt)),
        ],
      ),
      const SizedBox(height: 16),
      _section(
        colors,
        title: 'Recipient',
        rows: [
          _row('Name', data.recipient.accountName),
          _row('Account Number', data.recipient.accountNumber),
          _row('Bank Code', data.recipient.bankCode),
        ],
      ),
    ];
  }

  Widget _section(ThemeColors colors, {required String title, List<_DetailRow>? rows, List<Widget>? children}) {
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
          if (rows != null) ...rows.map((row) => _detailLine(colors, row.label, row.value)),
          if (children != null) ...children,
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

  Widget _queuedTransferCard(ThemeColors colors, QueuedTransfer transfer) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  transfer.recipient.accountName,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.text),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  transfer.status.toUpperCase(),
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.warning),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                formatAmount(transfer.amount, transfer.currency),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: colors.primary),
              ),
              Text(
                '${transfer.recipient.bankCode} • ${transfer.recipient.accountNumber}',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  _DetailRow _row(String label, String? value) => _DetailRow(label, value);
}

class _DetailRow {
  const _DetailRow(this.label, this.value);

  final String label;
  final String? value;
}
