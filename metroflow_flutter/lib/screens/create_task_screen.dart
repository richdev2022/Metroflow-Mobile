import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:fluttertoast/fluttertoast.dart';
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
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _sprintController = TextEditingController();
  final _startDateController = TextEditingController();
  final _endDateController = TextEditingController();
  final _dueDateController = TextEditingController();
  final _targetValueController = TextEditingController();
  final _accomplishedValueController = TextEditingController();
  final _epicNameController = TextEditingController();
  String? _selectedEpicId;
  final List<String> _selectedAssigneeIds = [];
  bool _isLoading = false;
  bool _isFetching = true;
  List<Epic> _epics = [];
  List<TeamMember> _teamMembers = [];
  Task? _editingTask;
  bool _didLoadRouteTask = false;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didLoadRouteTask) return;
    _didLoadRouteTask = true;
    final extra = GoRouterState.of(context).extra;
    if (extra is Task) {
      _editingTask = extra;
      _titleController.text = extra.title;
      _descriptionController.text = extra.description ?? '';
      _sprintController.text = extra.sprint ?? '';
      _startDateController.text = extra.startDate;
      _endDateController.text = extra.endDate;
      _dueDateController.text = extra.dueDate ?? '';
      _selectedEpicId = extra.epicId;
      _epicNameController.text = extra.epic ?? '';
      _targetValueController.text = extra.targetValue.toString();
      _accomplishedValueController.text = extra.accomplishedValue.toString();
      _selectedAssigneeIds.addAll(extra.assignedTo ?? []);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _sprintController.dispose();
    _startDateController.dispose();
    _endDateController.dispose();
    _dueDateController.dispose();
    _targetValueController.dispose();
    _accomplishedValueController.dispose();
    _epicNameController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final api = ApiService();
      final results = await Future.wait([
        api.getEpics(),
        api.getTeam(),
      ]);

      final epicsRes = results[0];
      if (epicsRes.statusCode == 200) {
        final data = epicsRes.data;
        if (data['success'] == true) {
          setState(() {
            _epics = ((data['data'] as List<dynamic>?) ?? const [])
                .map((e) => Epic.fromJson(e as Map<String, dynamic>))
                .toList();
          });
        }
      }

      final teamRes = results[1];
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
    } catch (e) {
      debugPrint('Failed to fetch data: $e');
    } finally {
      setState(() => _isFetching = false);
    }
  }

  Future<void> _handleSubmit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      Fluttertoast.showToast(msg: 'Please enter a task title');
      return;
    }

    // Get selected epic name
    final selectedEpic = _selectedEpicId != null
        ? _epics.firstWhere((e) => e.id == _selectedEpicId, orElse: () => Epic(id: '', name: '', businessId: '', status: '', createdAt: '', updatedAt: ''))
        : null;

    setState(() => _isLoading = true);
    try {
      final api = ApiService();
      final payload = {
        'title': title,
        'description': _descriptionController.text.isNotEmpty ? _descriptionController.text : null,
        'epicId': _selectedEpicId,
        'epic': selectedEpic?.name.isNotEmpty == true ? selectedEpic!.name : (_epicNameController.text.isNotEmpty ? _epicNameController.text : null),
        'sprint': _sprintController.text.isNotEmpty ? _sprintController.text : null,
        'startDate': _startDateController.text.isNotEmpty ? _startDateController.text : null,
        'endDate': _endDateController.text.isNotEmpty ? _endDateController.text : null,
        'dueDate': _dueDateController.text.isNotEmpty ? _dueDateController.text : null,
        'targetValue': _targetValueController.text.isNotEmpty ? double.tryParse(_targetValueController.text) : null,
        'accomplishedValue': _accomplishedValueController.text.isNotEmpty ? double.tryParse(_accomplishedValueController.text) : null,
        'assignedTo': _selectedAssigneeIds.isNotEmpty ? _selectedAssigneeIds : null,
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

  String _getSelectedEpicName() {
    return _epics.firstWhere((e) => e.id == _selectedEpicId, orElse: () => Epic(id: '', name: 'Select Epic', businessId: '', status: '', createdAt: '', updatedAt: '')).name;
  }

  String _getSelectedAssigneesText() {
    if (_selectedAssigneeIds.isEmpty) return 'Select Assignees';
    if (_selectedAssigneeIds.length == 1) {
      return _teamMembers.firstWhere((m) => m.id == _selectedAssigneeIds[0], orElse: () => TeamMember(id: '', name: '1 person', email: '', role: '', status: '')).name;
    }
    return '${_selectedAssigneeIds.length} people';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isFetching
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildHeader(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildField('Title *', _titleController, hint: 'Task title'),
                          _buildField('Description', _descriptionController, hint: 'Task description', maxLines: 4),
                          _buildPickerField(
                            label: 'Epic',
                            value: _getSelectedEpicName(),
                            onTap: _showEpicPicker,
                          ),
                          _buildField('Epic Name', _epicNameController, hint: 'Epic name (if not selecting from list)'),
                          _buildField('Sprint', _sprintController, hint: 'Sprint name'),
                          Row(
                            children: [
                              Expanded(child: _buildField('Start Date', _startDateController, hint: 'YYYY-MM-DD')),
                              const SizedBox(width: 12),
                              Expanded(child: _buildField('End Date', _endDateController, hint: 'YYYY-MM-DD')),
                            ],
                          ),
                          _buildField('Due Date', _dueDateController, hint: 'YYYY-MM-DD'),
                          Row(
                            children: [
                              Expanded(child: _buildField('Target Value', _targetValueController, hint: '0.0', keyboardType: TextInputType.number)),
                              const SizedBox(width: 12),
                              Expanded(child: _buildField('Accomplished Value', _accomplishedValueController, hint: '0.0', keyboardType: TextInputType.number)),
                            ],
                          ),
                          _buildPickerField(
                            label: 'Assignees',
                            value: _getSelectedAssigneesText(),
                            isPlaceholder: _selectedAssigneeIds.isEmpty,
                            onTap: _showAssigneePicker,
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleSubmit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: _isLoading
                                ? const CircularProgressIndicator(color: Colors.white)
                                : Text(
                                    _editingTask == null ? 'Create' : 'Save Changes',
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
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

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          IconButton(
            onPressed: () => context.go('/main/backlog'),
            icon: const Icon(Icons.close),
          ),
          Expanded(
            child: Text(
              _editingTask == null ? 'Create Task' : 'Edit Task',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showEpicPicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _pickerShell(
        title: 'Select Epic',
        child: ListView(
          shrinkWrap: true,
          children: [
            _pickerOption(
              label: 'None',
              selected: _selectedEpicId == null || _selectedEpicId!.isEmpty,
              onTap: () {
                setState(() => _selectedEpicId = null);
                Navigator.of(context).pop();
              },
            ),
            ..._epics.map((epic) => _pickerOption(
                  label: epic.name,
                  selected: _selectedEpicId == epic.id,
                  onTap: () {
                    setState(() => _selectedEpicId = epic.id);
                    Navigator.of(context).pop();
                  },
                )),
          ],
        ),
      ),
    );
  }

  void _showAssigneePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => _pickerShell(
          title: 'Select Assignees',
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: _teamMembers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = _teamMembers[index];
              final selected = _selectedAssigneeIds.contains(member.id);
              return _pickerOption(
                label: member.name,
                subtitle: member.role,
                selected: selected,
                onTap: () {
                  setState(() {
                    if (selected) {
                      _selectedAssigneeIds.remove(member.id);
                    } else {
                      _selectedAssigneeIds.add(member.id);
                    }
                  });
                  setModalState(() {});
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _pickerShell({required String title, required Widget child}) {
    final colors = AppTheme.colors;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
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
                  title,
                  style: TextStyle(color: colors.text, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: colors.text),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }

  Widget _pickerOption({
    required String label,
    String? subtitle,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final colors = AppTheme.colors;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: colors.text, fontSize: 16, fontWeight: FontWeight.w500)),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: colors.textSecondary, fontSize: 12)),
                  ],
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              color: selected ? colors.primary : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, {String? hint, int maxLines = 1, TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: maxLines,
            keyboardType: keyboardType,
            decoration: InputDecoration(
              hintText: hint,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              fillColor: AppTheme.colors.surface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPickerField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool isPlaceholder = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.colors.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(value, style: TextStyle(color: isPlaceholder ? AppTheme.colors.textSecondary : AppTheme.colors.text)),
                  Icon(Icons.arrow_drop_down, color: AppTheme.colors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
