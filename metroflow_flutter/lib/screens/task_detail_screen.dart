import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../models/task.dart';
import '../models/team_member.dart';
import '../theme/app_theme.dart';
import '../utils/app_toast.dart';

class TaskDetailScreen extends ConsumerStatefulWidget {
  const TaskDetailScreen({super.key});

  @override
  ConsumerState<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends ConsumerState<TaskDetailScreen> {
  Task? _task;
  List<dynamic> _comments = [];
  List<TeamMember> _teamMembers = [];
  bool _isLoading = true;
  bool _isSubmittingComment = false;
  final _commentController = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final extra = GoRouterState.of(context).extra;
    if (extra is Task && _task == null) {
      _task = extra;
      _fetchTaskDetails();
      _fetchTeamMembers();
    }
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _fetchTaskDetails() async {
    if (_task == null) return;
    try {
      final api = ApiService();
      final response = await api.getComments(_task!.id);
      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _comments = data['data'] ?? [];
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch task details: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchTeamMembers() async {
    try {
      final api = ApiService();
      final response = await api.getTeam();
      if (response.statusCode == 200) {
        final data = response.data;
        setState(() {
          _teamMembers = ((data['data'] as List<dynamic>?) ?? const [])
              .map((t) => TeamMember.fromJson(t as Map<String, dynamic>))
              .toList();
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch team members: $e');
    }
  }

  Future<void> _handleAddComment() async {
    if (_commentController.text.trim().isEmpty) return;
    if (_task == null) return;

    setState(() => _isSubmittingComment = true);
    try {
      final api = ApiService();
      await api.addComment({
        'taskId': _task!.id,
        'content': _commentController.text.trim(),
      });
      setState(() => _commentController.clear());
      await _fetchTaskDetails();
    } catch (e) {
      debugPrint('Failed to add comment: $e');
    } finally {
      setState(() => _isSubmittingComment = false);
    }
  }

  Future<void> _handleToggleAssignment(String userId) async {
    final task = _task;
    if (task == null) return;

    final assignedTo = List<String>.from(task.assignedTo ?? []);
    final isAssigned = assignedTo.contains(userId);

    try {
      if (isAssigned) {
        assignedTo.remove(userId);
        await ApiService().updateTask(task.id, {'assignedTo': assignedTo});
      } else {
        assignedTo.add(userId);
        await ApiService().assignTasks({
          'taskIds': [task.id],
          'userIds': [userId],
        });
      }

      setState(() {
        _task = _copyTask(task, assignedTo: assignedTo);
      });
    } catch (e) {
      debugPrint('Failed to update assignment: $e');
    }
  }

  Future<void> _handleToggleReaction(String commentId, String type) async {
    try {
      await ApiService().toggleReaction(commentId, type);
      await _fetchTaskDetails();
    } catch (e) {
      debugPrint('Failed to update reaction: $e');
    }
  }

  Future<void> _handleUpdateStatus(String status) async {
    if (_task == null) return;
    try {
      final api = ApiService();
      await api.updateTask(_task!.id, {'status': status});
      setState(() {
        _task = _copyTask(_task!, status: status);
      });
    } catch (e) {
      debugPrint('Failed to update status: $e');
    }
  }

  Task _copyTask(Task task, {String? status, List<String>? assignedTo}) {
    return Task(
      id: task.id,
      businessId: task.businessId,
      createdBy: task.createdBy,
      title: task.title,
      description: task.description,
      epic: task.epic,
      epicId: task.epicId,
      sprint: task.sprint,
      targetValue: task.targetValue,
      accomplishedValue: task.accomplishedValue,
      startDate: task.startDate,
      endDate: task.endDate,
      dueDate: task.dueDate,
      status: status ?? task.status,
      isOverdue: task.isOverdue,
      assignedTo: assignedTo ?? task.assignedTo,
      attachments: task.attachments,
      comments: task.comments,
      images: task.images,
      createdAt: task.createdAt,
      updatedAt: task.updatedAt,
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.success;
      case 'in_progress':
        return AppColors.warning;
      default:
        return AppTheme.colors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_task == null) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Column(
              children: [
                IconButton(
                  onPressed: () => context.go('/main/backlog'),
                  icon: const Icon(Icons.arrow_back),
                ),
                const Text('Task not found'),
              ],
            ),
          ),
        ),
      );
    }

    final task = _task!;
    final statusColor = _getStatusColor(task.status);

    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildStatusBadge(task, statusColor),
                          const SizedBox(height: 16),
                          Text(task.title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                          if (task.description != null && task.description!.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(task.description!, style: const TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                          const SizedBox(height: 24),
                          _buildMetaRow(task),
                          const SizedBox(height: 24),
                          _buildAssigneesSection(),
                          const SizedBox(height: 24),
                          _buildActionsSection(task, statusColor),
                          const SizedBox(height: 24),
                          _buildCommentsSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _handleDeleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final api = ApiService();
      await api.deleteTask(_task!.id);
      if (mounted) {
        AppToast.show('Task deleted successfully', type: AppToastType.success);
        context.go('/main/backlog');
      }
    } catch (e) {
      debugPrint('Failed to delete task: $e');
    }
  }

  Widget _buildHeader() {
    return Row(
      children: [
        IconButton(onPressed: () => context.go('/main/backlog'), icon: const Icon(Icons.arrow_back)),
        const Expanded(
          child: Text('Task Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ),
        IconButton(
          onPressed: () => context.go('/main/create-task', extra: _task),
          icon: Icon(Icons.edit_outlined, color: AppTheme.colors.textSecondary),
        ),
        IconButton(
          onPressed: _handleDeleteTask,
          icon: const Icon(Icons.delete_outline, color: AppColors.error),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(Task task, Color statusColor) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(
                task.status.split('_').map((w) => w[0].toUpperCase() + w.substring(1)).join(' '),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: statusColor),
              ),
            ],
          ),
        ),
        if (task.isOverdue)
          Container(
            margin: const EdgeInsets.only(left: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('Overdue', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.error)),
          ),
      ],
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null || dateString.isEmpty) return '';
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Widget _buildMetaRow(Task task) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.colors.border),
      ),
      child: Column(
        children: [
          if (task.startDate.isNotEmpty)
            ListTile(
              leading: const Icon(Icons.date_range_outlined),
              title: const Text('Start Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(
                _formatDate(task.startDate),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          if (task.endDate.isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('End Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(
                _formatDate(task.endDate),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (task.dueDate != null && task.dueDate!.isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.access_time_outlined),
              title: const Text('Due Date', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(
                _formatDate(task.dueDate),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
          if (task.sprint != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.view_list_outlined),
              title: const Text('Sprint', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(task.sprint!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
          if (task.epic != null) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Epic', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(task.epic!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ],
          if (task.createdAt.isNotEmpty) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('Created At', style: TextStyle(fontSize: 12, color: Colors.grey)),
              subtitle: Text(
                _formatDate(task.createdAt),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAssigneesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Assignees', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            IconButton(
              onPressed: _showAssignModal,
              icon: const Icon(Icons.person_add_outlined, color: AppColors.primary),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_task!.assignedTo == null || _task!.assignedTo!.isEmpty)
              const Text('No one assigned', style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic))
            else
              ...(_task!.assignedTo ?? []).map((userId) {
                final member = _teamMembers.firstWhere((m) => m.id == userId, orElse: () => TeamMember(id: '', name: userId, email: '', role: '', status: ''));
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.colors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppTheme.colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(member.name, style: const TextStyle(fontSize: 14)),
                    ],
                  ),
                );
              }),
          ],
        ),
      ],
    );
  }

  void _showAssignModal() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final colors = AppTheme.colors;
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Assign Task',
                          style: TextStyle(
                            color: colors.text,
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: colors.text),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.separated(
                        itemCount: _teamMembers.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final member = _teamMembers[index];
                          final isAssigned = _task?.assignedTo?.contains(member.id) ?? false;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () async {
                              await _handleToggleAssignment(member.id);
                              setModalState(() {});
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.background,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 20,
                                    backgroundColor: colors.primary.withValues(alpha: 0.12),
                                    child: Text(
                                      member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
                                      style: TextStyle(color: colors.primary, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(member.name, style: TextStyle(color: colors.text, fontWeight: FontWeight.w600)),
                                        Text(member.role, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  Icon(
                                    isAssigned ? Icons.check_box : Icons.check_box_outline_blank,
                                    color: isAssigned ? colors.primary : colors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildActionsSection(Task task, Color statusColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Actions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Row(
          children: [
            if (task.status != 'pending')
              Expanded(
                child: _ActionButton(label: 'Set Pending', color: Colors.grey, onTap: () => _handleUpdateStatus('pending')),
              ),
            if (task.status != 'in_progress') ...[
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(label: 'Set In Progress', color: AppColors.warning, onTap: () => _handleUpdateStatus('in_progress')),
              ),
            ],
            if (task.status != 'completed') ...[
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(label: 'Complete Task', color: AppColors.success, onTap: () => _handleUpdateStatus('completed')),
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildCommentsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comments (${_comments.length})', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        if (_comments.isEmpty)
          const Text('No comments yet', style: TextStyle(fontSize: 14, color: Colors.grey, fontStyle: FontStyle.italic))
        else
          ..._comments.map((comment) {
            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Text(
                            '${comment['userName'] ?? 'U'}'.toUpperCase().characters.first,
                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${comment['userName'] ?? 'User'}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            Text(
                              DateTime.tryParse(comment['createdAt'] ?? '')?.toLocal().toString().split(' ')[0] ?? '',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Row(
                        children: [
                          _reactionButton(comment, 'like', Icons.thumb_up_alt_outlined),
                          const SizedBox(width: 6),
                          _reactionButton(comment, 'love', Icons.favorite_border),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('${comment['content'] ?? ''}', style: const TextStyle(fontSize: 14)),
                ],
              ),
            );
          }),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppTheme.colors.border)),
            color: AppTheme.colors.background,
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: InputDecoration(
                    hintText: 'Add a comment...',
                    hintStyle: TextStyle(color: AppTheme.colors.textSecondary),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(20)),
                    filled: true,
                    fillColor: AppTheme.colors.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  ),
                  maxLines: null,
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _isSubmittingComment ? null : _handleAddComment,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: _isSubmittingComment
                      ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                      : const Icon(Icons.send, color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reactionButton(Map<String, dynamic> comment, String type, IconData icon) {
    final reactions = comment['reactions'] as List<dynamic>? ?? [];
    final isActive = reactions.any((reaction) {
      if (reaction is Map<String, dynamic>) {
        return reaction['type'] == type;
      }
      return false;
    });

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _handleToggleReaction((comment['id'] as String?) ?? '', type),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(
          icon,
          size: 18,
          color: isActive ? AppColors.primary : AppTheme.colors.textSecondary,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
      ),
    );
  }
}
