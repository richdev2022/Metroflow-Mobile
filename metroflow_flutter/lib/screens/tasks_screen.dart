import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:metroflow_flutter/theme/app_theme.dart';
import 'package:metroflow_flutter/services/api.dart';
import 'package:metroflow_flutter/models/task.dart';
import 'package:metroflow_flutter/models/epic.dart';
import 'package:metroflow_flutter/screens/bulk_create_tasks_screen.dart';

class TasksScreen extends ConsumerStatefulWidget {
  const TasksScreen({super.key});

  @override
  ConsumerState<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends ConsumerState<TasksScreen> {
  List<Task> tasks = [];
  List<Epic> epics = [];
  bool isLoading = true;
  bool isRefreshing = false;
  String selectedStatus = 'all';
  String selectedEpic = 'all';
  String searchQuery = '';
  List<String> selectedTasks = [];
  bool isSelectionMode = false;
  int page = 1;
  bool hasMore = true;
  bool isLoadingMore = false;
  int total = 0;
  final ScrollController scrollController = ScrollController();
  final TextEditingController searchController = TextEditingController();

  void _showImportModal() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Tasks from Excel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Download the Excel template from the web version, fill it out, then upload here.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 8),
            const Text(
              'Format: Title (required), Description, Sprint, Start Date, End Date',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['xlsx', 'xls'],
                  );

                  if (result == null) return;

