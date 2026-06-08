import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xlsx;
import '../services/api.dart';
import '../models/epic.dart';
import '../models/team_member.dart';
import '../theme/app_theme.dart';

class BulkCreateTasksScreen extends ConsumerStatefulWidget {
  const BulkCreateTasksScreen({super.key});

  @override
  ConsumerState<BulkCreateTasksScreen> createState() => _BulkCreateTasksScreenState();
}

class _BulkCreateTask {
  final String title;
  final String? description;
  final String? epic;
  final String? sprint;
  final String? startDate;
  final String? endDate;
  final List<String>? assignedTo;
  final List<String>? images;

  _BulkCreateTask({
    required this.title,
    this.description,
    this.epic,
    this.sprint,
    this.startDate,
    this.endDate,
    this.assignedTo,
    this.images,
  });

  Map<String, dynamic> toJson() => {
    'title': title,
    'description': description,
    'epic': epic,
    'sprint': sprint,
    'startDate': startDate,
    'endDate': endDate,
    'assignedTo': assignedTo,
    'images': images,
  };
}

class _BulkCreateTasksScreenState extends ConsumerState<BulkCreateTasksScreen> {
  final List<_BulkCreateTask> _tasks = [];
  bool _isLoading = false;
  bool _isFetching = true;
  List<TeamMember> _teamMembers = [];
  List<Epic> _epics = [];
  final _epicNameController = TextEditingController();
  final _sprintController = TextEditingController();
  final _epicStartDateController = TextEditingController();
  final _epicEndDateController = TextEditingController();
  final List<String> _epicAssignedTo = [];
  Epic? _selectedEpic;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _tasks.add(_createEmptyTask());
  }

  @override
  void dispose() {
    _epicNameController.dispose();
    _sprintController.dispose();
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

  _BulkCreateTask _createEmptyTask() {
    return _BulkCreateTask(
      title: '',
      description: '',
      epic: null,
      sprint: null,
      startDate: null,
      endDate: null,
      assignedTo: [],
      images: [],
    );
  }

  Future<void> _addTaskFromExcel() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
    );

    if (result == null) return;

    try {
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to read file')),
          );
        }
        return;
      }
      final excel = xlsx.Excel.decodeBytes(bytes);
      final sheet = excel.sheets.values.first;
      final rows = sheet.rows;

      if (rows.isEmpty) return;

      final newTasks = <_BulkCreateTask>[];
      for (var i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.isEmpty) continue;
        if (row[0] == null) continue;
        newTasks.add(_BulkCreateTask(
          title: row[0]?.value?.toString() ?? '',
          description: row[1]?.value?.toString(),
          epic: row[2]?.value?.toString(),
          sprint: row[3]?.value?.toString(),
          startDate: row[4]?.value?.toString(),
          endDate: row[5]?.value?.toString(),
          assignedTo: [],
          images: [],
        ));
      }

      setState(() {
        _tasks.addAll(newTasks);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to parse Excel: $e')),
        );
      }
    }
  }

  void _addTask() {
    setState(() {
      _tasks.add(_createEmptyTask());
    });
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
    });
  }

  void _updateTask(int index, _BulkCreateTask task) {
    setState(() {
      _tasks[index] = task;
    });
  }

  Future<void> _submitTasks() async {
    if (_tasks.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add at least one task')),
        );
      }
      return;
    }

    for (var i = 0; i < _tasks.length; i++) {
      if (_tasks[i].title.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Task ${i + 1} requires a title')),
          );
        }
        return;
      }
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final api = ApiService();
      final tasksPayload = _tasks.map((task) {
        return {
          ...task.toJson(),
          'epicId': _selectedEpic?.id,
        };
      }).toList();
      await api.createBulkTasks(tasksPayload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tasks created successfully')),
        );
        context.go('/main/backlog');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create tasks: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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
    setState(() => controller.text = '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}');
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(colors),
            Expanded(
              child: _isFetching
                  ? Center(child: CircularProgressIndicator(color: colors.primary))
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildEpicDetails(colors),
                          const SizedBox(height: 24),
                          _buildTasksSection(colors),
                        ],
                      ),
                    ),
            ),
            if (_tasks.isNotEmpty)
              Padding(
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
                      onPressed: _isLoading ? null : _submitTasks,
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
                          : const Text(
                              'Create Tasks',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
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
  }

  Widget _buildHeader(ThemeColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: colors.surface),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.close, color: colors.text),
            onPressed: () => context.go('/main/backlog'),
          ),
          Text(
            'Add Tasks to Epic',
            style: TextStyle(
              color: colors.text,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 48), // To balance the close button
        ],
      ),
    );
  }

  Widget _buildEpicDetails(ThemeColors colors) {
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
              child: _buildTextField(
                label: 'Sprint',
                controller: _sprintController,
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
                label: 'Start Date',
                controller: _epicStartDateController,
                colors: colors,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDateField(
                label: 'End Date',
                controller: _epicEndDateController,
                colors: colors,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildPickerField(
          label: 'Assign Team Members (Epic Level)',
          value: _epicAssignedTo.isEmpty
              ? 'Select team members for this epic...'
              : _epicAssignedTo.length == 1
                  ? _teamMembers.firstWhere((m) => m.id == _epicAssignedTo.first, orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name
                  : '${_epicAssignedTo.length} people',
          isPlaceholder: _epicAssignedTo.isEmpty,
          onTap: () => _showTeamMemberPicker(_epicAssignedTo, (updated) {
            setState(() {
              _epicAssignedTo.clear();
              _epicAssignedTo.addAll(updated);
            });
          }),
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
              borderRadius: BorderRadius.circular(4),
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
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: _addTaskFromExcel,
                  icon: const Icon(Icons.upload, size: 18),
                  label: const Text('Upload Excel'),
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
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _addTask,
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
          ],
        ),
        const SizedBox(height: 16),
        ..._tasks.asMap().entries.map((entry) {
          return _TaskFormCard(
            index: entry.key,
            task: entry.value,
            onUpdate: (t) => _updateTask(entry.key, t),
            onRemove: () => _removeTask(entry.key),
            teamMembers: _teamMembers,
          );
        }),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    required ThemeColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: TextStyle(color: colors.text),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: colors.textSecondary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
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

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required ThemeColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
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
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
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
              borderRadius: BorderRadius.circular(4),
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
}

class _TaskFormCard extends StatefulWidget {
  final int index;
  final _BulkCreateTask task;
  final ValueChanged<_BulkCreateTask> onUpdate;
  final VoidCallback onRemove;
  final List<TeamMember> teamMembers;

  const _TaskFormCard({
    required this.index,
    required this.task,
    required this.onUpdate,
    required this.onRemove,
    required this.teamMembers,
  });

  @override
  State<_TaskFormCard> createState() => _TaskFormCardState();
}

class _TaskFormCardState extends State<_TaskFormCard> {
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _startDateController;
  late TextEditingController _endDateController;
  late List<String> _assignedTo;
  late List<String> _images;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.task.title);
    _descriptionController = TextEditingController(text: widget.task.description);
    _startDateController = TextEditingController(text: widget.task.startDate);
    _endDateController = TextEditingController(text: widget.task.endDate);
    _assignedTo = List.from(widget.task.assignedTo ?? []);
    _images = List.from(widget.task.images ?? []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    super.dispose();
  }

  void _update() {
    widget.onUpdate(_BulkCreateTask(
      title: _titleController.text,
      description: _descriptionController.text.isEmpty ? null : _descriptionController.text,
      epic: widget.task.epic,
      sprint: widget.task.sprint,
      startDate: _startDateController.text.isEmpty ? null : _startDateController.text,
      endDate: _endDateController.text.isEmpty ? null : _endDateController.text,
      assignedTo: _assignedTo,
      images: _images,
    ));
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
    setState(() => controller.text = '${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}/${picked.year}');
    _update();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Task ${widget.index + 1}',
                style: TextStyle(
                  color: colors.text,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: widget.onRemove,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleController,
            style: TextStyle(color: colors.text),
            decoration: InputDecoration(
              labelText: 'Title',
              labelStyle: TextStyle(color: colors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              filled: true,
              fillColor: colors.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            style: TextStyle(color: colors.text),
            decoration: InputDecoration(
              labelText: 'Description',
              labelStyle: TextStyle(color: colors.textSecondary),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(4),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
              filled: true,
              fillColor: colors.surfaceVariant,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (_) => _update(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildDateField(
                  label: 'Start Date',
                  controller: _startDateController,
                  colors: colors,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildDateField(
                  label: 'End Date',
                  controller: _endDateController,
                  colors: colors,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPickerField(
            label: 'Assign Team Members (Override Epic Assignment)',
            value: _assignedTo.isEmpty
                ? 'Select team members for this task...'
                : _assignedTo.length == 1
                    ? widget.teamMembers.firstWhere((m) => m.id == _assignedTo.first, orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name
                    : '${_assignedTo.length} people',
            isPlaceholder: _assignedTo.isEmpty,
            onTap: () => _showTeamMemberPicker(),
            colors: colors,
          ),
          const SizedBox(height: 12),
          _buildImagePicker(colors),
        ],
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required TextEditingController controller,
    required ThemeColors colors,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: colors.text, fontSize: 12, fontWeight: FontWeight.bold)),
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
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(4),
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
              borderRadius: BorderRadius.circular(4),
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
                _images.addAll(result.files.map((f) => f.path ?? '').where((p) => p.isNotEmpty));
              });
              _update();
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colors.surfaceVariant,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.image_outlined, color: colors.textSecondary, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _images.isEmpty ? 'Choose Files' : '${_images.length} file(s) chosen',
                    style: TextStyle(
                      color: _images.isEmpty ? colors.textSecondary : colors.text,
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

  void _showTeamMemberPicker() {
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
                    itemCount: widget.teamMembers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final member = widget.teamMembers[index];
                      final isSelected = _assignedTo.contains(member.id);
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setModalState(() {
                            if (isSelected) {
                              _assignedTo.remove(member.id);
                            } else {
                              _assignedTo.add(member.id);
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
                      _update();
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
}
