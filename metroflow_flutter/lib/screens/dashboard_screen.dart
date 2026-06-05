import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';
import 'package:metroflow_flutter/services/api.dart';
import 'package:metroflow_flutter/models/team_member.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  List<dynamic> _tasks = [];
  List<TeamMember> _teamMembers = [];
  List<dynamic> _epics = [];
  bool _isLoading = true;
  String _selectedMember = 'all';
  String _selectedEpic = 'all';
  String _startDate = '';
  String _endDate = '';

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

      final tasksParams = <String, dynamic>{'limit': '10000'};
      if (_selectedMember != 'all') {
        tasksParams['assignedTo'] = _selectedMember;
      }
      if (_selectedEpic != 'all') {
        tasksParams['epicId'] = _selectedEpic;
      }
      if (_startDate.isNotEmpty) {
        tasksParams['startDate'] = _startDate;
      }
      if (_endDate.isNotEmpty) {
        tasksParams['endDate'] = _endDate;
      }

      final tasksResponse = await api.getTasks(params: tasksParams);
      final teamResponse = await api.getTeam();
      final epicsResponse = await api.getEpics();

      if (mounted) {
        setState(() {
          if (tasksResponse.data != null && tasksResponse.data['success'] == true) {
            _tasks = tasksResponse.data['data']['tasks'] ?? [];
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
    _fetchData();
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
      _fetchData();
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
      _fetchData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return SafeArea(
        child: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    final totalTasks = _tasks.length;
    final completedTasks = _tasks.where((t) => t['status'] == 'completed').length;
    final inProgressTasks = _tasks.where((t) => t['status'] == 'in_progress').length;
    final overdueTasks = _tasks.where((t) => t['isOverdue'] == true).toList();
    final completionPercentage = totalTasks > 0 ? ((completedTasks / totalTasks) * 100).round() : 0;

    final Map<String, Map<String, int>> memberStats = {};
    for (var member in _teamMembers) {
      memberStats[member.id] = {'total': 0, 'completed': 0};
    }
    for (var task in _tasks) {
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

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.text.withValues(alpha: 0.05),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Filters',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Team Member',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  _SearchableDropdown(
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('All'),
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
                      _fetchData();
                    },
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Epic',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  _SearchableDropdown(
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
                      _fetchData();
                    },
                    colors: colors,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Date Range',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: colors.textSecondary),
                  ),
                  const SizedBox(height: 8),
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
                      if (_startDate.isNotEmpty || _endDate.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.textSecondary, size: 20),
                          onPressed: _clearFilters,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _ActionCard(
                    icon: Icons.archive_outlined,
                    label: 'Backlog',
                    onTap: () => context.go('/main/backlog'),
                    colors: colors,
                  ),
                  _ActionCard(
                    icon: Icons.lightbulb_outlined,
                    label: 'Ideas',
                    onTap: () => context.go('/main/ideas'),
                    colors: colors,
                  ),
                  _ActionCard(
                    icon: Icons.receipt_long_outlined,
                    label: 'Logs',
                    onTap: () => context.go('/main/activity-logs'),
                    colors: colors,
                  ),
                  _ActionCard(
                    icon: Icons.people_outlined,
                    label: 'Team',
                    onTap: () => context.go('/main/team'),
                    colors: colors,
                  ),
                  _StatCard(
                    icon: Icons.list_outlined,
                    value: '$totalTasks',
                    label: 'Total Tasks',
                    iconBgColor: colors.primary.withValues(alpha: 0.2),
                    iconColor: colors.primary,
                    colors: colors,
                  ),
                  _StatCard(
                    icon: Icons.check_circle_outlined,
                    value: '$completedTasks',
                    label: 'Completed',
                    iconBgColor: colors.success.withValues(alpha: 0.2),
                    iconColor: colors.success,
                    colors: colors,
                  ),
                  _StatCard(
                    icon: Icons.timer_outlined,
                    value: '$inProgressTasks',
                    label: 'In Progress',
                    iconBgColor: colors.warning.withValues(alpha: 0.2),
                    iconColor: colors.warning,
                    colors: colors,
                  ),
                  _StatCard(
                    icon: Icons.warning_amber_rounded,
                    value: '${overdueTasks.length}',
                    label: 'Overdue',
                    iconBgColor: colors.error.withValues(alpha: 0.2),
                    iconColor: colors.error,
                    colors: colors,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colors.text.withValues(alpha: 0.05),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Completion Rate',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: _GradientProgressBar(
                            progress: totalTasks > 0 ? completionPercentage / 100 : 0,
                            colors: colors,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '$completionPercentage%',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.primary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (overdueTasks.isNotEmpty) ...[
                    Text(
                      'Overdue Tasks',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                    ),
                    const SizedBox(height: 16),
                    ...overdueTasks.take(3).map((task) {
                      return _OverdueCard(task: task, colors: colors);
                    }),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    'Team Performance',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: colors.text),
                  ),
                  const SizedBox(height: 16),
                  ...List.generate(
                    sortedMembers.take(5).length,
                    (index) {
                      final member = sortedMembers[index];
                      final stats = memberStats[member.id]!;
                      final rate = stats['total']! > 0 ? ((stats['completed']! / stats['total']!) * 100).round() : 0;
                      return _TeamMemberRow(
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
    );
  }
}

class _GradientProgressBar extends StatelessWidget {
  final double progress;
  final ThemeColors colors;

  const _GradientProgressBar({
    required this.progress,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: 14,
          width: constraints.maxWidth,
          decoration: BoxDecoration(
            color: colors.surfaceVariant,
            borderRadius: BorderRadius.circular(7),
          ),
          child: FractionallySizedBox(
            widthFactor: progress,
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.primary, colors.primaryLight],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ),
        );
      },
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
    return Container(
      decoration: BoxDecoration(
        color: widget.colors.surfaceVariant,
        border: Border.all(color: widget.colors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonFormField(
        items: widget.items,
        onChanged: widget.onChanged,
        initialValue: widget.value,
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          suffixIcon: Icon(Icons.arrow_drop_down, color: widget.colors.primary),
        ),
        isExpanded: true,
        icon: const SizedBox.shrink(),
        dropdownColor: widget.colors.surface,
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
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.calendar_today_outlined, size: 16, color: colors.primary),
            const SizedBox(width: 6),
            Text(
              date.isEmpty ? placeholder : date,
              style: TextStyle(
                fontSize: 14,
                color: date.isEmpty ? colors.textSecondary : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ThemeColors colors;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: (MediaQuery.of(context).size.width - 24 * 2 - 12 * 3) / 4,
        constraints: const BoxConstraints(minWidth: 70),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: colors.text.withValues(alpha: 0.05), offset: const Offset(0, 2), blurRadius: 8),
          ],
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [colors.primary, colors.primaryLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: [
                  BoxShadow(
                    color: colors.primary.withValues(alpha: 0.3),
                    offset: const Offset(0, 4),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(fontSize: 12, color: colors.text, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color iconBgColor;
  final Color iconColor;
  final ThemeColors colors;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.iconBgColor,
    required this.iconColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: (MediaQuery.of(context).size.width - 24 * 2 - 12) / 2,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: colors.text.withValues(alpha: 0.08), offset: const Offset(0, 4), blurRadius: 12),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(color: iconBgColor, borderRadius: BorderRadius.circular(14)),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: colors.text),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: colors.textSecondary, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _OverdueCard extends StatelessWidget {
  final dynamic task;
  final ThemeColors colors;

  const _OverdueCard({required this.task, required this.colors});

  @override
  Widget build(BuildContext context) {
    final dueDate = task['dueDate'] as String? ?? task['endDate'] as String? ?? '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: colors.text.withValues(alpha: 0.05), offset: const Offset(0, 2), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            child: Icon(Icons.warning_amber_rounded, color: colors.error, size: 20),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task['title'] as String,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.text),
                ),
                const SizedBox(height: 4),
                Text(
                  dueDate.isNotEmpty
                      ? 'Due: ${DateTime.parse(dueDate).day}/${DateTime.parse(dueDate).month}/${DateTime.parse(dueDate).year}'
                      : 'Due: No date',
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TeamMemberRow extends StatelessWidget {
  final int rank;
  final TeamMember member;
  final int completionRate;
  final int completed;
  final int total;
  final ThemeColors colors;

  const _TeamMemberRow({
    required this.rank,
    required this.member,
    required this.completionRate,
    required this.completed,
    required this.total,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: colors.text.withValues(alpha: 0.05), offset: const Offset(0, 2), blurRadius: 8),
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text(
              '$rank',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.primary),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: colors.text),
                ),
                const SizedBox(height: 2),
                Text(
                  member.role,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$completionRate%',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.primary),
              ),
              Text(
                '$completed/$total',
                style: TextStyle(fontSize: 13, color: colors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
