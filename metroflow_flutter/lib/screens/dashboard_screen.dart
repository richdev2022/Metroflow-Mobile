import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../providers/auth_provider.dart';
import '../providers/user_profile_provider.dart';
import '../utils/app_timezone.dart';
import '../widgets/app_tour.dart';
import '../widgets/avatar_with_initials.dart';
import '../widgets/modern_ui.dart';

/// Home — deliberately LEAN.
///
/// The previous revision stacked NINE sections (hero, quick actions, stat
/// grid, weekly chart, filters, my tasks, overdue banner, status pie, top
/// members) which made the page endless on phones. This revision keeps the
/// four sections that matter (compact hero, quick actions, my tasks,
/// overdue banner) and gets out of the way.
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _allTasks = [];
  bool _isLoading = true;

  // Anchors for the guided app tour (lib/widgets/app_tour.dart) — the tour
  // spotlights these regions on first launch.
  final GlobalKey _tourHeroKey = GlobalKey(debugLabel: 'tour-hero');
  final GlobalKey _tourQuickActionsKey = GlobalKey(debugLabel: 'tour-quick-actions');
  final GlobalKey _tourTasksKey = GlobalKey(debugLabel: 'tour-tasks');

  @override
  void initState() {
    super.initState();
    AppTourAnchors.register('dashboard-hero', _tourHeroKey);
    AppTourAnchors.register('dashboard-quick-actions', _tourQuickActionsKey);
    AppTourAnchors.register('dashboard-tasks', _tourTasksKey);
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

      // Fetch ALL tasks without filters, we'll aggregate locally.
      final tasksResponse =
          await api.getTasks(params: <String, dynamic>{'limit': '10000'});

      if (mounted) {
        setState(() {
          if (tasksResponse.data != null &&
              tasksResponse.data['success'] == true) {
            _allTasks = tasksResponse.data['data']['tasks'] ?? [];
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


  int _completedThisWeekCount() {
    final weekAgo = DateTime.now().subtract(const Duration(days: 7));
    return _allTasks.where((task) {
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

    final totalTasks = _allTasks.length;
    final completedTasks = _allTasks.where((t) => t['status'] == 'completed').length;
    final openTasksCount = totalTasks - completedTasks;
    final overdueTasks = _allTasks.where(_isTaskOverdue).toList();

    final openTasks = _allTasks.where((t) => t['status'] != 'completed').toList()
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
              // ---------- Compact hero (greeting + mini stats) ----------
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildCompactHero(
                  colors,
                  firstName,
                  profile,
                  openTasksCount,
                  _completedThisWeekCount(),
                  overdueTasks.length,
                ),
              ),
              const SizedBox(height: 22),

              // ---------- Quick actions ----------
              _buildQuickActions(colors),
              const SizedBox(height: 22),

              // ---------- My Tasks preview ----------
              Padding(
                key: _tourTasksKey,
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                          subtitle:
                              'No open tasks right now. Create a task to get things moving.',
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

              // ---------- Overdue banner ----------
              if (overdueTasks.isNotEmpty) ...[
                const SizedBox(height: 20),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _OverdueBanner(
                    count: overdueTasks.length,
                    colors: colors,
                    onTap: () => context.go('/main?tab=1'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Compact hero: greeting + avatar + today's date + three tappable stat
  /// chips. Everything else that used to live in the hero (workspace chip,
  /// giant counter, progress bar) moved to the Tasks tab or got cut.
  Widget _buildCompactHero(
    ThemeColors colors,
    String firstName,
    UserProfile profile,
    int openCount,
    int doneThisWeek,
    int overdueCount,
  ) {
    return Container(
      key: _tourHeroKey,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
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
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.30),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '${_greeting()}, $firstName!',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    height: 1.25,
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
          const SizedBox(height: 4),
          Text(
            AppTimezone.instance.formatDateFull(DateTime.now()),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Colors.white.withValues(alpha: 0.82),
            ),
          ),
          const SizedBox(height: 16),
          // Three tappable stat chips — the whole row is one flexible unit,
          // so it never overflows on narrow screens.
          Row(
            children: [
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.assignment_outlined,
                  value: '$openCount',
                  label: 'Open',
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.task_alt_rounded,
                  value: '$doneThisWeek',
                  label: 'Done · 7d',
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStatChip(
                  icon: Icons.error_outline,
                  value: '$overdueCount',
                  label: 'Overdue',
                  alert: overdueCount > 0,
                  onTap: () => context.go('/main?tab=1'),
                ),
              ),
            ],
          ),
        ],
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
        // tab=3 → Meetings (index 3 = MeetingsScreen on the bottom nav)
        onTap: () => context.go('/main?tab=3'),
      ),
      _QuickActionData(
        icon: Icons.chat_bubble_outline_rounded,
        label: 'New Chat',
        tint: const Color(0xFF7C3AED),
        // tab=2 → Chat (index 2 = ChatScreen on the bottom nav)
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
        icon: Icons.people_outlined,
        label: 'Team',
        tint: const Color(0xFF4F46E5),
        onTap: () => context.go('/main/team'),
      ),
    ];

    return Padding(
      key: _tourQuickActionsKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
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
}

/// Small translucent stat chip used inside the compact hero.
class _HeroStatChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final bool alert;
  final VoidCallback onTap;

  const _HeroStatChip({
    required this.icon,
    required this.value,
    required this.label,
    this.alert = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: alert ? Colors.red.shade200 : Colors.white.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$value  $label',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: alert ? Colors.red.shade100 : Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: ShimmerBox(
              width: double.infinity,
              height: 150,
              radius: 24,
            ),
          ),
          const SizedBox(height: 22),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: const [
                ShimmerBox(width: 84, height: 96, radius: 18),
                SizedBox(width: 12),
                ShimmerBox(width: 84, height: 96, radius: 18),
                SizedBox(width: 12),
                ShimmerBox(width: 84, height: 96, radius: 18),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              label: isOverdue
                                  ? 'Overdue · $dateLabel'
                                  : 'Due $dateLabel',
                              color: isOverdue
                                  ? colors.error
                                  : colors.textSecondary,
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
