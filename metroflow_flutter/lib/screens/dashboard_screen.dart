import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/team_member.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/app_timezone.dart';
import '../widgets/modern_ui.dart';
import '../widgets/avatar_with_initials.dart';
import 'package:fl_chart/fl_chart.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _allTasks = [];
  List<TeamMember> _teamMembers = [];
  List<dynamic> _epics = [];
  bool _isLoading = true;
  String _selectedMember = 'all';
  String _selectedEpic = 'all';
  String _startDate = '';
  String _endDate = '';

  List<dynamic> get _filteredTasks {
    return _allTasks.where((task) {
      // Filter by member
      bool matchesMember = true;
      if (_selectedMember != 'all') {
        final assignedTo = task['assignedTo'] as List?;
        matchesMember = assignedTo?.contains(_selectedMember) ?? false;
      }

      // Filter by epic
      bool matchesEpic = true;
      if (_selectedEpic != 'all') {
        final taskEpicId = task['epicId']?.toString();
        matchesEpic = taskEpicId == _selectedEpic;
      }

      // Filter by start date
      bool matchesStartDate = true;
      if (_startDate.isNotEmpty) {
        final taskDateStr = task['startDate'] as String? ?? task['dueDate'] as String? ?? task['endDate'] as String?;
        if (taskDateStr != null) {
          try {
            final taskDate = DateTime.parse(taskDateStr);
            final filterStartDate = DateTime.parse(_startDate);
            matchesStartDate = taskDate.isAfter(filterStartDate.subtract(const Duration(days: 1)));
          } catch (e) {
            matchesStartDate = false;
          }
        } else {
          matchesStartDate = false;
        }
      }

      // Filter by end date
      bool matchesEndDate = true;
      if (_endDate.isNotEmpty) {
        final taskDateStr = task['endDate'] as String? ?? task['dueDate'] as String? ?? task['startDate'] as String?;
        if (taskDateStr != null) {
          try {
            final taskDate = DateTime.parse(taskDateStr);
            final filterEndDate = DateTime.parse(_endDate);
            matchesEndDate = taskDate.isBefore(filterEndDate.add(const Duration(days: 1)));
          } catch (e) {
            matchesEndDate = false;
          }
        } else {
          matchesEndDate = false;
        }
      }

      return matchesMember && matchesEpic && matchesStartDate && matchesEndDate;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Warm the shared user profile (name/avatar) from the local cache and,
    // best-effort, from the server — used by the greeting + avatar chip.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(userProfileProvider.notifier).hydrate();
      ref.read(userProfileProvider.notifier).refreshFromServer();
    });
  }

  Future<void> _fetchData([bool showLoader = true]) async {
    if (showLoader) {
      setState(() => _isLoading = true);
    }
    try {
      final api = ApiService();

      // Fetch ALL tasks without filters, we'll filter locally
      final tasksParams = <String, dynamic>{'limit': '10000'};

      final tasksResponse = await api.getTasks(params: tasksParams);
      final teamResponse = await api.getTeam();
      final epicsResponse = await api.getEpics();

      if (mounted) {
        setState(() {
          if (tasksResponse.data != null && tasksResponse.data['success'] == true) {
            _allTasks = tasksResponse.data['data']['tasks'] ?? [];
          }
          if (teamResponse.data != null && teamResponse.data['success'] == true) {
            _teamMembers = (teamResponse.data['data'] as List?)
                    ?.map((e) {
                      try {
                        return TeamMember.fromJson(e as Map<String, dynamic>);
                      } catch (e) {
                        return null;
                      }
                    })
                    .whereType<TeamMember>()
                    .toList() ??
                [];
          }
          if (epicsResponse.data != null && epicsResponse.data['success'] == true) {
            _epics = epicsResponse.data['data'] ?? [];
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch dashboard data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearFilters() {
    setState(() {
      _selectedMember = 'all';
      _selectedEpic = 'all';
      _startDate = '';
      _endDate = '';
    });
  }

  Future<void> _selectStartDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _startDate.isNotEmpty ? DateTime.parse(_startDate) : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _startDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  Future<void> _selectEndDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _endDate.isNotEmpty ? DateTime.parse(_endDate) : DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        _endDate = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  List<PieChartSectionData> _buildPieChartSections(
    ThemeColors colors,
    int totalTasks,
    int completedTasks,
    int inProgressTasks,
    int overdueTasks,
  ) {
    final pendingTasks = totalTasks - completedTasks - inProgressTasks - overdueTasks;
    if (totalTasks == 0) {
      return [
        PieChartSectionData(
          value: 1,
          color: colors.surfaceVariant,
          radius: 62,
          title: '',
        ),
      ];
    }
    return [
      PieChartSectionData(
        value: completedTasks.toDouble(),
        color: colors.success,
        radius: 62,
        title: '',
      ),
      PieChartSectionData(
        value: inProgressTasks.toDouble(),
        color: colors.warning,
        radius: 62,
        title: '',
      ),
      PieChartSectionData(
        value: overdueTasks.toDouble(),
        color: colors.error,
        radius: 62,
        title: '',
      ),
      PieChartSectionData(
        value: pendingTasks > 0 ? pendingTasks.toDouble() : 0,
        color: colors.textSecondary.withValues(alpha: 0.35),
        radius: 62,
        title: '',
      ),
    ];
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  /// Friendly display name for the greeting — the user's NAME, never the
  /// email. authProvider sometimes stores the email as a fallback, so a
  /// name-like string is derived from the email prefix in that case.
  String _displayName(AuthState authState, UserProfile profile) {
    final fromAuth = (authState.userName ?? '').trim();
    final candidate = fromAuth.isNotEmpty ? fromAuth : profile.name.trim();
    if (candidate.isEmpty) return 'there';
    if (candidate.contains('@')) {
      final prefix = candidate.split('@').first;
      final cleaned = prefix.replaceAll(RegExp(r'[._\-+0-9]+'), ' ').trim();
      if (cleaned.isEmpty) return 'there';
      return cleaned
          .split(RegExp(r'\s+'))
          .map((word) => word.isEmpty ? word : '${word[0].toUpperCase()}${word.substring(1)}')
          .join(' ');
    }
    return candidate;
  }

  bool _isTaskOverdue(dynamic task) {
    // If API provides isOverdue, use that
    if (task['isOverdue'] == true) return true;

    // Otherwise calculate from due date
    final dueDateStr = task['dueDate'] as String? ?? task['endDate'] as String?;
    if (dueDateStr == null) return false;

    try {
      final dueDate = DateTime.parse(dueDateStr);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      return dueDate.isBefore(today) && task['status'] != 'completed';
    } catch (e) {
      return false;
    }
  }

  String _taskDateLabel(dynamic task) {
    final dueDateStr = task['dueDate'] as String? ?? task['endDate'] as String? ?? '';
    if (dueDateStr.isEmpty) return 'No due date';
    try {
      return AppTimezone.instance.formatDateShort(DateTime.parse(dueDateStr));
    } catch (e) {
      return dueDateStr;
    }
  }

  int _dueTodayCount() {
    final todayKey = AppTimezone.instance.todayKey();
    return _filteredTasks.where((task) {
      if (task['status'] == 'completed') return false;
      final dateStr = task['dueDate'] as String? ?? task['endDate'] as String? ?? '';
      if (dateStr.isEmpty) return false;
      try {
        final dateKey = AppTimezone.instance.dateKeyIn(DateTime.parse(dateStr));
        return dateKey.year == todayKey.year &&
            dateKey.month == todayKey.month &&
            dateKey.day == todayKey.day;
      } catch (e) {
        return false;
      }
    }).length;
  }

  int _completedThisWeekCount() {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _filteredTasks.where((task) {
      if (task['status'] != 'completed') return false;
      final dateStr = task['updatedAt'] as String? ?? task['endDate'] as String? ?? task['dueDate'] as String? ?? '';
      if (dateStr.isEmpty) return false;
      try {
        return DateTime.parse(dateStr).isAfter(weekAgo);
      } catch (e) {
        return false;
      }
    }).length;
  }

  Color _statusColorFor(ThemeColors colors, dynamic task) {
    if (_isTaskOverdue(task)) return colors.error;
    switch (task['status'] as String?) {
      case 'completed':
        return colors.success;
      case 'in_progress':
        return colors.warning;
      default:
        return colors.primary;
    }
  }

  void _openTask(dynamic task) {
    try {
      context.go(
        '/main/task-detail',
        extra: Task.fromJson(Map<String, dynamic>.from(task)),
      );
    } catch (e) {
      debugPrint('Failed to open task: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return const SafeArea(child: _DashboardSkeleton());
    }

    final totalTasks = _filteredTasks.length;
    final completedTasks = _filteredTasks.where((t) => t['status'] == 'completed').length;
    final inProgressTasks = _filteredTasks.where((t) => t['status'] == 'in_progress').length;
    final overdueTasks = _filteredTasks.where(_isTaskOverdue).toList();
    final completionPercentage = totalTasks > 0 ? ((completedTasks / totalTasks) * 100).round() : 0;
    final openTasksCount = totalTasks - completedTasks;

    final Map<String, Map<String, int>> memberStats = {};
    for (var member in _teamMembers) {
      memberStats[member.id] = {'total': 0, 'completed': 0};
    }
    for (var task in _filteredTasks) {
      final assignedTo = task['assignedTo'] as List?;
      if (assignedTo != null) {
        for (var userId in assignedTo) {
          if (memberStats.containsKey(userId)) {
            memberStats[userId]!['total'] = (memberStats[userId]!['total'] ?? 0) + 1;
            if (task['status'] == 'completed') {
              memberStats[userId]!['completed'] = (memberStats[userId]!['completed'] ?? 0) + 1;
            }
          }
        }
      }
    }

    final sortedMembers = _teamMembers
        .where((m) => memberStats.containsKey(m.id) && memberStats[m.id]!['total']! > 0)
        .toList()
      ..sort((a, b) {
        final aRate = memberStats[a.id]!['total']! > 0
            ? memberStats[a.id]!['completed']! / memberStats[a.id]!['total']!
            : 0;
        final bRate = memberStats[b.id]!['total']! > 0
            ? memberStats[b.id]!['completed']! / memberStats[b.id]!['total']!
            : 0;
        return bRate.compareTo(aRate);
      });

    final openTasks = _filteredTasks.where((t) => t['status'] != 'completed').toList()
      ..sort((a, b) {
        final aDate = a['dueDate'] as String? ?? a['endDate'] as String? ?? '';
        final bDate = b['dueDate'] as String? ?? b['endDate'] as String? ?? '';
        if (aDate.isEmpty && bDate.isEmpty) return 0;
        if (aDate.isEmpty) return 1;
        if (bDate.isEmpty) return -1;
        try {
          return DateTime.parse(aDate).compareTo(DateTime.parse(bDate));
        } catch (e) {
          return 0;
        }
      });

    final authState = ref.watch(authProvider);
    final profile = ref.watch(userProfileProvider);
    final displayName = _displayName(authState, profile);
    final firstName = displayName.split(' ').first;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _fetchData(false),
        color: colors.primary,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ---------- Hero card (greeting + workspace overview) ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildHeroCard(
                  colors,
                  firstName,
                  openTasksCount,
                  completionPercentage,
                  overdueTasks.length,
                  profile,
                ),
              ),
              const SizedBox(height: 24),

              // ---------- Quick actions ----------
              _buildQuickActions(colors),
              const SizedBox(height: 24),

              // ---------- Stat grid ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _SectionKicker(label: 'Overview'),
                    const SizedBox(height: 10),
                    _buildStatGrid(colors),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ---------- Weekly activity ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _WeeklyActivityCard(colors: colors, tasks: _filteredTasks),
              ),
              const SizedBox(height: 24),

              // ---------- Filters ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildFiltersCard(colors),
              ),
              const SizedBox(height: 24),

              // ---------- My Tasks preview ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionKicker(
                      label: 'My Tasks',
                      subtitle: '$openTasksCount open of $totalTasks total',
                      actionLabel: 'View all',
                      onAction: () => context.go('/main?tab=1'),
                      actionIcon: Icons.arrow_forward_rounded,
                    ),
                    const SizedBox(height: 10),
                    if (openTasks.isEmpty)
                      ModernCard(
                        margin: EdgeInsets.zero,
                        child: EmptyState(
                          icon: Icons.task_alt_outlined,
                          title: 'You are all caught up!',
                          subtitle: 'No open tasks right now. Create a task to get things moving.',
                          actionLabel: 'New Task',
                          onAction: () => context.go('/main/create-task'),
                        ),
                      )
                    else
                      ...openTasks.take(3).map((task) {
                        return _MyTaskCard(
                          task: task,
                          colors: colors,
                          dateLabel: _taskDateLabel(task),
                          isOverdue: _isTaskOverdue(task),
                          statusColor: _statusColorFor(colors, task),
                          onTap: () => _openTask(task),
                        );
                      }),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ---------- Overdue banner ----------
              if (overdueTasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: _OverdueBanner(
                    count: overdueTasks.length,
                    colors: colors,
                    onTap: () => context.go('/main?tab=1'),
                  ),
                ),
              if (overdueTasks.isNotEmpty) const SizedBox(height: 24),

              // ---------- Task status breakdown ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildTaskStatusCard(
                  colors,
                  totalTasks,
                  completedTasks,
                  inProgressTasks,
                  overdueTasks.length,
                ),
              ),
              const SizedBox(height: 24),

              // ---------- Top members ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SectionKicker(
                      label: 'Top Members',
                      subtitle: 'Highest completion rate this period',
                      actionLabel: 'Full ranking',
                      onAction: () => context.go('/main/ranking'),
                      actionIcon: Icons.arrow_forward_rounded,
                    ),
                    const SizedBox(height: 10),
                    if (sortedMembers.isEmpty)
                      ModernCard(
                        margin: EdgeInsets.zero,
                        child: EmptyState(
                          icon: Icons.emoji_events_outlined,
                          title: 'No ranked members yet',
                          subtitle: 'Members appear here once tasks are assigned and completed.',
                          tint: const Color(0xFFF59E0B),
                        ),
                      )
                    else
                      ...List.generate(
                        sortedMembers.take(3).length,
                        (index) {
                          final member = sortedMembers[index];
                          final stats = memberStats[member.id]!;
                          final rate = stats['total']! > 0 ? ((stats['completed']! / stats['total']!) * 100).round() : 0;
                          return _TopMemberCard(
                            rank: index + 1,
                            member: member,
                            completionRate: rate,
                            completed: stats['completed']!,
                            total: stats['total']!,
                            colors: colors,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard(
    ThemeColors colors,
    String firstName,
    int openTasksCount,
    int completionPercentage,
    int overdueCount,
    UserProfile profile,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        // Brand-consistent deep indigo -> blue -> violet wash.
        gradient: const LinearGradient(
          colors: [
            Color(0xFF1E3A8A),
            Color(0xFF2563EB),
            Color(0xFF7C3AED),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          stops: [0.0, 0.55, 1.0],
        ),
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.35),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          children: [
            // Soft inner highlight sweeping from the top-left.
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(-0.7, -1.0),
                      radius: 1.3,
                      colors: [
                        Colors.white.withValues(alpha: 0.16),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.7],
                    ),
                  ),
                ),
              ),
            ),
            // Decorative circles.
            Positioned(
              right: -36,
              top: -36,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.10),
                ),
              ),
            ),
            Positioned(
              right: 42,
              bottom: -44,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Greeting + avatar chip (uses the user's picture, initials
                // as fallback — never the email).
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        '${_greeting()}, $firstName!',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 23,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 1.6,
                        ),
                      ),
                      child: AvatarWithInitials(
                        name: firstName == 'there' ? 'Me' : firstName,
                        imageUrl: profile.avatarUrl,
                        radius: 19,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  AppTimezone.instance.formatDateFull(DateTime.now()),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                Text(
                  "Here's what's happening today",
                  style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.white.withValues(alpha: 0.60),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.bolt_rounded, size: 14, color: Colors.amber.shade200),
                      const SizedBox(width: 4),
                      Text(
                        'Workspace overview',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.95),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '$openTasksCount',
                  style: const TextStyle(
                    fontSize: 44,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'open tasks in your workspace',
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: completionPercentage / 100,
                          minHeight: 8,
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '$completionPercentage% done',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                if (overdueCount > 0) ...[
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Icon(Icons.error_outline, size: 15, color: Colors.red.shade200),
                      const SizedBox(width: 6),
                      Text(
                        '$overdueCount overdue ${overdueCount == 1 ? 'task' : 'tasks'} need attention',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.red.shade100,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatGrid(ThemeColors colors) {
    final stats = <_DashboardStatData>[
      _DashboardStatData(
        icon: Icons.today_outlined,
        label: 'Due today',
        value: '${_dueTodayCount()}',
        tint: colors.primary,
        onTap: () => context.go('/main?tab=1'),
      ),
      _DashboardStatData(
        icon: Icons.task_alt_outlined,
        label: 'Done this week',
        value: '${_completedThisWeekCount()}',
        tint: colors.success,
        onTap: () => context.go('/main?tab=1'),
      ),
      _DashboardStatData(
        icon: Icons.error_outline,
        label: 'Overdue',
        value: '${_filteredTasks.where(_isTaskOverdue).length}',
        tint: colors.error,
        onTap: () => context.go('/main?tab=1'),
      ),
      _DashboardStatData(
        icon: Icons.groups_outlined,
        label: 'Team members',
        value: '${_teamMembers.length}',
        tint: const Color(0xFF7C3AED),
        onTap: () => context.go('/main/team'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth >= 560 ? 4 : 2;
        final cardWidth =
            (constraints.maxWidth - (crossAxisCount - 1) * 12) / crossAxisCount;
        final aspectRatio = cardWidth / 112;
        return GridView.count(
          crossAxisCount: crossAxisCount,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: aspectRatio,
          padding: EdgeInsets.zero,
          children: [
            for (final stat in stats) _DashboardStatCard(data: stat, colors: colors),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(ThemeColors colors) {
    final actions = <_QuickActionData>[
      _QuickActionData(
        icon: Icons.add_task_outlined,
        label: 'New Task',
        tint: colors.primary,
        onTap: () => context.go('/main/create-task'),
      ),
      _QuickActionData(
        icon: Icons.video_call_outlined,
        label: 'Start Meeting',
        tint: colors.success,
        onTap: () => context.go('/main?tab=3'),
      ),
      _QuickActionData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'New Chat',
        tint: const Color(0xFF7C3AED),
        onTap: () => context.go('/main?tab=2'),
      ),
      _QuickActionData(
        icon: Icons.archive_outlined,
        label: 'Backlog',
        tint: const Color(0xFF0891B2),
        onTap: () => context.go('/main/backlog'),
      ),
      _QuickActionData(
        icon: Icons.lightbulb_outlined,
        label: 'Ideas',
        tint: const Color(0xFFF59E0B),
        onTap: () => context.go('/main/ideas'),
      ),
      _QuickActionData(
        icon: Icons.receipt_long_outlined,
        label: 'Logs',
        tint: const Color(0xFFDB2777),
        onTap: () => context.go('/main/activity-logs'),
      ),
      _QuickActionData(
        icon: Icons.people_outlined,
        label: 'Team',
        tint: const Color(0xFF4F46E5),
        onTap: () => context.go('/main/team'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionKicker(label: 'Quick Actions'),
          const SizedBox(height: 10),
          SizedBox(
            height: 96,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: actions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final action = actions[index];
                return _QuickAction(data: action, colors: colors);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFiltersCard(ThemeColors colors) {
    return ModernCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              TintedCircleIcon(
                icon: Icons.tune_rounded,
                tint: colors.primary,
                size: 36,
                iconSize: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Filters',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
              ),
              if (_selectedMember != 'all' ||
                  _selectedEpic != 'all' ||
                  _startDate.isNotEmpty ||
                  _endDate.isNotEmpty)
                TextButton(
                  onPressed: _clearFilters,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    minimumSize: const Size(0, 32),
                  ),
                  child: const Text('Clear all'),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SearchableDropdown(
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Members'),
                    ),
                    ..._teamMembers.map((member) {
                      return DropdownMenuItem(
                        value: member.id,
                        child: Text(member.name),
                      );
                    }),
                  ],
                  value: _selectedMember,
                  onChanged: (value) {
                    setState(() => _selectedMember = value.toString());
                  },
                  colors: colors,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SearchableDropdown(
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('All Epics'),
                    ),
                    ..._epics.map((epic) {
                      return DropdownMenuItem(
                        value: epic['id'].toString(),
                        child: Text(epic['name'] as String),
                      );
                    }),
                  ],
                  value: _selectedEpic,
                  onChanged: (value) {
                    setState(() => _selectedEpic = value.toString());
                  },
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _DateButton(
                  date: _startDate,
                  placeholder: 'Start Date',
                  onTap: _selectStartDate,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 8),
              Text('to', style: TextStyle(color: colors.textSecondary)),
              const SizedBox(width: 8),
              Expanded(
                child: _DateButton(
                  date: _endDate,
                  placeholder: 'End Date',
                  onTap: _selectEndDate,
                  colors: colors,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTaskStatusCard(
    ThemeColors colors,
    int totalTasks,
    int completedTasks,
    int inProgressTasks,
    int overdueCount,
  ) {
    final pendingTasks = totalTasks - completedTasks - inProgressTasks - overdueCount;
    return ModernCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Task Status',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              SizedBox(
                width: 150,
                height: 150,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sections: _buildPieChartSections(
                          colors,
                          totalTasks,
                          completedTasks,
                          inProgressTasks,
                          overdueCount,
                        ),
                        borderData: FlBorderData(show: false),
                        sectionsSpace: 2,
                        centerSpaceRadius: 48,
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$totalTasks',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                            height: 1.1,
                          ),
                        ),
                        Text(
                          'tasks',
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _LegendItem(
                      color: colors.success,
                      label: 'Completed',
                      value: '$completedTasks',
                    ),
                    _LegendItem(
                      color: colors.warning,
                      label: 'In Progress',
                      value: '$inProgressTasks',
                    ),
                    _LegendItem(
                      color: colors.error,
                      label: 'Overdue',
                      value: '$overdueCount',
                    ),
                    _LegendItem(
                      color: colors.textSecondary,
                      label: 'Pending',
                      value: '$pendingTasks',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private widgets
// ---------------------------------------------------------------------------

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                ShimmerBox(width: 220, height: 26, radius: 8),
                SizedBox(height: 8),
                ShimmerBox(width: 150, height: 14, radius: 6),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: ShimmerBox(
              width: double.infinity,
              height: 190,
              radius: 24,
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: const [
                ShimmerBox(width: 96, height: 96, radius: 20),
                SizedBox(width: 12),
                ShimmerBox(width: 96, height: 96, radius: 20),
                SizedBox(width: 12),
                ShimmerBox(width: 96, height: 96, radius: 20),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: const [
                SkeletonCard(),
                SkeletonCard(),
                SkeletonCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionData {
  final IconData icon;
  final String label;
  final Color tint;
  final VoidCallback onTap;

  const _QuickActionData({
    required this.icon,
    required this.label,
    required this.tint,
    required this.onTap,
  });
}

class _QuickAction extends StatelessWidget {
  final _QuickActionData data;
  final ThemeColors colors;

  const _QuickAction({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: data.onTap,
      child: Container(
        width: 84,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.border),
          boxShadow: [
            BoxShadow(
              color: colors.text.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TintedCircleIcon(
              icon: data.icon,
              tint: data.tint,
              size: 38,
              iconSize: 19,
            ),
            const SizedBox(height: 8),
            Text(
              data.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyTaskCard extends StatelessWidget {
  final dynamic task;
  final ThemeColors colors;
  final String dateLabel;
  final bool isOverdue;
  final Color statusColor;
  final VoidCallback onTap;

  const _MyTaskCard({
    required this.task,
    required this.colors,
    required this.dateLabel,
    required this.isOverdue,
    required this.statusColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCompleted = task['status'] == 'completed';
    final epic = task['epic'] as String?;

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          // Priority / status color bar
          Container(
            width: 5,
            height: 68,
            decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  // Checkbox-style leading icon
                  Icon(
                    isCompleted
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked_rounded,
                    color: isCompleted ? colors.success : colors.borderVariant,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          task['title'] as String? ?? 'Untitled task',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: colors.text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if (epic != null && epic.isNotEmpty)
                              ModernBadge(
                                label: epic,
                                color: colors.primary,
                              ),
                            ModernBadge(
                              label: isOverdue ? 'Overdue · $dateLabel' : 'Due $dateLabel',
                              color: isOverdue ? colors.error : colors.textSecondary,
                              icon: Icons.schedule,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OverdueBanner extends StatelessWidget {
  final int count;
  final ThemeColors colors;
  final VoidCallback onTap;

  const _OverdueBanner({
    required this.count,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.error.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          children: [
            TintedCircleIcon(
              icon: Icons.warning_amber_rounded,
              tint: colors.error,
              size: 40,
              iconSize: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '$count overdue ${count == 1 ? 'task' : 'tasks'} — review them before the day gets away.',
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                  height: 1.35,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: colors.error,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopMemberCard extends StatelessWidget {
  final int rank;
  final TeamMember member;
  final int completionRate;
  final int completed;
  final int total;
  final ThemeColors colors;

  const _TopMemberCard({
    required this.rank,
    required this.member,
    required this.completionRate,
    required this.completed,
    required this.total,
    required this.colors,
  });

  /// Gold / silver / bronze medal gradients for the top 3, brand colors after.
  List<Color> _rankGradient() {
    switch (rank) {
      case 1:
        return const [Color(0xFFFDE68A), Color(0xFFF59E0B)]; // gold
      case 2:
        return const [Color(0xFFE2E8F0), Color(0xFF94A3B8)]; // silver
      case 3:
        return const [Color(0xFFFDBA74), Color(0xFFC2410C)]; // bronze
      default:
        return [colors.primaryLight, colors.primaryDark];
    }
  }

  @override
  Widget build(BuildContext context) {
    final rankColors = _rankGradient();

    return ModernCard(
      margin: const EdgeInsets.only(bottom: 12),
      onTap: () => context.go('/main/ranking'),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              AvatarInitials(name: member.name, radius: 21),
              Positioned(
                right: -4,
                bottom: -4,
                child: Container(
                  width: 21,
                  height: 21,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: rankColors,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: rankColors.last.withValues(alpha: 0.35),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: rank == 1 ? const Color(0xFF78350F) : Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: colors.text,
                  ),
                ),
                const SizedBox(height: 7),
                // Thin progress bar with a brand gradient fill.
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    height: 6,
                    color: colors.surfaceVariant,
                    child: FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: (completionRate / 100).clamp(0.0, 1.0).toDouble(),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [colors.primary, const Color(0xFF7C3AED)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$completionRate%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.primary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$completed/$total done',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: colors.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchableDropdown extends StatefulWidget {
  final List<DropdownMenuItem> items;
  final String value;
  final Function(dynamic) onChanged;
  final ThemeColors colors;

  const _SearchableDropdown({
    required this.items,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  State<_SearchableDropdown> createState() => _SearchableDropdownState();
}

class _SearchableDropdownState extends State<_SearchableDropdown> {
  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButton(
        items: widget.items,
        onChanged: widget.onChanged,
        value: widget.value,
        isExpanded: true,
        icon: Icon(Icons.arrow_drop_down, color: colors.primary),
        dropdownColor: colors.surface,
        underline: const SizedBox(),
      ),
    );
  }
}

class _DateButton extends StatelessWidget {
  final String date;
  final String placeholder;
  final VoidCallback onTap;
  final ThemeColors colors;

  const _DateButton({
    required this.date,
    required this.placeholder,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surfaceVariant,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                date.isEmpty ? placeholder : date,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  color: date.isEmpty ? colors.textSecondary : colors.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Dashboard revamp widgets
// ---------------------------------------------------------------------------

/// Small uppercase, tracking-wide, muted section label — the section header
/// style for the revamped dashboard.
class _SectionKicker extends StatelessWidget {
  final String label;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;

  const _SectionKicker({
    required this.label,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: colors.textSecondary,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textSecondary.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: colors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 36),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  actionLabel!,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (actionIcon != null) ...[
                  const SizedBox(width: 2),
                  Icon(actionIcon, size: 16),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _DashboardStatData {
  final IconData icon;
  final String label;
  final String value;
  final Color tint;
  final VoidCallback? onTap;

  const _DashboardStatData({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
    this.onTap,
  });
}

/// Rounded-2xl surface stat card: colored icon chip, large value, small
/// muted label, gentle shadow.
class _DashboardStatCard extends StatelessWidget {
  final _DashboardStatData data;
  final ThemeColors colors;

  const _DashboardStatCard({required this.data, required this.colors});

  @override
  Widget build(BuildContext context) {
    return ModernCard(
      onTap: data.onTap,
      padding: const EdgeInsets.all(12),
      margin: EdgeInsets.zero,
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TintedCircleIcon(
            icon: data.icon,
            tint: data.tint,
            size: 34,
            iconSize: 17,
          ),
          const SizedBox(height: 9),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              data.value,
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: colors.text,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            data.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colors.textSecondary,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _DayActivity {
  final DateTime dayKey;
  final String label;
  final bool isToday;
  int count;

  _DayActivity({
    required this.dayKey,
    required this.label,
    required this.isToday,
    this.count = 0,
  });
}

/// Small weekly activity card: tasks completed per day over the last 7 days,
/// bucketed in the business timezone from each task's `updatedAt`.
class _WeeklyActivityCard extends StatelessWidget {
  final ThemeColors colors;
  final List<dynamic> tasks;

  const _WeeklyActivityCard({required this.colors, required this.tasks});

  List<_DayActivity> _computeBuckets() {
    final tz = AppTimezone.instance;
    final todayKey = tz.todayKey();

    final buckets = List<_DayActivity>.generate(7, (i) {
      final day = todayKey.subtract(Duration(days: 6 - i));
      String label;
      try {
        label = DateFormat('E').format(day);
      } catch (_) {
        label = '';
      }
      return _DayActivity(
        dayKey: day,
        label: label.isEmpty ? '·' : label[0],
        isToday: i == 6,
      );
    });

    for (final task in tasks) {
      if (task is! Map || task['status'] != 'completed') continue;
      final raw = task['updatedAt'] ?? task['endDate'] ?? task['dueDate'];
      final updated = AppTimezone.tryParse(raw);
      if (updated == null) continue;
      final key = tz.dateKeyIn(updated);
      for (final bucket in buckets) {
        if (bucket.dayKey.year == key.year &&
            bucket.dayKey.month == key.month &&
            bucket.dayKey.day == key.day) {
          bucket.count += 1;
          break;
        }
      }
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _computeBuckets();
    final total = buckets.fold<int>(0, (sum, b) => sum + b.count);
    final maxCount = buckets.fold<int>(0, (m, b) => b.count > m ? b.count : m);
    final maxY = (maxCount < 4 ? 4 : maxCount).toDouble();

    return ModernCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'THIS WEEK',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      total == 0
                          ? 'No completions in the last 7 days'
                          : '$total task${total == 1 ? '' : 's'} completed in the last 7 days',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
              TintedCircleIcon(
                icon: Icons.insights_rounded,
                tint: colors.success,
                size: 34,
                iconSize: 17,
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 110,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(enabled: false),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= buckets.length) {
                          return const SizedBox.shrink();
                        }
                        final bucket = buckets[index];
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            bucket.label,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: bucket.isToday
                                  ? FontWeight.w800
                                  : FontWeight.w600,
                              color: bucket.isToday
                                  ? colors.primary
                                  : colors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barGroups: [
                  for (var i = 0; i < buckets.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: buckets[i].count.toDouble(),
                          width: 14,
                          borderRadius: BorderRadius.circular(6),
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: buckets[i].isToday
                                ? [colors.primaryLight, colors.primary]
                                : [
                                    colors.primary.withValues(alpha: 0.30),
                                    colors.primary.withValues(alpha: 0.55),
                                  ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
