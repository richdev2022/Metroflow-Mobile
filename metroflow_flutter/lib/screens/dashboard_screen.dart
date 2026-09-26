import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/team_member.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../widgets/modern_ui.dart';
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
      return DateFormat('d MMM').format(DateTime.parse(dueDateStr));
    } catch (e) {
      return dueDateStr;
    }
  }

  int _dueTodayCount() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return _filteredTasks.where((task) {
      if (task['status'] == 'completed') return false;
      final dateStr = task['dueDate'] as String? ?? task['endDate'] as String? ?? '';
      if (dateStr.isEmpty) return false;
      try {
        final date = DateTime.parse(dateStr);
        return date.year == today.year &&
            date.month == today.month &&
            date.day == today.day;
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
    final displayName = (authState.userName ?? '').trim();
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
              // ---------- Greeting header ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_greeting()}, $firstName!',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: colors.text,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, d MMMM y').format(DateTime.now()),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ---------- Hero overview card ----------
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildHeroCard(colors, openTasksCount, completionPercentage, overdueTasks.length),
              ),
              const SizedBox(height: 20),

              // ---------- Quick actions ----------
              _buildQuickActions(colors),
              const SizedBox(height: 24),

              // ---------- Stat chips row ----------
              SectionHeader(
                title: 'Overview',
                subtitle: 'Activity for the selected filters',
              ),
              SizedBox(
                height: 132,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  physics: const BouncingScrollPhysics(),
                  children: [
                    StatCard(
                      icon: Icons.today_outlined,
                      label: 'Due today',
                      value: '${_dueTodayCount()}',
                      tint: colors.primary,
                    ),
                    const SizedBox(width: 12),
                    StatCard(
                      icon: Icons.task_alt_outlined,
                      label: 'Done this week',
                      value: '${_completedThisWeekCount()}',
                      tint: colors.success,
                    ),
                    const SizedBox(width: 12),
                    StatCard(
                      icon: Icons.error_outline,
                      label: 'Overdue',
                      value: '${overdueTasks.length}',
                      tint: colors.error,
                    ),
                    const SizedBox(width: 12),
                    StatCard(
                      icon: Icons.groups_outlined,
                      label: 'Team members',
                      value: '${_teamMembers.length}',
                      tint: const Color(0xFF7C3AED),
                    ),
                  ],
                ),
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
                    SectionHeader(
                      title: 'My Tasks',
                      subtitle: '$openTasksCount open of $totalTasks total',
                      actionLabel: 'View all',
                      onAction: () => context.go('/main?tab=1'),
                      actionIcon: Icons.arrow_forward_rounded,
                    ),
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
                    SectionHeader(
                      title: 'Top Members',
                      subtitle: 'Highest completion rate this period',
                      actionLabel: 'Full ranking',
                      onAction: () => context.go('/main/ranking'),
                      actionIcon: Icons.arrow_forward_rounded,
                    ),
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
    int openTasksCount,
    int completionPercentage,
    int overdueCount,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: BrandGradient.deep,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Stack(
          children: [
            // Decorative circles
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
                Row(
                  children: [
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
                  ],
                ),
                const SizedBox(height: 18),
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
        onTap: () => context.go('/main?tab=2'),
      ),
      _QuickActionData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'New Chat',
        tint: const Color(0xFF7C3AED),
        onTap: () => context.go('/main?tab=3'),
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
          SectionHeader(title: 'Quick Actions'),
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
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.text,
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

  Color _rankColor() {
    switch (rank) {
      case 1:
        return const Color(0xFFF59E0B); // Gold
      case 2:
        return const Color(0xFF94A3B8); // Silver
      case 3:
        return const Color(0xFFB45309); // Bronze
      default:
        return colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _rankColor(),
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.surface, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '$rank',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
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
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: completionRate / 100,
                          minHeight: 6,
                          backgroundColor: colors.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            colors.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$completionRate%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$completed/$total',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: colors.text,
              ),
            ),
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
