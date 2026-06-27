// ignore_for_file: prefer_const_constructors

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/transfer.dart';
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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _fetchTransfers(1, refresh: true);
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



  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

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
                    onPressed: () => context.pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Transfers',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colors.text,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.download_outlined, color: colors.primary),
                    onPressed: _isLoading ? null : _exportToCsv,
                  ),
                ],
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

  const _TransferCard({required this.transfer, required this.onTap, this.onRetry});

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
    try {
      final dt = DateTime.parse(date);
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return date;
    }
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
