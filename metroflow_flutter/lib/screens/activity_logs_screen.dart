import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class ActivityLogsScreen extends StatefulWidget {
  const ActivityLogsScreen({super.key});

  @override
  State<ActivityLogsScreen> createState() => _ActivityLogsScreenState();
}

class _ActivityLogsScreenState extends State<ActivityLogsScreen> {
  final ScrollController _scrollController = ScrollController();
  List<dynamic> _logs = [];
  bool _isLoading = true;
  bool _hasMore = true;
  bool _isLoadingMore = false;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    _fetchLogs(1, refresh: true);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _fetchLogs(int pageNumber, {bool refresh = false}) async {
    if (!refresh && (!_hasMore || _isLoadingMore)) return;

    setState(() {
      if (refresh) {
        _isLoading = _logs.isEmpty;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      final api = ApiService();
      final response = await api.getActivityLogs(page: pageNumber, limit: 20);

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          final newLogs = data['data']['logs'] ?? [];
          setState(() {
            if (refresh) {
              _logs = newLogs;
            } else {
              _logs = [..._logs, ...newLogs];
            }
            _hasMore = newLogs.length == 20;
            _page = pageNumber;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch logs: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _fetchLogs(_page + 1);
    }
  }

  IconData _getActionIcon(String actionType) {
    final type = actionType.toLowerCase();
    if (type.contains('task')) return Icons.list_alt_outlined;
    if (type.contains('wallet') || type.contains('transfer')) return Icons.account_balance_wallet_outlined;
    if (type.contains('user') || type.contains('team')) return Icons.people_outline;
    if (type.contains('auth') || type.contains('login')) return Icons.lock_outlined;
    return Icons.flash_on_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _fetchLogs(1, refresh: true),
                      child: _logs.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                              itemCount: _logs.length + (_isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index == _logs.length) {
                                  return const Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(16.0),
                                      child: CircularProgressIndicator(),
                                    ),
                                  );
                                }
                                final log = _logs[index];
                                return _LogCard(log: log, icon: _getActionIcon(log['actionType'] ?? ''));
                              },
                            ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/main'),
          ),
          const Text(
            'Activity Logs',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: AppTheme.colors.textSecondary),
          const SizedBox(height: 16),
          Text(
            'No activities recorded yet',
            style: TextStyle(color: AppTheme.colors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  final dynamic log;
  final IconData icon;

  const _LogCard({required this.log, required this.icon});

  @override
  Widget build(BuildContext context) {
    final createdAt = log['createdAt'] ?? '';
    final dateStr = createdAt.isNotEmpty
        ? DateTime.tryParse(createdAt)?.toLocal().toString().split('.')[0] ?? createdAt
        : '';

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.colors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryBg,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(icon, size: 20, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      (log['action'] ?? '').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  log['description'] ?? '',
                  style: const TextStyle(fontSize: 15, height: 1.3),
                ),
                if ((log['taskTitle'] ?? '').toString().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.colors.surfaceVariant,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.description_outlined, size: 12, color: AppTheme.colors.textSecondary),
                        const SizedBox(width: 4),
                        Text(
                          log['taskTitle'] ?? '',
                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'By ${log['userName'] ?? 'Unknown'}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
