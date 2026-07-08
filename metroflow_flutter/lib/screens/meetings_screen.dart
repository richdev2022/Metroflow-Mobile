import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';
import '../services/socket_service.dart';
import '../models/meeting.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import 'jitsi_call_screen.dart';

class MeetingsScreen extends ConsumerStatefulWidget {
  const MeetingsScreen({super.key});

  @override
  ConsumerState<MeetingsScreen> createState() => _MeetingsScreenState();
}

class _MeetingsScreenState extends ConsumerState<MeetingsScreen> {
  final ApiService _api = ApiService();
  final SocketService _socket = SocketService();
  List<Meeting> _meetings = [];
  List<User> _teamMembers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
    _loadTeamMembers();
    _socket.onMeetingCreated = (data) {
      setState(() {
        _meetings.add(Meeting.fromJson(data));
        _meetings.sort((a, b) => a.startTime.compareTo(b.startTime));
      });
    };
    _socket.onMeetingUpdated = (data) {
      setState(() {
        final index = _meetings.indexWhere((m) => m.id == data['id']);
        if (index != -1) {
          _meetings[index] = Meeting.fromJson(data);
          _meetings.sort((a, b) => a.startTime.compareTo(b.startTime));
        }
      });
    };
    _socket.onMeetingDeleted = (meetingId) {
      setState(() {
        _meetings.removeWhere((m) => m.id == meetingId);
      });
    };
  }

  Future<void> _loadMeetings() async {
    try {
      final response = await _api.getMeetings();
      if (response.data['success'] == true) {
        final data = response.data['data']['meetings'] as List;
        setState(() {
          _meetings = data.map((json) => Meeting.fromJson(json)).toList()
            ..sort((a, b) => a.startTime.compareTo(b.startTime));
        });
      }
    } catch (e) {
      Logger.error('Error loading meetings: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadTeamMembers() async {
    try {
      final response = await _api.getTeam();
      if (response.data['success'] == true) {
        final data = response.data['data'] as List;
        setState(() {
          _teamMembers = data.map((json) => User.fromJson(json)).toList();
        });
      }
    } catch (e) {
      Logger.error('Error loading team members: $e');
    }
  }

  Future<void> _showCreateMeetingDialog([Meeting? meeting]) async {
    showDialog(
      context: context,
      builder: (context) => _MeetingDialog(
        teamMembers: _teamMembers,
        meeting: meeting,
        onSaved: (updatedMeeting) {
          if (meeting == null) {
            setState(() {
              _meetings.add(updatedMeeting);
              _meetings.sort((a, b) => a.startTime.compareTo(b.startTime));
            });
          } else {
            setState(() {
              final index = _meetings.indexWhere((m) => m.id == updatedMeeting.id);
              if (index != -1) {
                _meetings[index] = updatedMeeting;
                _meetings.sort((a, b) => a.startTime.compareTo(b.startTime));
              }
            });
          }
        },
      ),
    );
  }

  Future<void> _deleteMeeting(Meeting meeting) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Meeting'),
        content: Text('Are you sure you want to delete "${meeting.title}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await _api.deleteMeeting(meeting.id);
        setState(() {
          _meetings.remove(meeting);
        });
      } catch (e) {
        Logger.error('Error deleting meeting: $e');
      }
    }
  }

  Future<void> _joinMeeting(Meeting meeting) async {
    if (meeting.meetingUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Meeting link is not available yet')),
      );
      return;
    }

    await JitsiCallScreen.showModal(
      context: context,
      meetingUrl: meeting.meetingUrl,
      title: meeting.title,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Meetings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _meetings.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.event_outlined, size: 80, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No meetings scheduled', style: TextStyle(color: Colors.grey[600])),
                      const SizedBox(height: 8),
                      Text('Create your first meeting!', style: TextStyle(color: Colors.grey[500])),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _meetings.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final meeting = _meetings[index];
                    return Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: InkWell(
                        onTap: () => _showCreateMeetingDialog(meeting),
                        borderRadius: BorderRadius.circular(12),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      meeting.title,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                  PopupMenuButton(
                                    onSelected: (value) {
                                      if (value == 'edit') {
                                        _showCreateMeetingDialog(meeting);
                                      } else if (value == 'delete') {
                                        _deleteMeeting(meeting);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                                      const PopupMenuItem(value: 'delete', child: Text('Delete')),
                                    ],
                                  ),
                                ],
                              ),
                              if (meeting.description.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(meeting.description),
                                ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Icon(Icons.access_time, size: 18, color: Theme.of(context).primaryColor),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${DateFormat.yMMMd().format(meeting.startTime)} • ${DateFormat.Hm().format(meeting.startTime)} - ${DateFormat.Hm().format(meeting.endTime)}',
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (meeting.attendees.isNotEmpty)
                                Text(
                                  '${meeting.attendees.length} attendee${meeting.attendees.length > 1 ? 's' : ''}',
                                  style: TextStyle(color: Colors.grey[600]),
                                ),
                              const SizedBox(height: 12),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.video_call),
                                  label: const Text('Join Meeting'),
                                  onPressed: () => _joinMeeting(meeting),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New Meeting'),
        onPressed: () => _showCreateMeetingDialog(),
      ),
    );
  }
}

