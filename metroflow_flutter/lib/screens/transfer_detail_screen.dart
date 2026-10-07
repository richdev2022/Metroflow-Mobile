import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../models/transfer.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';
import '../utils/logger.dart';
import '../widgets/dispute_sheet.dart';

/// ---------------------------------------------------------------------------
/// Transaction Receipt — fully revamped.
///
///  - Gradient hero with the amount, a Credit/Debit type chip and a status chip
///  - Bank CODE resolved into the actual BANK NAME (GET /transfers/banks)
///  - Clean sections (no internal source/sourceId/walletId noise)
///  - Actions: Share receipt (PNG), Download receipt (PNG), Repeat
///    transaction (prefilled transfer form), Dispute transaction (end-to-end)
///  - "Processing" receipts get a one-tap provider re-verify
/// ---------------------------------------------------------------------------
class TransferDetailScreen extends StatefulWidget {
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
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year} • '
          '$hour12:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return date.isEmpty ? 'N/A' : date;
    }
  }

  @override
  State<TransferDetailScreen> createState() => _TransferDetailScreenState();
}

class _TransferDetailScreenState extends State<TransferDetailScreen> {
  final GlobalKey _receiptKey = GlobalKey();
  Map<String, String>? _bankNames; // code -> name
  String _status = '';
  bool _verifying = false;
  bool _reversing = false;

  @override
  void initState() {
    super.initState();
    _status = widget.transfer.status;
    _loadBanks();
    if (_isIndeterminate(_status)) _autoVerify();
  }

  static bool _isIndeterminate(String status) =>
      ['pending', 'processing', 'queued'].contains(status.toLowerCase());

  Future<void> _loadBanks() async {
    try {
      final response = await ApiService().getBanks();
      final list = response.data?['data'];
      if (list is List && mounted) {
        setState(() {
          _bankNames = {
            for (final b in list.whereType<Map>())
              (b['code'] ?? '').toString(): (b['name'] ?? '').toString(),
          };
        });
      }
    } catch (_) {
      // Non-fatal: fall back to bank name/code already on the record.
    }
  }

  String get _bankLabel {
    final t = widget.transfer;
    final code = (t.recipientBank ?? '').trim();
    final storedName = (t.recipientBankName ?? '').trim();
    if (storedName.isNotEmpty && storedName.toLowerCase() != code.toLowerCase()) {
      return storedName;
    }
    final mapped = _bankNames?[code];
    if (mapped != null && mapped.isNotEmpty) return mapped;
    return code.isEmpty ? 'N/A' : code;
  }

