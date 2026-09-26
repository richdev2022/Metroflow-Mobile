import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../theme/app_theme.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../models/epic.dart';
import '../widgets/modern_ui.dart';
import 'bulk_create_tasks_screen.dart';

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
              'Supported columns: Title, Description, Epic, Start Date, End Date, Status.',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 16),
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

  String get selectedEpicLabel {
    if (selectedEpic == 'all') return 'All Epics';
    for (final epic in epics) {
      if (epic.id == selectedEpic) return epic.name;
    }
    return 'Selected Epic';
  }

  List<_TaskFilterOption> get _statusOptions => const [
        _TaskFilterOption(value: 'all', label: 'All'),
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
        return AppTheme.colors.textSecondary;
      default:
        return AppTheme.colors.textSecondary;
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

  IconData _statusIcon(String status) {
    switch (status) {
      case 'completed':
        return Icons.check_circle_outline_rounded;
      case 'in_progress':
        return Icons.autorenew_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: colors.primary, size: 18),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: colors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
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
      return SafeArea(
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: const [
            SkeletonCard(),
            SkeletonCard(),
            SkeletonCard(),
            SkeletonCard(),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.background,
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
                        Row(
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
                            const SizedBox(width: 4),
                            Text(
                              '${selectedTasks.length} selected',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.text,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: colors.error.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: IconButton(
                                icon: Icon(Icons.delete_outline, color: colors.error),
                                onPressed: handleBulkDelete,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          '$total tasks',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        const Spacer(),
                        _buildActionButton(
                          icon: Icons.upload_file,
                          label: 'Import',
                          onTap: _showImportModal,
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () => context.go('/main/create-task'),
                          child: Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: colors.primary,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: colors.primary.withValues(alpha: 0.35),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(Icons.add, color: Colors.white, size: 22),
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: ModernSearchField(
                controller: searchController,
                hintText: 'Search tasks...',
                onChanged: (value) => setState(() => searchQuery = value),
                onClear: searchQuery.isEmpty
                    ? null
                    : () {
                        searchController.clear();
                        setState(() => searchQuery = '');
                      },
              ),
            ),
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                itemCount: _statusOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final option = _statusOptions[index];
                  return ModernFilterChip(
                    label: option.label,
                    selected: selectedStatus == option.value,
                    onTap: () {
                      setState(() => selectedStatus = option.value);
                      fetchData(1, true);
                    },
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              child: _TaskFilterDropdown(
                label: 'Epic',
                valueLabel: selectedEpicLabel,
                options: _epicOptions,
                selectedValue: selectedEpic,
                onSelected: (value) => setState(() => selectedEpic = value),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => fetchData(1, true),
                color: colors.primary,
                child: filteredTasks.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 40),
                          EmptyState(
                            icon: Icons.list_alt_outlined,
                            title: 'No tasks found',
                            subtitle:
                                'Try a different filter, or create a task to get your team moving.',
                            actionLabel: 'New Task',
                            onAction: () => context.go('/main/create-task'),
                          ),
                        ],
                      )
                    : ListView.builder(
                        controller: scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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
                          final statusColor = getStatusColor(status);
                          return GestureDetector(
                            onTap: () {
                              if (isSelectionMode) {
                                toggleTaskSelection(task.id);
                              } else {
                                context.go('/main/task-detail', extra: task);
                              }
                            },
                            onLongPress: () => handleLongPress(task.id),
                            child: _TaskCard(
                              task: task,
                              colors: colors,
                              isSelected: isSelected,
                              isSelectionMode: isSelectionMode,
                              statusColor: statusColor,
                              statusIcon: _statusIcon(status),
                              formattedDate: formatDate(task.endDate),
                              epicLabel: task.epic,
                              onToggle: () => toggleTaskSelection(task.id),
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

class _TaskCard extends StatelessWidget {
  final Task task;
  final ThemeColors colors;
  final bool isSelected;
  final bool isSelectionMode;
  final Color statusColor;
  final IconData statusIcon;
  final String formattedDate;
  final String? epicLabel;
  final VoidCallback onToggle;

  const _TaskCard({
    required this.task,
    required this.colors,
    required this.isSelected,
    required this.isSelectionMode,
    required this.statusColor,
    required this.statusIcon,
    required this.formattedDate,
    required this.epicLabel,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected ? colors.primary.withValues(alpha: 0.08) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? colors.primary
              : (task.isOverdue ? colors.error.withValues(alpha: 0.5) : colors.border),
          width: isSelected ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.text.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status color leading bar
              Container(width: 5, color: statusColor),
              Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (isSelectionMode)
                          GestureDetector(
                            onTap: onToggle,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 10, top: 1),
                              child: Icon(
                                isSelected
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color:
                                    isSelected ? colors.primary : colors.borderVariant,
                                size: 21,
                              ),
                            ),
                          )
                        else
                          Padding(
                            padding: const EdgeInsets.only(right: 10, top: 1),
                            child: Icon(
                              statusIcon,
                              color: statusColor,
                              size: 19,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            task.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (task.description != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 29),
                        child: Text(
                          task.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textSecondary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 6,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (epicLabel != null && epicLabel!.isNotEmpty)
                                ModernBadge(
                                  label: epicLabel!,
                                  color: colors.primary,
                                  icon: Icons.folder_outlined,
                                ),
                              ModernBadge(
                                label: task.isOverdue
                                    ? 'Overdue · $formattedDate'
                                    : 'Due $formattedDate',
                                color: task.isOverdue ? colors.error : colors.textSecondary,
                                icon: Icons.schedule,
                              ),
                            ],
                          ),
                        ),
                        if (task.assignedTo != null && task.assignedTo!.isNotEmpty)
                          SizedBox(
                            width: 66,
                            height: 26,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                for (int i = 0;
                                    i < task.assignedTo!.length && i < 2;
                                    i++)
                                  Positioned(
                                    left: i * 18.0,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: colors.surface, width: 2),
                                      ),
                                      child: AvatarInitials(
                                        name: task.assignedTo![i],
                                        radius: 12,
                                      ),
                                    ),
                                  ),
                                if (task.assignedTo!.length > 2)
                                  Positioned(
                                    left: 36,
                                    child: Container(
                                      width: 26,
                                      height: 26,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: colors.surfaceVariant,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: colors.surface, width: 2),
                                      ),
                                      child: Text(
                                        '+${task.assignedTo!.length - 2}',
                                        style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                    ),
                                  ),
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
      borderRadius: BorderRadius.circular(14),
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(Icons.folder_outlined, size: 18, color: colors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                valueLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: colors.text,
                ),
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                borderRadius: BorderRadius.circular(14),
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
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
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
