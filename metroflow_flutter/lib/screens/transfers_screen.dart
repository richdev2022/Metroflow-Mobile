// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/transfer.dart';
import '../utils/app_timezone.dart';
import '../widgets/pin_setup_sheet.dart';
import 'package:share_plus/share_plus.dart';

class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key});

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Transfer> _transfers = [];
  String _filterStatus = 'all';
  String _searchQuery = '';
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  Timer? _searchDebounce;

  /// Transaction PIN gate — auto-prompted at most ONCE per app session
  /// (shared across instances of this screen; dismissal never loops).
  static bool _pinPromptShownThisSession = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _fetchTransfers(1, refresh: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensurePinSetup());
  }

  /// Checks GET /settings/otp-enabled; when no PIN exists yet, shows the
  /// setup sheet once (silent on failure — never blocks the screen).
  Future<void> _ensurePinSetup() async {
    if (_pinPromptShownThisSession) return;
    _pinPromptShownThisSession = true;
    try {
      final response = await ApiService().getOtpEnabled();
      final data = response.data;
      final pinCreated = data is Map && data['pinCreated'] == true;
      if (!mounted || pinCreated) return;
      await showPinSetupSheet(context);
    } catch (e) {
      debugPrint('PIN status check failed: $e');
    }
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TransfersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget != widget) {
      _fetchTransfers(1, refresh: true);
    }
  }

  Future<void> _fetchTransfers(int page, {bool refresh = false}) async {
    if (!refresh && (!_hasMore || _isLoadingMore)) return;

    setState(() {
      if (refresh) {
        _isLoading = _transfers.isEmpty;
      } else if (page > 1) {
        _isLoadingMore = true;
      } else {
        _isLoading = true;
      }
    });

    try {
      final api = ApiService();
      final params = <String, dynamic>{
        'page': page,
        'limit': 20,
      };
      if (_filterStatus != 'all') params['status'] = _filterStatus;
      if (_searchQuery.isNotEmpty) params['search'] = _searchQuery;

      final response = await api.getTransfers(params: params);
      if (response.data['success'] == true) {
        final data = response.data['data'] as List<dynamic>? ?? [];
        final newTransfers = data
            .map((e) => Transfer.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() {
          if (refresh) {
            _transfers = newTransfers;
          } else {
            _transfers = [..._transfers, ...newTransfers];
          }
          final pagination = response.data['pagination'] as Map<String, dynamic>?;
          final totalPages = pagination?['totalPages'] as int?;
          _hasMore = totalPages != null ? page < totalPages : newTransfers.length == 20;
          _page = page;
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch transfers: $e');
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _handleRefresh() async {
    await _fetchTransfers(1, refresh: true);
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _fetchTransfers(_page + 1);
    }
  }

  Future<void> _handleRetryTransfer(String id) async {
    try {
      final api = ApiService();
      await api.retryTransfer(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Transfer retry initiated')),
        );
      }
      await _fetchTransfers(1, refresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to retry transfer: ${e.toString()}')),
        );
      }
    }
  }

  /// "Reverse Now" — pull the money for a FAILED transfer straight back into
  /// the wallet (POST /transfers/:id/force-reversal, id-or-reference,
  /// idempotent server-side). Honest errors (already reversed / nothing to
  /// reverse) are surfaced verbatim.
  Future<void> _handleReverseTransfer(Transfer transfer) async {
    try {
      final api = ApiService();
      final id = transfer.id.isNotEmpty ? transfer.id : transfer.reference;
      final response = await api.forceTransferReversal(id);
      final data = response.data;
      final ok = data is Map && data['success'] == true;
      final message = (data is Map ? data['message'] ?? data['error'] : null)
              ?.toString() ??
          (ok ? 'Reversal completed' : 'Reversal failed');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
      await _fetchTransfers(1, refresh: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _exportToCsv() async {
    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final params = <String, dynamic>{};
      if (_filterStatus != 'all') params['status'] = _filterStatus;

      final response = await api.exportSubscriptionTransactions(params: params);
      final data = response.data?.toString() ?? '';
      if (data.isNotEmpty) {
        await SharePlus.instance.share(
          ShareParams(
            text: data,
            subject: 'Transfer History',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to export transfers: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }



  /// Entry point: choose between the single (individual) transfer flow and
  /// the bulk transfer flow.
  void _showNewTransferSheet() {
    final colors = AppTheme.colors;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Make New Transfer',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose how you want to send money',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _transferOptionCard(
                    colors,
                    icon: Icons.person_rounded,
                    title: 'Individual Transfer',
                    subtitle: 'Send to one account',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/single-transfer');
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _transferOptionCard(
                    colors,
                    icon: Icons.group_rounded,
                    title: 'Bulk Transfer',
                    subtitle: 'Send to multiple accounts',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      context.push('/main/bulk-transfer');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _transferOptionCard(
    ThemeColors colors, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primaryBg,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: colors.primary, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.text,
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    // Primary-blue app bar (same treatment as the main shell) so the status
    // bar area is blue with light icons — network/battery stay visible. The
    // previous white surface header rendered a white status bar on top.
    return Scaffold(
      appBar: AppBar(
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
        title: const Text(
          'Transfers',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Export statement',
            onPressed: _isLoading ? null : _exportToCsv,
          ),
        ],
      ),
      body: Column(
          children: [
            // Prominent entry point: start a new individual or bulk transfer.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.primary, colors.primaryDark],
                    ),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: colors.primary.withValues(alpha: 0.3),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: _showNewTransferSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.add_circle_outline, size: 22),
                    label: const Text(
                      'Make New Transfer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: colors.surfaceVariant,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.search_outlined, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText: 'Search transfers...',
                          hintStyle: TextStyle(color: colors.textSecondary),
                          border: InputBorder.none,
                        ),
                        style: TextStyle(color: colors.text, fontSize: 16),
                        onChanged: (value) {
                          setState(() => _searchQuery = value);
                          _searchDebounce?.cancel();
                          _searchDebounce = Timer(const Duration(milliseconds: 450), () {
                            _fetchTransfers(1, refresh: true);
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: colors.surface,
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: ['all', 'pending', 'success', 'failed'].map((status) {
                  final isSelected = _filterStatus == status;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _filterStatus = status);
                        _fetchTransfers(1, refresh: true);
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(
                          color: isSelected ? colors.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            status == 'all' ? 'All' : status[0].toUpperCase() + status.substring(1),
                            style: TextStyle(
                              fontSize: 14,
                              color: isSelected ? Colors.white : colors.textSecondary,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            Expanded(
              child: _buildTransferList(colors),
            ),
          ],
      ),
    );
  }

  Widget _buildTransferList(ThemeColors colors) {
    if (_isLoading && _transfers.isEmpty) {
      return Center(child: CircularProgressIndicator(color: colors.primary));
    }

    if (_transfers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz_outlined, size: 64, color: colors.textSecondary),
            const SizedBox(height: 16),
            Text(
              'No transfers found',
              style: TextStyle(fontSize: 16, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _handleRefresh,
      color: colors.primary,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: _transfers.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _transfers.length) {
            return Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(color: colors.primary)),
            );
          }
          final transfer = _transfers[index];
          return _TransferCard(
            transfer: transfer,
            onTap: () => context.push('/main/transfer-detail', extra: transfer),
            onRetry: transfer.status == 'failed' ? () => _handleRetryTransfer(transfer.id) : null,
            onReverse: transfer.status == 'failed' ? () => _handleReverseTransfer(transfer) : null,
          );
        },
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  final Transfer transfer;
  final VoidCallback onTap;
  final VoidCallback? onRetry;
  final VoidCallback? onReverse;

  const _TransferCard({required this.transfer, required this.onTap, this.onRetry, this.onReverse});

  static Color getStatusColor(String status, ThemeColors colors) {
    switch (status) {
      case 'success':
        return colors.success;
      case 'pending':
        return colors.warning;
      case 'failed':
        return colors.error;
      default:
        return colors.primary;
    }
  }

  static Color getStatusBg(String status, ThemeColors colors) {
    final base = getStatusColor(status, colors);
    return base.withValues(alpha: 0.1);
  }

  static String formatDate(String date) {
    final dt = AppTimezone.tryParse(date);
    if (dt == null) return date;
    return AppTimezone.instance.formatDateTime(dt);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final status = transfer.status.toLowerCase();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
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
                  transfer.recipientName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colors.text,
                  ),
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _TransferCard.getStatusBg(status, colors),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      transfer.status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _TransferCard.getStatusColor(status, colors),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.chevron_right, color: colors.textSecondary, size: 20),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${transfer.currency} ${transfer.amount.toStringAsFixed(0).replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]},')}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colors.primary,
                ),
              ),
              Text(
                _TransferCard.formatDate(transfer.createdAt),
                style: TextStyle(fontSize: 14, color: colors.textSecondary),
              ),
            ],
          ),
          if (transfer.status == 'failed' && transfer.failureReason != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      transfer.failureReason!,
                      style: TextStyle(fontSize: 14, color: colors.error),
                    ),
                  ),
                  if (onRetry != null)
                    TextButton(
                      onPressed: onRetry,
                      style: TextButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Text('Retry', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  if (onReverse != null) ...[
                    const SizedBox(width: 6),
                    TextButton(
                      onPressed: onReverse,
                      style: TextButton.styleFrom(
                        backgroundColor: colors.error,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      ),
                      child: const Text('Reverse Now', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