                  try {
                    final bytes = result.files.single.bytes;
                    if (bytes == null) {
                      if (!mounted) return;
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to read file')),
                        );
                      }
                      return;
                    }
                    final tasks = await BulkCreateTasksScreen.parseExcelFile(bytes);
                    if (!mounted) return;
                    if (context.mounted) {
                      Navigator.of(context).pop();
                      context.go('/main/bulk-create-tasks', extra: tasks);
                    }
                  } catch (e) {
                    if (!mounted) return;
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Failed to parse Excel: $e')),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('Upload Excel File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    fetchData(1, true);
    scrollController.addListener(() {
      if (scrollController.position.pixels >= scrollController.position.maxScrollExtent - 200) {
        loadMore();
      }
    });
  }

  @override
  void dispose() {
    scrollController.dispose();
    searchController.dispose();
    super.dispose();
  }

  Future<void> fetchData(int pageNumber, bool refresh) async {
    try {
      if (refresh) {
        setState(() => isRefreshing = true);
      } else if (pageNumber > 1) {
        setState(() => isLoadingMore = true);
      } else {
        setState(() => isLoading = true);
      }

      final params = <String, dynamic>{
        'page': pageNumber,
        'limit': 20,
      };
      if (selectedStatus != 'all') {
        params['status'] = selectedStatus;
      }

      final api = ApiService();
      final shouldFetchEpics = refresh || epics.isEmpty;
      final tasksResponse = await api.getTasks(params: params);
      final epicsResponse = shouldFetchEpics ? await api.getEpics() : null;

      if (mounted) {
        final tasksData = tasksResponse.data;
        if (tasksData is Map && tasksData['success'] == true) {
          final body = tasksData['data'];
          final newTasks = (body is Map ? body['tasks'] as List? : tasksData['tasks'] as List?)
              ?.map((e) => Task.fromJson(e as Map<String, dynamic>))
              .toList() ??
              [];
          setState(() {
            if (refresh) {
              tasks = newTasks;
            } else {
              tasks.addAll(newTasks);
            }
            hasMore = newTasks.length == 20;
            page = pageNumber;
            total = body is Map ? (body['total'] ?? total) : (tasksData['total'] ?? total);
          });
        }
        final epicsData = epicsResponse?.data;
        if (epicsData is Map && epicsData['success'] == true) {
          setState(() {
            epics = (epicsData['data'] as List?)
                ?.map((e) => Epic.fromJson(e as Map<String, dynamic>))
                .toList() ??
                [];
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch tasks: $e');
    } finally {
      if (mounted) {
        setState(() {
          isLoading = false;
          isRefreshing = false;
          isLoadingMore = false;
        });
      }
    }
  }

  void loadMore() {
    if (!isLoadingMore && hasMore) {
      fetchData(page + 1, false);
    }
  }

  List<Task> get filteredTasks {
    return tasks.where((task) {
      final matchesEpic = selectedEpic == 'all' || task.epicId == selectedEpic;
      final matchesSearch = searchQuery.isEmpty ||
          task.title.toLowerCase().contains(searchQuery.toLowerCase()) ||
          (task.description?.toLowerCase().contains(searchQuery.toLowerCase()) ?? false);
      return matchesEpic && matchesSearch;
    }).toList();
  }

  String get selectedStatusLabel {
    return _statusOptions
        .firstWhere((option) => option.value == selectedStatus)
        .label;
  }

  String get selectedEpicLabel {
    if (selectedEpic == 'all') return 'All Epics';
    for (final epic in epics) {
      if (epic.id == selectedEpic) return epic.name;
    }
    return 'Selected Epic';
  }

  List<_TaskFilterOption> get _statusOptions => const [
        _TaskFilterOption(value: 'all', label: 'All Statuses'),
        _TaskFilterOption(value: 'pending', label: 'Pending'),
        _TaskFilterOption(value: 'in_progress', label: 'In Progress'),
        _TaskFilterOption(value: 'completed', label: 'Completed'),
      ];

  List<_TaskFilterOption> get _epicOptions => [
        const _TaskFilterOption(value: 'all', label: 'All Epics'),
        ...epics.map((epic) => _TaskFilterOption(value: epic.id, label: epic.name)),
      ];

  void toggleTaskSelection(String taskId) {
    setState(() {
      if (selectedTasks.contains(taskId)) {
        selectedTasks.remove(taskId);
      } else {
        selectedTasks.add(taskId);
      }
    });
  }

  void handleLongPress(String taskId) {
    setState(() {
      isSelectionMode = true;
      selectedTasks = [taskId];
    });
  }

  Future<void> handleBulkDelete() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Tasks'),
        content: Text('Are you sure you want to delete ${selectedTasks.length} task(s)?'),
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
      await api.bulkDeleteTasks(selectedTasks);
      if (mounted) {
        setState(() {
          tasks.removeWhere((t) => selectedTasks.contains(t.id));
          selectedTasks = [];
          isSelectionMode = false;
        });
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Tasks deleted successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Failed to delete: $e')),
        );
      }
    }
  }

  Color getStatusColor(String status) {
    switch (status) {
      case 'completed':
        return AppTheme.colors.success;
      case 'in_progress':
        return AppTheme.colors.warning;
      case 'pending':
        return const Color(0xFF9E9E9E);
      default:
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 20),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: colors.text,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
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
              child: isSelectionMode
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            setState(() {
                              isSelectionMode = false;
                              selectedTasks = [];
                            });
                          },
                        ),
                        Text(
                          '${selectedTasks.length} selected',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: handleBulkDelete,
                        ),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Tasks',
                          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.text),
                        ),
                        Row(
                          children: [
                            _buildActionButton(
                              icon: Icons.upload_file,
                              label: 'Import Tasks',
                              onTap: _showImportModal,
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Icon(Icons.search_outlined, color: colors.textSecondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Search tasks...',
                          hintStyle: TextStyle(color: colors.textSecondary),
                        ),
                        style: TextStyle(color: colors.text, fontSize: 16),
                        onChanged: (value) => setState(() => searchQuery = value),
                      ),
                    ),
                    if (searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          searchController.clear();
                          setState(() => searchQuery = '');
                        },
                        child: Icon(Icons.close_outlined, color: colors.textSecondary),
                      ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: _TaskFilterDropdown(
                      label: 'Status',
                      valueLabel: selectedStatusLabel,
                      options: _statusOptions,
                      selectedValue: selectedStatus,
                      onSelected: (value) {
                        setState(() => selectedStatus = value);
                        fetchData(1, true);
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TaskFilterDropdown(
                      label: 'Epic',
                      valueLabel: selectedEpicLabel,
                      options: _epicOptions,
                      selectedValue: selectedEpic,
                      onSelected: (value) => setState(() => selectedEpic = value),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => fetchData(1, true),
                color: colors.primary,
                child: filteredTasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.list_outlined, size: 64, color: colors.textSecondary),
                            const SizedBox(height: 16),
                            Text(
                              'No tasks found',
                              style: TextStyle(fontSize: 16, color: colors.textSecondary),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        itemCount: filteredTasks.length + (isLoadingMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == filteredTasks.length) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: CircularProgressIndicator(color: colors.primary),
                              ),
                            );
                          }
                          final task = filteredTasks[index];
                          final isSelected = selectedTasks.contains(task.id);
                          final status = task.status;
                          return GestureDetector(
                            onTap: () {
                              if (isSelectionMode) {
                                toggleTaskSelection(task.id);
                              } else {
                                context.go('/main/task-detail', extra: task);
                              }
                            },
                            onLongPress: () => handleLongPress(task.id),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF2563EB).withValues(alpha: 0.1) : colors.surface,
                                border: Border.all(
                                  color: isSelected
                                      ? colors.primary
                                      : (task.isOverdue ? colors.error : colors.border),
                                  width: 2,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: getStatusColor(status),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          task.title,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: colors.text,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      if (task.isOverdue)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: colors.error,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Text(
                                            'Overdue',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (task.description != null)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      child: Text(
                                        task.description!,
                                        style: TextStyle(fontSize: 14, color: colors.textSecondary),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (task.epic != null)
                                        Text(
                                          '📁 ${task.epic}',
                                          style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                        ),
                                      Text(
                                        formatDate(task.endDate),
                                        style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                      ),
                                    ],
                                  ),
                                  if (task.assignedTo != null && task.assignedTo!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Row(
                                        children: [
                                          for (int i = 0; i < task.assignedTo!.length && i < 3; i++)
                                            Padding(
                                              padding: EdgeInsets.only(left: i > 0 ? -8 : 0),
                                              child: Container(
                                                width: 28,
                                                height: 28,
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
                                                      fontSize: 12,
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          if (task.assignedTo!.length > 3)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 12),
                                              child: Text(
                                                '+${task.assignedTo!.length - 3}',
                                                style: TextStyle(
                                                  fontSize: 12,
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
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskFilterOption {
  final String value;
  final String label;

  const _TaskFilterOption({required this.value, required this.label});
}

class _TaskFilterDropdown extends StatelessWidget {
  final String label;
  final String valueLabel;
  final String selectedValue;
  final List<_TaskFilterOption> options;
  final ValueChanged<String> onSelected;

  const _TaskFilterDropdown({
    required this.label,
    required this.valueLabel,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    valueLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.text),
                  ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: colors.primary),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _TaskFilterPicker(
        title: label,
        selectedValue: selectedValue,
        options: options,
        onSelected: onSelected,
      ),
    );
  }
}

class _TaskFilterPicker extends StatefulWidget {
  final String title;
  final String selectedValue;
  final List<_TaskFilterOption> options;
  final ValueChanged<String> onSelected;

  const _TaskFilterPicker({
    required this.title,
    required this.selectedValue,
    required this.options,
    required this.onSelected,
  });

  @override
  State<_TaskFilterPicker> createState() => _TaskFilterPickerState();
}

class _TaskFilterPickerState extends State<_TaskFilterPicker> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final filtered = widget.options
        .where((option) => option.label.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return FractionallySizedBox(
      heightFactor: 0.7,
      child: Container(
        padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: colors.borderVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Select ${widget.title}',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text),
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colors.text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.surfaceVariant,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Search ${widget.title.toLowerCase()}...',
                  prefixIcon: Icon(Icons.search, color: colors.textSecondary),
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Text('No options found', style: TextStyle(color: colors.textSecondary)),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => Divider(color: colors.border, height: 1),
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        final selected = option.value == widget.selectedValue;
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            option.label,
                            style: TextStyle(
                              color: selected ? colors.primary : colors.text,
                              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                          trailing: selected ? Icon(Icons.check_circle, color: colors.primary) : null,
                          onTap: () {
                            widget.onSelected(option.value);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