class _MeetingDialog extends StatefulWidget {
  final List<User> teamMembers;
  final Meeting? meeting;
  final Function(Meeting) onSaved;

  const _MeetingDialog({
    required this.teamMembers,
    this.meeting,
    required this.onSaved,
  });

  @override
  State<_MeetingDialog> createState() => _MeetingDialogState();
}

class _MeetingDialogState extends State<_MeetingDialog> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  final List<String> _selectedAttendeeIds = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.meeting != null) {
      _titleController.text = widget.meeting!.title;
      _descriptionController.text = widget.meeting!.description;
      _startDate = widget.meeting!.startTime;
      _endDate = widget.meeting!.endTime;
      _selectedAttendeeIds.addAll(widget.meeting!.attendees.map((a) => a.userId));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime({required bool isStart}) async {
    final initialDate = isStart ? _startDate : _endDate;
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: initialDate,
    );
    if (date == null) return;
    if (!mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initialDate),
    );
    if (time == null) return;
    setState(() {
      final newDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _startDate = newDateTime;
        if (_endDate.isBefore(_startDate)) {
          _endDate = _startDate.add(const Duration(hours: 1));
        }
      } else {
        _endDate = newDateTime;
      }
    });
  }

  Future<void> _saveMeeting() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final data = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'startTime': _startDate.toUtc().toIso8601String(),
        'endTime': _endDate.toUtc().toIso8601String(),
        'timezone': 'UTC',
        'attendeeIds': _selectedAttendeeIds,
      };
      final response = widget.meeting == null
          ? await _api.createMeeting(data)
          : await _api.updateMeeting(widget.meeting!.id, data);

      if (response.data['success'] == true) {
        final meeting = Meeting.fromJson(response.data['data']);
        widget.onSaved(meeting);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      Logger.error('Error saving meeting: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.meeting == null ? 'New Meeting' : 'Edit Meeting'),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Sprint Planning',
                  ),
                  validator: (value) => value?.trim().isEmpty ?? true ? 'Required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. Weekly sprint planning meeting',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _pickDateTime(isStart: true),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Start Time',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text(DateFormat.yMMMd().add_Hm().format(_startDate)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _pickDateTime(isStart: false),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'End Time',
                      border: OutlineInputBorder(),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today),
                        const SizedBox(width: 8),
                        Text(DateFormat.yMMMd().add_Hm().format(_endDate)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Attendees', style: TextStyle(fontWeight: FontWeight.w500)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 150,
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.teamMembers.length,
                    itemBuilder: (context, index) {
                      final member = widget.teamMembers[index];
                      final isSelected = _selectedAttendeeIds.contains(member.id);
                      return CheckboxListTile(
                        title: Text(member.name),
                        subtitle: Text(member.email),
                        value: isSelected,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _selectedAttendeeIds.add(member.id);
                            } else {
                              _selectedAttendeeIds.remove(member.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _saveMeeting,
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
