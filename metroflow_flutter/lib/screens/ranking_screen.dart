import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../models/team_member.dart';
import '../services/api.dart';
import '../theme/app_theme.dart';

class RankingScreen extends StatefulWidget {
  const RankingScreen({super.key});

  @override
  State<RankingScreen> createState() => _RankingScreenState();
}

class _RankingScreenState extends State<RankingScreen> {
  bool _isLoading = true;
  String? _error;
  List<_RankingEntry> _rankings = [];

  @override
  void initState() {
    super.initState();
    _fetchRankings();
  }

  Future<void> _fetchRankings() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getTasks(params: {'limit': 10000}),
        api.getTeam(),
      ]);

      final tasks = _extractTasks(results[0].data);
      final members = _extractMembers(results[1].data);
      final entries = _buildRankings(members, tasks);

      if (mounted) {
        setState(() => _rankings = entries);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Unable to load team rankings. Please try again.');
      }
      debugPrint('Failed to fetch rankings: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> _extractTasks(dynamic data) {
    if (data is! Map) return const [];
    final root = data['data'];
    final tasks = root is Map ? root['tasks'] : root;
    if (tasks is! List) return const [];
    return tasks.whereType<Map>().map((task) => Map<String, dynamic>.from(task)).toList();
  }

  List<TeamMember> _extractMembers(dynamic data) {
    if (data is! Map || data['success'] != true || data['data'] is! List) {
      return const [];
    }
    return (data['data'] as List)
        .whereType<Map>()
        .map((member) => TeamMember.fromJson(Map<String, dynamic>.from(member)))
        .toList();
  }

  List<_RankingEntry> _buildRankings(List<TeamMember> members, List<Map<String, dynamic>> tasks) {
    final stats = <String, _RankingStats>{
      for (final member in members) member.id: _RankingStats(),
    };

    for (final task in tasks) {
      final assignedTo = task['assignedTo'];
      if (assignedTo is! List) continue;

      for (final assigneeId in assignedTo) {
        final assigneeStats = stats[assigneeId.toString()];
        if (assigneeStats == null) continue;
        assigneeStats.assigned += 1;
        if (task['status']?.toString().toLowerCase() == 'completed') {
          assigneeStats.completed += 1;
        }
      }
    }

    final entries = members.map((member) {
      final memberStats = stats[member.id] ?? _RankingStats();
      return _RankingEntry(
        member: member,
        assigned: memberStats.assigned,
        completed: memberStats.completed,
      );
    }).toList();

    entries.sort((a, b) {
      final rateCompare = b.completionRate.compareTo(a.completionRate);
      if (rateCompare != 0) return rateCompare;
      final completedCompare = b.completed.compareTo(a.completed);
      if (completedCompare != 0) return completedCompare;
      return b.assigned.compareTo(a.assigned);
    });

    return entries;
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        title: const Text('Team Rankings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/main');
            }
          },
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchRankings,
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: colors.primary))
            : _error != null
                ? _RankingError(message: _error!, onRetry: _fetchRankings)
                : RefreshIndicator(
                    onRefresh: _fetchRankings,
                    child: _rankings.isEmpty
                        ? ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              _EmptyRankings(colors: colors),
                            ],
                          )
                        : ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              Text(
                                'Performance ranking based on task completion rates',
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(height: 20),
                              ...List.generate(_rankings.length, (index) {
                                return _RankingCard(
                                  rank: index + 1,
                                  entry: _rankings[index],
                                  colors: colors,
                                );
                              }),
                            ],
                          ),
                  ),
      ),
    );
  }
}

class _RankingStats {
  int assigned = 0;
  int completed = 0;
}

class _RankingEntry {
  final TeamMember member;
  final int assigned;
  final int completed;

  const _RankingEntry({
    required this.member,
    required this.assigned,
    required this.completed,
  });

  double get completionRate => assigned == 0 ? 0 : (completed / assigned) * 100;
}

class _RankingCard extends StatelessWidget {
  final int rank;
  final _RankingEntry entry;
  final ThemeColors colors;

  const _RankingCard({
    required this.rank,
    required this.entry,
    required this.colors,
  });

  IconData get _rankIcon {
    if (rank <= 3) return Icons.emoji_events_outlined;
    return Icons.format_list_numbered;
  }

  Color get _rankColor {
    switch (rank) {
      case 1:
        return const Color(0xFFFFC107);
      case 2:
        return const Color(0xFF94A3B8);
      case 3:
        return const Color(0xFFF59E0B);
      default:
        return colors.textSecondary;
    }
  }

  String get _initials {
    final parts = entry.member.name.trim().split(RegExp(r'\s+')).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '--';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final rate = entry.completionRate;
    final progress = (rate / 100).clamp(0.0, 1.0).toDouble();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 36,
                child: rank <= 3
                    ? Icon(_rankIcon, color: _rankColor, size: 30)
                    : Text(
                        '$rank',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              CircleAvatar(
                radius: 22,
                backgroundColor: colors.primary.withValues(alpha: 0.14),
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: colors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.member.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.member.role,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: rate > 0 ? AppColors.success.withValues(alpha: 0.14) : AppColors.error.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${rate.toStringAsFixed(1)}%',
                  style: TextStyle(
                    color: rate > 0 ? AppColors.success : AppColors.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colors.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                rank == 1 ? colors.primary : colors.primary.withValues(alpha: 0.72),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RankingMetric(
                  label: 'Assigned',
                  value: entry.assigned.toString(),
                  colors: colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RankingMetric(
                  label: 'Completed',
                  value: entry.completed.toString(),
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RankingMetric extends StatelessWidget {
  final String label;
  final String value;
  final ThemeColors colors;

  const _RankingMetric({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _RankingError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _RankingError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.error, size: 48),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyRankings extends StatelessWidget {
  final ThemeColors colors;

  const _EmptyRankings({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        children: [
          Icon(Icons.leaderboard_outlined, color: colors.textSecondary, size: 48),
          const SizedBox(height: 12),
          Text(
            'No ranking data yet',
            style: TextStyle(
              color: colors.text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Invite team members and assign tasks to start building the leaderboard.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}
