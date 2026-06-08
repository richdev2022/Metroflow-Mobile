import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api.dart';
import '../models/epic.dart';
import '../models/task.dart';
import '../models/team_member.dart';
import '../theme/app_theme.dart';

class CreateTaskScreen extends ConsumerStatefulWidget {
  const CreateTaskScreen({super.key});

  @override
  ConsumerState<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends ConsumerState<CreateTaskScreen> {
  // For multiple tasks
  final List<Map<String, dynamic>> _tasks = [];
  
  // Epic Details
  final _sprintController = TextEditingController();
  final _epicStartDateController = TextEditingController();
  final _epicEndDateController = TextEditingController();
  final List<String> _epicAssignedToIds = [];
  List<Epic> _epics = [];
  Epic? _selectedEpic;
  
  // Task Details
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final List<String> _taskAssignedToIds = [];
  final List<String> _taskImages = [];
  
  bool _isLoading = false;
  bool _isFetching = true;
  List<TeamMember> _teamMembers = [];
  Task? _editingTask;
  bool _didLoadRouteTask = false;
  bool _isMultiTaskMode = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
    // Initialize with one empty task if multi-task mode
    _tasks.add(_createEmptyTask());
  }

  Map<String, dynamic> _createEmptyTask() {
    return {
      'title': '',
      'description': '',
      'startDate': '',
      'endDate': '',
      'assigneeIds': <String>[],
      'images': <String>[],
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadRouteTask) return;
    _didLoadRouteTask = true;
    final extra = GoRouterState.of(context).extra;
    if (extra is Task) {
      _editingTask = extra;
      _isMultiTaskMode = false;
      _titleController.text = extra.title;
      _descriptionController.text = extra.description ?? '';
      _startDateController.text = extra.startDate;
      _endDateController.text = extra.endDate;
      _taskAssignedToIds.addAll(extra.assignedTo ?? []);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _sprintController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _epicStartDateController.dispose();
    _epicEndDateController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final api = ApiService();
      final teamRes = await api.getTeam();
      final epicsRes = await api.getEpics();
      if (teamRes.statusCode == 200) {
        final data = teamRes.data;
        if (data['success'] == true) {
          setState(() {
            _teamMembers = ((data['data'] as List<dynamic>?) ?? const [])
                .map((t) => TeamMember.fromJson(t as Map<String, dynamic>))
                .toList();
          });
        }
      }
      if (epicsRes.statusCode == 200) {
        final epicsData = epicsRes.data;
        if (epicsData['success'] == true) {
          setState(() {
            _epics = ((epicsData['data'] as List<dynamic>?) ?? const [])
                .map((e) => Epic.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Failed to fetch data: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _handleSubmit() async {
    if (_isMultiTaskMode) {
      // Validate all tasks
      for (var i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task['title'].toString().trim().isEmpty) {
          Fluttertoast.showToast(msg: 'Task ${i+1} requires a title');
          return;
        }
      }
      
      setState(() => _isLoading = true);
      try {
        final api = ApiService();
        // Convert tasks to payload
        final tasksPayload = _tasks.map((task) {
          return {
            'title': task['title'],
            'description': task['description'].toString().isNotEmpty ? task['description'] : null,
            'epicId': _selectedEpic?.id,
            'sprint': _sprintController.text.isNotEmpty ? _sprintController.text : null,
            'startDate': task['startDate'].toString().isNotEmpty ? task['startDate'] : null,
            'endDate': task['endDate'].toString().isNotEmpty ? task['endDate'] : null,
            'assignedTo': (task['assigneeIds'] as List<String>).isNotEmpty ? task['assigneeIds'] : null,
            'images': task['images'],
          };
        }).toList();
        
        await api.createBulkTasks(tasksPayload);
        Fluttertoast.showToast(msg: 'Tasks created successfully');
        if (mounted) context.go('/main/backlog');
      } catch (e) {
        Fluttertoast.showToast(
          msg: e.toString().replaceAll('Exception: ', ''),
          backgroundColor: AppColors.error,
        );
      } finally {
        setState(() => _isLoading = false);
      }
    } else {
      // Single task mode
      final title = _titleController.text.trim();
      if (title.isEmpty) {
        Fluttertoast.showToast(msg: 'Please enter a task title');
        return;
      }

      setState(() => _isLoading = true);
      try {
        final api = ApiService();
        final payload = {
          'title': title,
          'description': _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
          'epicId': _selectedEpic?.id,
          'sprint': _sprintController.text.isNotEmpty ? _sprintController.text : null,
          'startDate': _startDateController.text.isNotEmpty ? _startDateController.text : null,
          'endDate': _endDateController.text.isNotEmpty ? _endDateController.text : null,
          'assignedTo': _taskAssignedToIds.isNotEmpty ? _taskAssignedToIds : null,
          'images': _taskImages,
        };

        if (_editingTask == null) {
          await api.createTask(payload);
        } else {
          await api.updateTask(_editingTask!.id, payload);
        }
        Fluttertoast.showToast(msg: _editingTask == null ? 'Task created successfully' : 'Task updated successfully');
        if (mounted) context.go('/main/backlog');
      } catch (e) {
        Fluttertoast.showToast(
          msg: e.toString().replaceAll('Exception: ', ''),
          backgroundColor: AppColors.error,
        );
      } finally {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getSelectedEpicAssigneesText() {
    if (_epicAssignedToIds.isEmpty) return 'Select team members for this epic...';
    if (_epicAssignedToIds.length == 1) {
      return _teamMembers.firstWhere((m) => m.id == _epicAssignedToIds[0], orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name;
    }
    return '${_epicAssignedToIds.length} people';
  }

  String _getSelectedTaskAssigneesText() {
    if (_taskAssignedToIds.isEmpty) return 'Select team members for this task...';
    if (_taskAssignedToIds.length == 1) {
      return _teamMembers.firstWhere((m) => m.id == _taskAssignedToIds[0], orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name;
    }
    return '${_taskAssignedToIds.length} people';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: _isFetching
            ? Center(child: CircularProgressIndicator(color: colors.primary))
            : Column(
                children: [
                  _buildHeader(colors),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _isMultiTaskMode
                          ? _buildMultiTaskUI(colors)
                          : _buildSingleTaskUI(colors),
                    ),
                  ),
                  _buildBottomButtons(colors),
                ],
              ),
      ),
    );
  }

  Widget _buildSingleTaskUI(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Epic Details
        _buildEpicDetailsSection(colors),
        const SizedBox(height: 24),
        // Task Details
        _buildTaskDetailsSection(colors),
      ],
    );
  }

  Widget _buildMultiTaskUI(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Epic Details
        _buildEpicDetailsSection(colors),
        const SizedBox(height: 24),
        // Tasks Section
        _buildTasksSection(colors),
      ],
    );
  }

  Widget _buildEpicDetailsSection(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Epic Details',
          style: TextStyle(
            color: colors.text,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        _buildEpicDropdown(colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildField(
                'Sprint',
                _sprintController,
                hint: 'Enter sprint name',
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateField(
                'Start Date',
                _epicStartDateController,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateField(
                'End Date',
                _epicEndDateController,
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPickerField(
          label: 'Assign Team Members (Epic Level)',
          value: _getSelectedEpicAssigneesText(),
          isPlaceholder: _epicAssignedToIds.isEmpty,
          onTap: () => _showTeamMemberPicker(
            _epicAssignedToIds,
            (updated) {
              setState(() {
                _epicAssignedToIds.clear();
                _epicAssignedToIds.addAll(updated);
              });
            },
          ),
          colors: colors,
        ),
      ],
    );
  }

  Widget _buildEpicDropdown(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Epic', style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _showEpicDialog(colors),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    _selectedEpic?.name ?? 'Select an epic',
                    style: TextStyle(
                      color: _selectedEpic == null ? colors.textSecondary : colors.text,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: colors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showEpicDialog(ThemeColors colors) async {
    final TextEditingController searchController = TextEditingController();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final filteredEpics = _epics
              .where((epic) =>
                  epic.name.toLowerCase().contains(searchController.text.toLowerCase()))
              .toList();

          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Epic',
                      style: TextStyle(color: colors.text, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.text),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: searchController,
                  style: TextStyle(color: colors.text),
                  decoration: InputDecoration(
                    hintText: 'Search epics...',
                    hintStyle: TextStyle(color: colors.textSecondary),
                    prefixIcon: Icon(Icons.search_outlined, color: colors.textSecondary),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.primary, width: 2),
                    ),
                    filled: true,
                    fillColor: colors.surfaceVariant,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  onChanged: (value) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () async {
                    final TextEditingController newEpicNameController = TextEditingController();
                    final TextEditingController newEpicDescController = TextEditingController();
                    if (mounted) Navigator.of(context).pop();
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Create New Epic'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextField(
                              controller: newEpicNameController,
                              style: TextStyle(color: colors.text),
                              decoration: InputDecoration(
                                labelText: 'Epic Name',
                                labelStyle: TextStyle(color: colors.textSecondary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.primary, width: 2),
                                ),
                                filled: true,
                                fillColor: colors.surfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: newEpicDescController,
                              style: TextStyle(color: colors.text),
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Description (Optional)',
                                labelStyle: TextStyle(color: colors.textSecondary),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.border),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(color: colors.primary, width: 2),
                                ),
                                filled: true,
                                fillColor: colors.surfaceVariant,
                              ),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text('Cancel', style: TextStyle(color: colors.text)),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              if (newEpicNameController.text.trim().isEmpty) return;
                              final navigator = Navigator.of(context);
                              try {
                                final api = ApiService();
                                final res = await api.createEpic({
                                  'name': newEpicNameController.text.trim(),
                                  'description': newEpicDescController.text.trim().isEmpty
                                      ? null
                                      : newEpicDescController.text.trim(),
                                });
                                if (res.statusCode == 200) {
                                  await _fetchData();
                                  if (mounted) navigator.pop();
                                }
                              } catch (e) {
                                debugPrint('Failed to create epic: $e');
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: colors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            ),
                            child: const Text('Create', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: colors.surfaceVariant,
                      border: Border.all(color: colors.border),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.add, color: colors.primary, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Create New Epic',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: filteredEpics.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final epic = filteredEpics[index];
                      final isSelected = _selectedEpic?.id == epic.id;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            _selectedEpic = epic;
                          });
                          Navigator.of(context).pop();
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                            border: isSelected ? Border.all(color: colors.primary, width: 2) : null,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      epic.name,
                                      style: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w500),
                                    ),
                                    if (epic.description != null && epic.description!.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        epic.description!,
                                        style: TextStyle(color: colors.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Icon(
                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                color: isSelected ? colors.primary : colors.textSecondary,
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
          );
        },
      ),
    );
  }

  Widget _buildTaskDetailsSection(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildField('Title', _titleController, hint: 'Task title', colors: colors),
        const SizedBox(height: 12),
        _buildField('Description', _descriptionController, hint: 'Task description', maxLines: 4, colors: colors),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateField('Start Date', _startDateController, colors: colors),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateField('End Date', _endDateController, colors: colors),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPickerField(
          label: 'Assign Team Members (Override Epic Assignment)',
          value: _getSelectedTaskAssigneesText(),
          isPlaceholder: _taskAssignedToIds.isEmpty,
          onTap: () => _showTeamMemberPicker(
            _taskAssignedToIds,
            (updated) {
              setState(() {
                _taskAssignedToIds.clear();
                _taskAssignedToIds.addAll(updated);
              });
            },
          ),
          colors: colors,
        ),
        const SizedBox(height: 12),
        _buildImagePicker(colors),
      ],
    );
  }

  Widget _buildTasksSection(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tasks',
              style: TextStyle(
                color: colors.text,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _tasks.add(_createEmptyTask());
                });
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Task'),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.surface,
                foregroundColor: colors.text,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: colors.border),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        ..._tasks.asMap().entries.map((entry) {
          final index = entry.key;
          final task = entry.value;
          return _buildTaskCard(index, task, colors);
        }),
      ],
    );
  }

  Widget _buildTaskCard(int index, Map<String, dynamic> task, ThemeColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Task ${index + 1}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: colors.text)),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: () {
                  setState(() {
                    _tasks.removeAt(index);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInlineField('Title', (value) {
            setState(() {
              task['title'] = value;
            });
          }, initialValue: task['title'], hint: 'Task title', colors: colors),
          const SizedBox(height: 12),
          _buildInlineField('Description', (value) {
            setState(() {
              task['description'] = value;
            });
          }, initialValue: task['description'], hint: 'Task description', maxLines: 3, colors: colors),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildInlineDateField('Start Date', (value) {
                  setState(() {
                    task['startDate'] = value;
                  });
                }, initialValue: task['startDate'], colors: colors),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildInlineDateField('End Date', (value) {
                  setState(() {
                    task['endDate'] = value;
                  });
                }, initialValue: task['endDate'], colors: colors),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInlinePickerField(
            label: 'Assign Team Members (Override Epic Assignment)',
            task: task,
            colors: colors,
          ),
          const SizedBox(height: 12),
          _buildInlineImagePicker(task: task, colors: colors),
        ],
      ),
    );
  }

  Widget _buildImagePicker(ThemeColors colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Images (Optional)', style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            );
            if (result != null) {
              setState(() {
                _taskImages.addAll(result.files.map((f) => f.path ?? '').where((p) => p.isNotEmpty));
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, color: colors.textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _taskImages.isEmpty ? 'Choose Files' : '${_taskImages.length} file(s) chosen',
                    style: TextStyle(
                      color: _taskImages.isEmpty ? colors.textSecondary : colors.text,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineImagePicker({
    required Map<String, dynamic> task,
    required ThemeColors colors,
  }) {
    final images = task['images'] as List<String>;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Images (Optional)', style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () async {
            final result = await FilePicker.platform.pickFiles(
              type: FileType.image,
              allowMultiple: true,
            );
            if (result != null) {
              setState(() {
                images.addAll(result.files.map((f) => f.path ?? '').where((p) => p.isNotEmpty));
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, color: colors.textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    images.isEmpty ? 'Choose Files' : '${images.length} file(s) chosen',
                    style: TextStyle(
                      color: images.isEmpty ? colors.textSecondary : colors.text,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlinePickerField({
    required String label,
    required Map<String, dynamic> task,
    required ThemeColors colors,
  }) {
    final selectedIds = task['assigneeIds'] as List<String>;
    String valueText;
    if (selectedIds.isEmpty) {
      valueText = 'Select team members for this task...';
    } else if (selectedIds.length == 1) {
      valueText = _teamMembers.firstWhere((m) => m.id == selectedIds[0], orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name;
    } else {
      valueText = '${selectedIds.length} people';
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: () => _showTeamMemberPicker(
            selectedIds,
            (updated) {
              setState(() {
                selectedIds.clear();
                selectedIds.addAll(updated);
              });
            },
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    valueText,
                    style: TextStyle(
                      color: selectedIds.isEmpty ? colors.textSecondary : colors.text,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: colors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineField(String label, ValueChanged<String> onChanged, {String? initialValue, String? hint, int maxLines = 1, required ThemeColors colors}) {
    final controller = TextEditingController(text: initialValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.text)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          onChanged: onChanged,
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            filled: true,
            fillColor: colors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildInlineDateField(String label, ValueChanged<String> onChanged, {String? initialValue, required ThemeColors colors}) {
    final controller = TextEditingController(text: initialValue);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.text)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () async {
            final initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: initialDate,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              final dateText = '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}';
              controller.text = dateText;
              onChanged(dateText);
            }
          },
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: 'mm/dd/yyyy',
            hintStyle: TextStyle(color: colors.textSecondary),
            suffixIcon: Icon(Icons.calendar_today_outlined, color: colors.textSecondary, size: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            filled: true,
            fillColor: colors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: colors.surface),
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/main/backlog');
              }
            },
            icon: Icon(Icons.close, color: colors.text),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _editingTask == null ? 'Create Task' : 'Edit Task',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: colors.text),
            ),
          ),
          if (_editingTask == null) ...[
            // Toggle for single/multi task mode
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colors.background,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildModeButton('Single', !_isMultiTaskMode, colors),
                  _buildModeButton('Multiple', _isMultiTaskMode, colors),
                ],
              ),
            ),
            const SizedBox(width: 12),
            TextButton(
              onPressed: () => context.go('/main/bulk-create-tasks'),
              child: Text(
                'Bulk Create',
                style: TextStyle(color: colors.primary, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomButtons(ThemeColors colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Spacer(),
          OutlinedButton(
            onPressed: () => context.go('/main/backlog'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text('Cancel', style: TextStyle(color: colors.text)),
          ),
          const SizedBox(width: 12),
          ElevatedButton(
            onPressed: _isLoading ? null : _handleSubmit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    _editingTask == null ? 'Create' : 'Save Changes',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String label, bool isSelected, ThemeColors colors) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isMultiTaskMode = label == 'Multiple';
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? colors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  void _showTeamMemberPicker(List<String> selectedIds, ValueChanged<List<String>> onUpdate) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final colors = AppTheme.colors;
          return Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Select Team Members',
                      style: TextStyle(color: colors.text, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: colors.text),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _teamMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final member = _teamMembers[index];
                      final isSelected = selectedIds.contains(member.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              selectedIds.remove(member.id);
                            } else {
                              selectedIds.add(member.id);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: colors.surfaceVariant,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  member.name,
                                  style: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w500),
                                ),
                              ),
                              Icon(
                                isSelected ? Icons.check_circle : Icons.circle_outlined,
                                color: isSelected ? colors.primary : colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      onUpdate(List.from(selectedIds));
                      Navigator.of(context).pop();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: colors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Done',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {String? hint, int maxLines = 1, required ThemeColors colors}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.text)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            filled: true,
            fillColor: colors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$month/$day/${date.year}';
  }

  Future<void> _selectDate(TextEditingController controller) async {
    final initialDate = DateTime.tryParse(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => controller.text = _formatDate(picked));
  }

  Widget _buildDateField(String label, TextEditingController controller, {required ThemeColors colors}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: colors.text)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          readOnly: true,
          onTap: () => _selectDate(controller),
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: 'mm/dd/yyyy',
            hintStyle: TextStyle(color: colors.textSecondary),
            suffixIcon: Icon(Icons.calendar_today_outlined, color: colors.textSecondary, size: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
            filled: true,
            fillColor: colors.surfaceVariant,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ],
    );
  }

  Widget _buildPickerField({
    required String label,
    required String value,
    required bool isPlaceholder,
    required VoidCallback onTap,
    required ThemeColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    value,
                    style: TextStyle(
                      color: isPlaceholder ? colors.textSecondary : colors.text,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(Icons.keyboard_arrow_down, color: colors.textSecondary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
