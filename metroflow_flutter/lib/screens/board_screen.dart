import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../models/task_status.dart';
import '../utils/app_toast.dart';

class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends ConsumerState<BoardScreen> {
  List<Task> tasks = [];
  List<TaskStatus> taskStatuses = [];
  bool isLoading = true;
  bool isRefreshing = false;
  String? draggingTaskId;

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  Future<void> fetchData() async {
    try {
      setState(() => isRefreshing = true);
      final api = ApiService();
      
      // Fetch both tasks and statuses
      final tasksResponse = await api.getTasks(params: {'limit': 1000});
      final statusesResponse = await api.getTaskStatuses();
      
      if (mounted) {
        final tasksData = tasksResponse.data;
        final statusesData = statusesResponse.data;
        
        if (tasksData is Map && tasksData['success'] == true) {
          final body = tasksData['data'];
          final newTasks = (body is Map ? body['tasks'] as List? : tasksData['tasks'] as List?)
              ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
          setState(() => tasks = newTasks);
        }
        
        if (statusesData is Map && statusesData['success'] == true) {
          final newStatuses = (statusesData['data'] as List?)
              ?.map((e) => TaskStatus.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
          setState(() => taskStatuses = newStatuses);
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch data: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
        });
      }
    }
  }

  Map<String, List<Task>> get groupedTasks {
    final Map<String, List<Task>> groups = {};
    for (final status in taskStatuses) {
      groups[status.name] = [];
    }
    for (final task in tasks) {
      if (groups.containsKey(task.status)) {
        groups[task.status]!.add(task);
      } else if (taskStatuses.isNotEmpty) {
        groups[taskStatuses.first.name]!.add(task);
      }
    }
    return groups;
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

  String formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
    } catch (e) {
      return dateString;
    }
  }

  Future<void> updateTaskStatus(Task task, String newStatus) async {
    debugPrint('Updating task ${task.id} to status $newStatus');
    // First, update local state for immediate UI feedback
    setState(() {
      final index = tasks.indexWhere((t) => t.id == task.id);
      if (index != -1) {
        tasks[index] = Task(
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
      }
    });

    // Then, make the API call to update on backend
    try {
      final api = ApiService();
      await api.updateTask(task.id, {'status': newStatus});
      debugPrint('Successfully updated task ${task.id} on backend');
    } catch (e) {
      debugPrint('Failed to update task status on backend: $e');
      // If API fails, revert back
      setState(() {
        final index = tasks.indexWhere((t) => t.id == task.id);
        if (index != -1) {
          tasks[index] = task;
        }
      });
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

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (isLoading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Board',
                        style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.text),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.touch_app, size: 14, color: colors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            'Swipe to scroll • Long press to drag tasks',
                            style: TextStyle(fontSize: 12, color: colors.textSecondary),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: showCreateStatusDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Column'),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => context.go('/main/create-task'),
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.add, color: Colors.white, size: 24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: fetchData,
                color: colors.primary,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  scrollDirection: Axis.horizontal,
                  children: [
                    ...taskStatuses.map((status) {
                      final statusTasks = groupedTasks[status.name] ?? [];
                      final screenWidth = MediaQuery.of(context).size.width;
                      final columnWidth = screenWidth * 0.85 < 280 ? 280.0 : screenWidth * 0.85;
                      return Container(
                        width: columnWidth,
                        margin: const EdgeInsets.only(right: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: colors.border),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    margin: const EdgeInsets.only(right: 8),
                                    decoration: BoxDecoration(
                                      color: getStatusColor(status.name),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      status.name,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: colors.text,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      statusTasks.length.toString(),
                                      style: TextStyle(
                                        color: colors.primary,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            Expanded(
                              child: DragTarget<Task>(
                                onWillAcceptWithDetails: (details) {
                                  debugPrint('DragTarget ${status.name} onWillAcceptWithDetails: ${details.data.title}');
                                  return true;
                                },
                                onAcceptWithDetails: (details) {
                                  final task = details.data;
                                  debugPrint('Dropped task: ${task.title} into status: ${status.name}');
                                  if (task.status != status.name) {
                                    updateTaskStatus(task, status.name);
                                  }
                                },
                                onLeave: (data) {
                                  debugPrint('DragTarget ${status.name} onLeave');
                                },
                                builder: (context, candidateData, rejectedData) {
                                  return Container(
                                    constraints: const BoxConstraints.expand(),
                                    decoration: BoxDecoration(
                                      color: candidateData.isNotEmpty
                                          ? colors.primary.withValues(alpha: 0.05)
                                          : colors.surfaceVariant,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: candidateData.isNotEmpty ? colors.primary : colors.border,
                                        width: candidateData.isNotEmpty ? 2 : 1,
                                      ),
                                    ),
                                    child: statusTasks.isEmpty
                                        ? Center(
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.inbox, color: colors.textSecondary, size: 32),
                                                const SizedBox(height: 8),
                                                Text(
                                                  'No tasks',
                                                  style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                                ),
                                              ],
                                            ),
                                          )
                                        : ListView.builder(
                                            padding: const EdgeInsets.all(8),
                                            itemCount: statusTasks.length,
                                            itemBuilder: (context, index) {
                                              final task = statusTasks[index];
                                              return LongPressDraggable<Task>(
                                                data: task,
                                                onDragStarted: () {
                                                  debugPrint('Drag started for task: ${task.title} (id: ${task.id})');
                                                },
                                                onDragEnd: (details) {
                                                  debugPrint('Drag ended for task: ${task.title}');
                                                },
                                                onDragCompleted: () {
                                                  debugPrint('Drag completed for task: ${task.title}');
                                                },
                                                onDraggableCanceled: (velocity, offset) {
                                                  debugPrint('Drag canceled for task: ${task.title}');
                                                },
                                                feedback: Container(
                                                  width: 280,
                                                  margin: const EdgeInsets.only(bottom: 8),
                                                  padding: const EdgeInsets.all(12),
                                                  decoration: BoxDecoration(
                                                    color: colors.surface,
                                                    border: Border.all(color: colors.border),
                                                    borderRadius: BorderRadius.circular(12),
                                                    boxShadow: [
                                                      BoxShadow(
                                                        color: Colors.black.withValues(alpha: 0.1),
                                                        blurRadius: 10,
                                                        offset: const Offset(0, 4),
                                                      ),
                                                    ],
                                                  ),
                                                  child: Text(
                                                    task.title,
                                                    style: TextStyle(
                                                      fontSize: 14,
                                                      fontWeight: FontWeight.w600,
                                                      color: colors.text,
                                                    ),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                childWhenDragging: Container(
                                                  height: 80,
                                                  margin: const EdgeInsets.only(bottom: 8),
                                                  decoration: BoxDecoration(
                                                    color: colors.surface.withValues(alpha: 0.5),
                                                    borderRadius: BorderRadius.circular(12),
                                                    border: Border.all(color: colors.border, width: 2),
                                                  ),
                                                ),
                                                child: GestureDetector(
                                                  behavior: HitTestBehavior.translucent,
                                                  onTap: () => context.go('/main/task-detail', extra: task),
                                                  child: Container(
                                                    margin: const EdgeInsets.only(bottom: 8),
                                                    padding: const EdgeInsets.all(12),
                                                    decoration: BoxDecoration(
                                                      color: colors.surface,
                                                      border: Border.all(
                                                        color: task.isOverdue ? colors.error : colors.border,
                                                      ),
                                                      borderRadius: BorderRadius.circular(12),
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(
                                                          task.title,
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w600,
                                                            color: colors.text,
                                                          ),
                                                          maxLines: 2,
                                                          overflow: TextOverflow.ellipsis,
                                                        ),
                                                        if (task.description != null)
                                                          Padding(
                                                            padding: const EdgeInsets.only(top: 4),
                                                            child: Text(
                                                              task.description!,
                                                              style: TextStyle(
                                                                fontSize: 12,
                                                                color: colors.textSecondary,
                                                              ),
                                                              maxLines: 2,
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                          ),
                                                        const SizedBox(height: 8),
                                                        Row(
                                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                          children: [
                                                            if (task.epic != null)
                                                              Text(
                                                                '📁 ${task.epic}',
                                                                style: TextStyle(
                                                                  fontSize: 10,
                                                                  color: colors.textSecondary,
                                                                ),
                                                              ),
                                                            Text(
                                                              formatDate(task.endDate),
                                                              style: TextStyle(
                                                                fontSize: 10,
                                                                color: colors.textSecondary,
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
                                                                      width: 24,
                                                                      height: 24,
                                                                      decoration: BoxDecoration(
                                                                        color: colors.primary,
                                                                        shape: BoxShape.circle,
                                                                        border: Border.all(color: colors.surface, width: 2),
                                                                      ),
                                                                      child: Center(
                                                                        child: Text(
                                                                          task.assignedTo![i][0].toUpperCase(),
                                                                          style: const TextStyle(
                                                                            color: Colors.white,
                                                                            fontSize: 10,
                                                                            fontWeight: FontWeight.w600,
                                                                          ),
                                                                        ),
                                                                      ),
                                                                    ),
                                                                  ),
                                                                if (task.assignedTo!.length > 3)
                                                                  Padding(
                                                                    padding: const EdgeInsets.only(left: 8),
                                                                    child: Text(
                                                                      '+${task.assignedTo!.length - 3}',
                                                                      style: TextStyle(
                                                                        fontSize: 10,
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
                    GestureDetector(
                      onTap: showCreateStatusDialog,
                      child: Container(
                        width: 120,
                        margin: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: colors.surface.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.add_circle_outline, size: 40, color: colors.textSecondary),
                            const SizedBox(height: 8),
                            Text(
                              'Add Column',
                              style: TextStyle(color: colors.textSecondary, fontWeight: FontWeight.w500),
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
