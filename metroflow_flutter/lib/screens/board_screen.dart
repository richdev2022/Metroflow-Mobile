import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../utils/app_toast.dart';

// Top-level so BOTH _BoardScreenState and _BoardTaskCard can use it.
String formatDate(String dateString) {
  try {
    final date = DateTime.parse(dateString).toLocal();
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  } catch (e) {
    return dateString;
  }
}

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  List<TaskStatus> taskStatuses = [];
  bool isLoading = true;
  bool isRefreshing = false;
  String? _error; // surfaced — a failed load must never masquerade as an empty board
  String? draggingTaskId;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      setState(() {
        isRefreshing = true;
        _error = null;
      });
      final api = ApiService();
      
      // Fetch board data (statuses with tasks already grouped)
      final boardResponse = await api.getBoard();
      
      if (mounted) {
        final boardData = boardResponse.data;
        
        if (boardData is Map && boardData['success'] == true) {
          final newStatuses = (boardData['data'] as List?)
              ?.map((e) => TaskStatus.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
          setState(() => taskStatuses = newStatuses);
        } else {
          setState(() => _error =
              boardData is Map ? (boardData['error']?.toString() ?? 'Could not load the board') : 'Could not load the board');
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch board: $e');
      if (mounted) {
        setState(() => _error = ApiService.extractErrorMessage(e));
      }
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Color getStatusColor(String statusName) {
    final status = taskStatuses.firstWhere(
      (s) => s.name == statusName,
      orElse: () => taskStatuses.first,
    );
    try {
      final colorString = status.color;
      final buffer = StringBuffer();
      if (colorString.length == 6 || colorString.length == 7) buffer.write('ff');
      buffer.write(colorString.replaceFirst('#', ''));
      return Color(int.parse(buffer.toString(), radix: 16));
    } catch (e) {
      return const Color(0xFF9E9E9E);
    }
  }

  Future<void> updateTaskStatus(Task task, String newStatus) async {
    debugPrint('Updating task ${task.id} to status $newStatus');
    // First, update local state for immediate UI feedback
    setState(() {
      // Remove task from old status
      for (int i = 0; i < taskStatuses.length; i++) {
        if (taskStatuses[i].tasks != null && taskStatuses[i].tasks!.any((t) => t.id == task.id)) {
          taskStatuses[i] = TaskStatus(
            id: taskStatuses[i].id,
            businessId: taskStatuses[i].businessId,
            name: taskStatuses[i].name,
            color: taskStatuses[i].color,
            isDefault: taskStatuses[i].isDefault,
            sortOrder: taskStatuses[i].sortOrder,
            createdAt: taskStatuses[i].createdAt,
            updatedAt: taskStatuses[i].updatedAt,
            tasks: taskStatuses[i].tasks?.where((t) => t.id != task.id).toList(),
          );
          break;
        }
      }
      
      // Add task to new status
      final updatedTask = Task(
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
        status: newStatus,
        isOverdue: task.isOverdue,
        assignedTo: task.assignedTo,
        attachments: task.attachments,
        comments: task.comments,
        images: task.images,
        createdAt: task.createdAt,
        updatedAt: DateTime.now().toIso8601String(),
      );
      
      for (int i = 0; i < taskStatuses.length; i++) {
        if (taskStatuses[i].name == newStatus) {
          taskStatuses[i] = TaskStatus(
            id: taskStatuses[i].id,
            businessId: taskStatuses[i].businessId,
            name: taskStatuses[i].name,
            color: taskStatuses[i].color,
            isDefault: taskStatuses[i].isDefault,
            sortOrder: taskStatuses[i].sortOrder,
            createdAt: taskStatuses[i].createdAt,
            updatedAt: taskStatuses[i].updatedAt,
            tasks: [...(taskStatuses[i].tasks ?? [])..add(updatedTask)],
          );
          break;
        }
      }
    });

    // Then, make the API call to update on backend
    try {
      final api = ApiService();
      await api.updateTask(task.id, {'status': newStatus});
      debugPrint('Successfully updated task ${task.id} on backend');
    } catch (e) {
      debugPrint('Failed to update task status on backend: $e');
      // If API fails, revert back by refetching the data
      await fetchData();
      if (mounted) {
        AppToast.show(ApiService.extractErrorMessage(e), type: AppToastType.error);
      }
    }
  }

  Future<void> showCreateStatusDialog() async {
    final nameController = TextEditingController();
    Color selectedColor = const Color(0xFF6B7280);

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Create New Status Column'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Status Name',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Select Color:'),
                const SizedBox(height: 8),
                SizedBox(
                  height: 200,
                  child: BlockPicker(
                    pickerColor: selectedColor,
                    onColorChanged: (color) {
                      setDialogState(() {
                        selectedColor = color;
                      });
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  AppToast.show('Please enter a status name', type: AppToastType.error);
                  return;
                }
                
                try {
                  final api = ApiService();
                  final navigator = Navigator.of(context);
                  final response = await api.createTaskStatus({
                    'name': nameController.text.trim(),
                    'color': '#${selectedColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                    'sort_order': taskStatuses.length,
                  });
                  
                  if (response.data is Map && response.data['success'] == true) {
                    if (!mounted) return;
                    navigator.pop();
                    await fetchData();
                  }
                } catch (e) {
                  debugPrint('Failed to create status: $e');
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // UI
  // -------------------------------------------------------------------------

  int get _totalTasks => taskStatuses.fold<int>(0, (sum, s) => sum + (s.tasks?.length ?? 0));

  int get _overdueCount => taskStatuses.fold<int>(
      0, (sum, s) => sum + (s.tasks?.where((t) => t.isOverdue).length ?? 0));

  void _goBack() {
    // GUARDED back: the board can be reached via context.go() (no stack) or
    // pushed from Tasks. Pop when possible, otherwise return to the app shell.
    if (context.canPop()) {
      context.pop();
    } else {
      context.go('/main/tasks');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (isLoading) {
      return Scaffold(
        backgroundColor: colors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: colors.primary),
              const SizedBox(height: 16),
              Text('Loading board…', style: TextStyle(color: colors.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/main/create-task'),
        backgroundColor: colors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_task_rounded, size: 20),
        label: const Text('New Task', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ------------------------------------------------ header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  // Back button — was MISSING entirely (board used go() nav).
                  _HeaderIconButton(
                    icon: Icons.arrow_back_ios_new_rounded,
                    colors: colors,
                    onTap: _goBack,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Board',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: colors.text,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$_totalTasks task${_totalTasks == 1 ? '' : 's'} • long-press to drag',
                          style: TextStyle(fontSize: 12, color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _HeaderIconButton(
                    icon: Icons.refresh_rounded,
                    colors: colors,
                    onTap: () => fetchData(),
                  ),
                  const SizedBox(width: 8),
                  _HeaderIconButton(
                    icon: Icons.view_column_outlined,
                    colors: colors,
                    onTap: showCreateStatusDialog,
                  ),
                ],
              ),
            ),

            // ------------------------------------------------ stats strip
            if (_totalTasks > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    _StatChip(
                      label: '$_totalTasks total',
                      icon: Icons.assignment_rounded,
                      background: colors.primary.withValues(alpha: 0.10),
                      foreground: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    if (_overdueCount > 0)
                      _StatChip(
                        label: '$_overdueCount overdue',
                        icon: Icons.warning_amber_rounded,
                        background: colors.error.withValues(alpha: 0.10),
                        foreground: colors.error,
                      ),
                    const Spacer(),
                    Text(
                      '${taskStatuses.length} column${taskStatuses.length == 1 ? '' : 's'}',
                      style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),

            // ------------------------------------------------ columns
            Expanded(
              child: _error != null
                  // A failed load must be VISIBLE — it used to swallow into
                  // the empty state, which looked like "board not working".
                  ? RefreshIndicator(
                      onRefresh: fetchData,
                      color: colors.primary,
                      backgroundColor: colors.surface,
                      child: ListView(
                        children: [
                          const SizedBox(height: 64),
                          Icon(Icons.cloud_off_rounded, size: 44, color: colors.textSecondary),
                          const SizedBox(height: 12),
                          Text(
                            'Couldn\'t load the board',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.text),
                          ),
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12.5, height: 1.4, color: colors.textSecondary),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Center(
                            child: OutlinedButton.icon(
                              onPressed: fetchData,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Retry'),
                              style: OutlinedButton.styleFrom(foregroundColor: colors.primary),
                            ),
                          ),
                        ],
                      ),
                    )
                  : taskStatuses.isEmpty
                  ? _EmptyBoard(colors: colors, onAddColumn: showCreateStatusDialog)
                  : RefreshIndicator(
                      onRefresh: fetchData,
                      color: colors.primary,
                      backgroundColor: colors.surface,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                        scrollDirection: Axis.horizontal,
                        children: [
                          ...taskStatuses.map((status) {
                            final statusTasks = status.tasks ?? [];
                            final screenWidth = MediaQuery.of(context).size.width;
                            final columnWidth = screenWidth * 0.85 < 290 ? 290.0 : screenWidth * 0.85;
                            final accent = getStatusColor(status.name);
                            return Container(
                              width: columnWidth,
                              margin: const EdgeInsets.only(right: 14, bottom: 4),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Column header card
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: colors.surface,
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: colors.border),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 34,
                                          height: 34,
                                          decoration: BoxDecoration(
                                            color: accent.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                          child: Center(
                                            child: Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: accent,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            status.name,
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: colors.text,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: colors.primary.withValues(alpha: 0.10),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            '${statusTasks.length}',
                                            style: TextStyle(
                                              color: colors.primary,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Expanded(
                                    child: DragTarget<Task>(
                                      onWillAcceptWithDetails: (details) => details.data.status != status.name,
                                      onAcceptWithDetails: (details) {
                                        final task = details.data;
                                        if (task.status != status.name) {
                                          updateTaskStatus(task, status.name);
                                        }
                                      },
                                      builder: (context, candidateData, rejectedData) {
                                        final isTargeting = candidateData.isNotEmpty;
                                        return AnimatedContainer(
                                          duration: const Duration(milliseconds: 180),
                                          constraints: const BoxConstraints.expand(),
                                          decoration: BoxDecoration(
                                            color: isTargeting
                                                ? accent.withValues(alpha: 0.08)
                                                : colors.surfaceVariant,
                                            borderRadius: BorderRadius.circular(14),
                                            border: Border.all(
                                              color: isTargeting ? accent : colors.border,
                                              width: isTargeting ? 1.6 : 1,
                                            ),
                                          ),
                                          child: statusTasks.isEmpty
                                              ? Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.outbound_rounded,
                                                          color: colors.textSecondary.withValues(alpha: 0.7), size: 30),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        isTargeting ? 'Drop here' : 'No tasks',
                                                        style: TextStyle(
                                                          color: isTargeting ? accent : colors.textSecondary,
                                                          fontSize: 12.5,
                                                          fontWeight: isTargeting ? FontWeight.w700 : FontWeight.w400,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : ListView.builder(
                                                  padding: const EdgeInsets.all(8),
                                                  itemCount: statusTasks.length,
                                                  itemBuilder: (context, index) {
                                                    final task = statusTasks[index];
                                                    return _BoardTaskCard(
                                                      task: task,
                                                      accent: accent,
                                                      colors: colors,
                                                      onTap: () => context.push('/main/task-detail', extra: task),
                                                    );
                                                  },
                                                ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          // Add-column card
                          GestureDetector(
                            onTap: showCreateStatusDialog,
                            child: Container(
                              width: 130,
                              decoration: BoxDecoration(
                                color: colors.surface.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colors.border,
                                  strokeAlign: BorderSide.strokeAlignInside,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.10),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.add_rounded, size: 22, color: colors.primary),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Add Column',
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
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
// Board building blocks
// ---------------------------------------------------------------------------

class _HeaderIconButton extends StatelessWidget {
  final IconData icon;
  final dynamic colors;
  final VoidCallback onTap;

  const _HeaderIconButton({required this.icon, required this.colors, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: colors.border),
          ),
          child: Icon(icon, size: 18, color: colors.text),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color background;
  final Color foreground;

  const _StatChip({
    required this.label,
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: foreground),
          ),
        ],
      ),
    );
  }
}

class _EmptyBoard extends StatelessWidget {
  final dynamic colors;
  final VoidCallback onAddColumn;

  const _EmptyBoard({required this.colors, required this.onAddColumn});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.view_kanban_outlined, size: 42, color: colors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Your board is empty',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.text),
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first status column to start\norganising tasks visually.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, height: 1.5, color: colors.textSecondary),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAddColumn,
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add first column'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Draggable task card used inside every board column. Long-press starts the
/// drag (feedback card mirrors the real one), tap opens the task detail.
class _BoardTaskCard extends StatelessWidget {
  final Task task;
  final Color accent;
  final dynamic colors;
  final VoidCallback onTap;

  const _BoardTaskCard({
    required this.task,
    required this.accent,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overdue = task.isOverdue;
    return LongPressDraggable<Task>(
      data: task,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Container(
          width: 250,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withValues(alpha: 0.6), width: 1.4),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 34,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  task.title,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: colors.text),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
      childWhenDragging: Opacity(
        opacity: 0.35,
        child: Container(
          height: 76,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent, width: 1.4),
          ),
        ),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: overdue ? colors.error.withValues(alpha: 0.45) : colors.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: overdue ? colors.error : accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          task.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                            height: 1.25,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (task.description != null && task.description!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              task.description!,
                              style: TextStyle(
                                fontSize: 11.5,
                                height: 1.35,
                                color: colors.textSecondary,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            if (task.epic != null && task.epic!.trim().isNotEmpty)
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colors.primary.withValues(alpha: 0.07),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    task.epic!,
                                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            const Spacer(),
                            if (overdue)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(Icons.warning_amber_rounded, size: 13, color: colors.error),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: overdue
                                    ? colors.error.withValues(alpha: 0.12)
                                    : colors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                formatDate(task.endDate),
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: overdue ? colors.error : colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (task.assignedTo != null && task.assignedTo!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              children: [
                                for (int i = 0; i < task.assignedTo!.length && i < 3; i++)
                                  Padding(
                                    padding: EdgeInsets.only(left: i > 0 ? -6 : 0),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: i.isEven
                                            ? colors.primary
                                            : colors.primaryDark,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: colors.surface, width: 2),
                                      ),
                                      child: Center(
                                        child: Text(
                                          task.assignedTo![i][0].toUpperCase(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (task.assignedTo!.length > 3)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      '+${task.assignedTo!.length - 3}',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