  /// One-tap provider re-verify for receipts still sitting on "Processing".
  Future<void> _autoVerify({bool silent = true}) async {
    final t = widget.transfer;
    if (t.id.isEmpty) return;
    if (!silent) setState(() => _verifying = true);
    try {
      final response = await ApiService().verifyTransfer(t.id);
      final data = response.data;
      final updated = data is Map
          ? (data['data'] is Map ? data['data'] as Map : null)
          : null;
      final newStatus = (updated?['status'] ?? '').toString();
      if (newStatus.isNotEmpty && mounted && newStatus != _status) {
        setState(() => _status = newStatus);
      }
    } catch (e) {
      if (!silent) Logger.error('Verify transfer failed: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  /// Customer-triggered self-heal: the transfer is FAILED but the money has
  /// not visibly come back (e.g. the failure webhook arrived while the server
  /// ran an older build). Idempotent server-side — safe to tap repeatedly.
  Future<void> _forceReversal() async {
    if (_reversing) return;
    setState(() => _reversing = true);
    try {
      final id = widget.transfer.id.isNotEmpty ? widget.transfer.id : widget.transfer.reference;
      final response = await ApiService().forceTransferReversal(id);
      final data = response.data;
      final ok = data is Map && data['success'] == true;
      final message = (data is Map ? data['message'] ?? data['error'] : null)?.toString() ??
          (ok ? 'Reversal completed' : 'Reversal failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        // Diagnose instead of a bare "Something went wrong": a silent
        // timeout / dead connection gets an explicit, actionable message.
        String message = ApiService.extractErrorMessage(e);
        if (e is DioException && message == 'Something went wrong') {
          switch (e.type) {
            case DioExceptionType.connectionTimeout:
            case DioExceptionType.sendTimeout:
            case DioExceptionType.receiveTimeout:
              message = 'The reversal request timed out. The refund usually lands anyway — check your balance in a moment, then tap "Reverse now" again if the money is still missing.';
              break;
            case DioExceptionType.connectionError:
              message = 'No connection to the server. Check your internet and tap "Reverse now" again.';
              break;
            default:
              message = 'Reversal failed (${e.response?.statusCode ?? e.type.name}). Try again, or use Dispute below.';
          }
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } finally {
      if (mounted) setState(() => _reversing = false);
    }
  }

  Future<Uint8List?> _captureReceipt() async {
    try {
      final boundary = _receiptKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (e) {
      Logger.error('Receipt capture failed: $e');
      return null;
    }
  }

  Future<void> _shareReceipt({required bool download}) async {
    final bytes = await _captureReceipt();
    if (!mounted) return;
    if (bytes == null) {
      // Fallback: share a plain-text receipt.
      final t = widget.transfer;
      await SharePlus.instance.share(ShareParams(
        text: 'Metricorex ${t.typeLabel} Receipt\n'
            'Amount: ${TransferDetailScreen.formatAmount(t)}\n'
            'Status: ${_status.toUpperCase()}\n'
            'To: ${t.recipientName} (${t.recipientAccount ?? ''}, $_bankLabel)\n'
            'Reference: ${t.reference}\n'
            'Date: ${TransferDetailScreen.formatDate(t.createdAt)}',
        subject: 'Transaction Receipt — ${t.reference}',
      ));
      return;
    }
    final t = widget.transfer;
    final safeRef = t.reference.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final file = File(
      '${Directory.systemTemp.path}/metricorex-receipt-$safeRef.png',
    );
    await file.writeAsBytes(bytes);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: 'image/png')],
      text: download
          ? 'Transaction receipt for ${t.reference}'
          : 'Metricorex ${t.typeLabel} receipt — ${TransferDetailScreen.formatAmount(t)}',
      subject: 'Transaction Receipt — ${t.reference}',
    ));
  }

  void _repeatTransaction() {
    final t = widget.transfer;
    context.push('/main/single-transfer', extra: {
      'bank_code': t.recipientBank ?? '',
      'account_number': t.recipientAccount ?? '',
      'account_name': t.recipientName,
      'amount': t.amount > 0 ? t.amount.toStringAsFixed(0) : '',
      'remark': t.remark ?? '',
    });
  }

  void _openDispute() {
    final t = widget.transfer;
    // Disputes are now allowed on FAILED transfers too: if the automatic
    // reversal ever fails, the customer must still be able to reach support
    // (the sheet pre-selects "Failed transfer" and the backend still only
    // accepts debit transactions). The banner below keeps pointing at the
    // faster self-service reversal.
    if (_status.toLowerCase() == 'failed') {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Failed transfers are reversed to your wallet automatically — if the amount has not arrived, file the dispute below and our team will step in.'),
      ));
    }
    DisputeSheet.show(
      context,
      reference: t.reference,
      amount: t.amount,
      currency: t.currency,
      initialCategory: _status.toLowerCase() == 'failed' ? 'failed_transfer' : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final status = _status.toLowerCase();

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Transaction Receipt',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _receiptKey,
                  child: Container(
                    color: colors.background,
                    padding: const EdgeInsets.all(4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _heroCard(colors, status),
                        const SizedBox(height: 14),
                        _partiesCard(colors),
                        const SizedBox(height: 14),
                        _detailsCard(colors),
                        if (widget.transfer.failureReason != null &&
                            widget.transfer.failureReason!.isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _failureCard(colors),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            _actionsBar(colors, status),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ hero

  Widget _heroCard(ThemeColors colors, String status) {
    final isCredit = widget.transfer.isCredit;
    final typeColor = isCredit ? AppColors.success : AppColors.primary;
    final failed = status == 'failed';
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: failed
              ? [AppColors.error, const Color(0xFFB91C1C)]
              : [AppColors.primary, const Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: (failed ? AppColors.error : AppColors.primary)
                .withValues(alpha: 0.28),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            TransferDetailScreen.formatAmount(widget.transfer),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pill(
                label: widget.transfer.typeLabel.toUpperCase(),
                color: Colors.white,
                background: Colors.white.withValues(alpha: 0.22),
              ),
              const SizedBox(width: 8),
              _pill(
                label: _status.toUpperCase(),
                color: Colors.white,
                background: Colors.black.withValues(alpha: 0.18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            TransferDetailScreen.formatDate(widget.transfer.createdAt),
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.white.withValues(alpha: 0.85),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill({
    required String label,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
          color: color,
        ),
      ),
    );
  }

  // -------------------------------------------------------------- parties

  Widget _partiesCard(ThemeColors colors) {
    final t = widget.transfer;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('From',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: colors.textSecondary)),
                const SizedBox(height: 6),
                Text('Metricorex Wallet',
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: colors.text),
                    overflow: TextOverflow.ellipsis),
                Text('Wallet ${(t.walletId ?? '').isEmpty ? '' : '••••'}',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary)),
              ],
            ),
          ),
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(t.isCredit ? Icons.south_west_rounded : Icons.east_rounded,
                size: 18, color: colors.primary),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('To',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: colors.textSecondary)),
                const SizedBox(height: 6),
                Text(
                  t.recipientName.isNotEmpty ? t.recipientName : 'Recipient',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: colors.text),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${t.recipientAccount ?? '—'} • $_bankLabel',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------- details

  Widget _detailsCard(ThemeColors colors) {
    final t = widget.transfer;
    final rows = <_DetailRow>[
      _DetailRow(
        'Reference',
        t.reference,
        trailing: IconButton(
          icon: const Icon(Icons.copy_rounded, size: 16),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: t.reference));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Reference copied')),
              );
            }
          },
        ),
      ),
      _DetailRow('Type', t.typeLabel),
      if (t.remark != null && t.remark!.isNotEmpty)
        _DetailRow('Remark', t.remark),
      _DetailRow(
          'Fee', '${t.currency} ${t.fee.toStringAsFixed(2)}'),
      // Payout provider intentionally hidden from customers.
      _DetailRow('Date', TransferDetailScreen.formatDate(t.createdAt)),
      _DetailRow('Status', _status.toUpperCase()),
    ];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transaction details',
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: colors.text)),
          const SizedBox(height: 8),
          ...rows.map((row) => _detailLine(context, colors, row)),
        ],
      ),
    );
  }

  Widget _failureCard(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: AppColors.error, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '${widget.transfer.failureReason}\nThe full amount (including the fee) is returned to your wallet automatically.',
              style: TextStyle(
                  fontSize: 12.5, height: 1.45, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailLine(BuildContext context, ThemeColors colors, _DetailRow row) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(row.label,
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              row.value == null || row.value!.isEmpty
                  ? 'N/A'
                  : row.value!,
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: colors.text,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),
          if (row.trailing != null) ...[
            const SizedBox(width: 6),
            row.trailing!,
          ],
        ],
      ),
    );
  }

  // --------------------------------------------------------------- actions

  Widget _actionsBar(ThemeColors colors, String status) {
    final indeterminate = _isIndeterminate(status);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (indeterminate)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: OutlinedButton.icon(
                  onPressed:
                      _verifying ? null : () => _autoVerify(silent: false),
                  icon: _verifying
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary))
                      : const Icon(Icons.refresh_rounded, size: 18),
                  label: Text(_verifying
                      ? 'Checking with the bank…'
                      : 'Still processing? Check status'),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    colors,
                    icon: Icons.ios_share_rounded,
                    label: 'Share',
                    onTap: () => _shareReceipt(download: false),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    colors,
                    icon: Icons.download_rounded,
                    label: 'Download',
                    onTap: () => _shareReceipt(download: true),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_status.toLowerCase() == 'failed') ...[
              OutlinedButton.icon(
                onPressed: _reversing ? null : _forceReversal,
                icon: _reversing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary))
                    : const Icon(Icons.currency_exchange_rounded, size: 18),
                label: Text(_reversing
                    ? 'Reversing…'
                    : 'Money not back yet? Reverse now'),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: _actionButton(
                    colors,
                    icon: Icons.replay_rounded,
                    label: 'Repeat',
                    primary: true,
                    onTap: _repeatTransaction,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _actionButton(
                    colors,
                    icon: Icons.report_problem_rounded,
                    label: 'Dispute',
                    danger: true,
                    onTap: _openDispute,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    ThemeColors colors, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
    bool danger = false,
  }) {
    final fg = danger
        ? AppColors.error
        : primary
            ? Colors.white
            : colors.text;
    return Material(
      color: primary
          ? AppColors.primary
          : danger
              ? AppColors.error.withValues(alpha: 0.08)
              : colors.textSecondary.withValues(alpha: 0.06),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(label,
                  style: TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w800, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow {
  const _DetailRow(this.label, this.value, {this.trailing});

  final String label;
  final String? value;
  final Widget? trailing;
}
