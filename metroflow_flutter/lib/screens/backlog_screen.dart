import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api.dart';
import '../models/task.dart';
import '../theme/app_theme.dart';
import './bulk_create_tasks_screen.dart';

class BacklogScreen extends StatefulWidget {
  const BacklogScreen({super.key});

  @override
  State<BacklogScreen> createState() => _BacklogScreenState();
}

class _BacklogScreenState extends State<BacklogScreen> {
  final ScrollController _scrollController = ScrollController();
  List<Task> _tasks = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _page = 1;
  String _searchQuery = '';

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
    _scrollController.addListener(_handleScroll);
    _fetchData();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_handleScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _fetchData({int pageNumber = 1, bool refresh = false}) async {
    if (!refresh && pageNumber > 1 && (!_hasMore || _isLoadingMore)) return;

    try {
      setState(() {
        if (refresh) {
          _isLoading = _tasks.isEmpty;
        } else if (pageNumber > 1) {
          _isLoadingMore = true;
        } else {
          _isLoading = true;
        }
      });
      final api = ApiService();
      final response = await api.getTasks(params: {
        'page': pageNumber,
        'limit': 20,
      });

      if (response.statusCode == 200) {
        final data = response.data;
        if (data['success'] == true) {
          final tasksData = (data['data']['tasks'] ?? []) as List;
          final newTasks = tasksData
              .map((t) => Task.fromJson(t as Map<String, dynamic>))
              .toList();
          setState(() {
            if (refresh) {
              _tasks = newTasks;
            } else {
              _tasks = [..._tasks, ...newTasks];
            }
            _hasMore = newTasks.length == 20;
            _page = pageNumber;
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch backlog: $e');
    } finally {
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _searchQuery.isNotEmpty) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 120) {
      _fetchData(pageNumber: _page + 1);
    }
  }

  List<Task> get _filteredTasks {
    final q = _searchQuery.toLowerCase();
    return _tasks.where((task) {
      return task.title.toLowerCase().contains(q) ||
          (task.description ?? '').toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () => _fetchData(refresh: true),
                      child: _filteredTasks.isEmpty
                          ? _buildEmptyState()
                          : ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              itemCount: _filteredTasks.length + (_isLoadingMore ? 1 : 0),
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, index) {
                                if (index == _filteredTasks.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                                  );
                                }
                                final task = _filteredTasks[index];
                                return _TaskCard(
                                  task: task,
                                  onTap: () {
                                    context.go('/main/task-detail', extra: task);
                                  },
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

  Widget _buildHeader() {
    final colors = AppTheme.colors;
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: colors.text),
                onPressed: () => context.go('/main'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Backlog',
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: colors.text),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage backlog tasks and assign them to Epics',
                      style: TextStyle(fontSize: 14, color: colors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search tasks...',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    prefixIcon: Icon(Icons.search_outlined, color: colors.textSecondary),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    filled: true,
                    fillColor: colors.surface,
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
              ),
              const SizedBox(width: 12),
              _buildActionButton(
                icon: Icons.upload_file,
                label: 'Import Tasks',
                onTap: _showImportModal,
              ),
              const SizedBox(width: 8),
              _buildActionButton(
                icon: Icons.add_task,
                label: 'Add Task',
                onTap: () => context.go('/main/create-task'),
              ),
            ],
          ),
        ],
      ),
    );
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        children: [
          Icon(Icons.archive_outlined, size: 64, color: AppTheme.colors.textSecondary),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isNotEmpty ? 'No results found' : 'Backlog is empty',
            style: TextStyle(color: AppTheme.colors.textSecondary, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.colors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Icon(Icons.chevron_right, color: AppTheme.colors.textSecondary),
              ],
            ),
            if (task.description != null && task.description!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                task.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.colors.textSecondary,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (task.epic != null)
                  Text(
                    '\u{1F4C1} ${task.epic}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                Text(
                  'Added ${DateTime.tryParse(task.createdAt)?.toLocal().toString().split(' ')[0] ?? task.createdAt}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
