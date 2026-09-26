import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../services/api.dart';

import '../services/socket_service.dart';
import '../models/meeting.dart';
import '../models/user.dart';
import '../utils/logger.dart';
import '../utils/app_toast.dart';
import '../theme/app_theme.dart';
import '../utils/timezone_data.dart';
import '../widgets/modern_ui.dart';
import 'video_call_screen.dart';

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
  String _filterStatus = 'upcoming';
  late final void Function(dynamic) _meetingCreatedHandler;
  late final void Function(dynamic) _meetingUpdatedHandler;
  late final void Function(dynamic) _meetingDeletedHandler;

  @override
  void initState() {
    super.initState();
    _loadMeetings();
    _loadTeamMembers();
    _meetingCreatedHandler = (data) {
      if (!mounted) return;
      if (data is! Map) return;
      setState(() {
        _upsertMeeting(Meeting.fromJson(Map<String, dynamic>.from(data)));
      });
    };
    _meetingUpdatedHandler = (data) {
      if (!mounted) return;
      if (data is! Map) return;
      setState(() {
        _upsertMeeting(Meeting.fromJson(Map<String, dynamic>.from(data)));
      });
    };
    _meetingDeletedHandler = (meetingId) {
      if (!mounted) return;
      final id = meetingId is Map ? meetingId['id'] : meetingId;
      setState(() {
        _meetings.removeWhere((item) => item.id == id);
      });
    };
    _socket.onMeetingCreated = _meetingCreatedHandler;
    _socket.onMeetingUpdated = _meetingUpdatedHandler;
    _socket.onMeetingDeleted = _meetingDeletedHandler;
  }

  @override
  void dispose() {
    if (_socket.onMeetingCreated == _meetingCreatedHandler) {
      _socket.onMeetingCreated = null;
    }
    if (_socket.onMeetingUpdated == _meetingUpdatedHandler) {
      _socket.onMeetingUpdated = null;
    }
    if (_socket.onMeetingDeleted == _meetingDeletedHandler) {
      _socket.onMeetingDeleted = null;
    }
    super.dispose();
  }

  Future<void> _loadMeetings() async {
    try {
      final response = await _api.getMeetings();
      if (response.data['success'] == true) {
        if (!mounted) return;
        final responseData = response.data['data'];
        final data = responseData is Map && responseData['meetings'] is List
            ? responseData['meetings'] as List
            : responseData is List
                ? responseData
                : <dynamic>[];
        setState(() {
          _meetings = data
              .whereType<Map>()
              .map((json) => Meeting.fromJson(Map<String, dynamic>.from(json)))
              .toList()
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

  void _upsertMeeting(Meeting meeting) {
    final index = _meetings.indexWhere((item) => item.id == meeting.id);
    if (index == -1) {
      _meetings.add(meeting);
    } else {
      _meetings[index] = meeting;
    }
    _meetings.sort((a, b) => a.startTime.compareTo(b.startTime));
  }

  Future<void> _loadTeamMembers() async {
    try {
      final response = await _api.getTeam();
      if (response.data['success'] == true) {
        if (!mounted) return;
        final data = response.data['data'] is List ? response.data['data'] as List : <dynamic>[];
        setState(() {
          _teamMembers = data
              .whereType<Map>()
              .map((json) => User.fromJson(Map<String, dynamic>.from(json)))
              .toList();
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
          setState(() {
            _upsertMeeting(updatedMeeting);
          });
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiService.extractErrorMessage(e))),
          );
        }
      }
    }
  }

  Future<void> _joinMeeting(Meeting meeting) async {
    try {
      final response = await _api.joinMeeting(meeting.id);
      if (response.data['success'] == true && mounted) {
        final userName = await StorageService().getUserName();
        await VideoCallScreen.showModal(
          context: context,
          roomId: meeting.id,
          title: meeting.title,
          isMeeting: true,
          userName: userName,
          onLeave: () => _leaveMeeting(meeting.id),
        );
      }
    } catch (e) {
      Logger.error('Error joining meeting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  Future<void> _leaveMeeting(String meetingId) async {
    try {
      await _api.leaveMeeting(meetingId);
      if (mounted) {
        await _loadMeetings();
      }
    } catch (e) {
      Logger.error('Error leaving meeting: $e');
    }
  }

  void _copyMeetingLink(Meeting meeting) {
    final link = meeting.meetingUrl.isNotEmpty
        ? meeting.meetingUrl
        : (meeting.meetingCode.isNotEmpty ? meeting.meetingCode : meeting.id);
    Clipboard.setData(ClipboardData(text: link));
    AppToast.show('Meeting link copied to clipboard');
  }

  List<Meeting> get _filteredMeetings {
    final now = DateTime.now();
    return _meetings.where((meeting) {
      switch (_filterStatus) {
        case 'cancelled':
          return meeting.status == 'cancelled';
        case 'completed':
          return meeting.status == 'completed' ||
              (meeting.status != 'cancelled' && meeting.endTime.isBefore(now));
        default:
          return meeting.status != 'cancelled' &&
              meeting.status != 'completed' &&
              !meeting.endTime.isBefore(now);
      }
    }).toList();
  }

  int _countFor(String status) {
    final now = DateTime.now();
    return _meetings.where((meeting) {
      switch (status) {
        case 'cancelled':
          return meeting.status == 'cancelled';
        case 'completed':
          return meeting.status == 'completed' ||
              (meeting.status != 'cancelled' && meeting.endTime.isBefore(now));
        default:
          return meeting.status != 'cancelled' &&
              meeting.status != 'completed' &&
              !meeting.endTime.isBefore(now);
      }
    }).length;
  }

  bool _isMeetingLive(Meeting meeting) {
    final now = DateTime.now();
    return meeting.status != 'cancelled' &&
        meeting.status != 'completed' &&
        !meeting.startTime.isAfter(now) &&
        meeting.endTime.isAfter(now);
  }

  Color _statusColorFor(ThemeColors colors, Meeting meeting) {
    if (meeting.status == 'cancelled') return colors.error;
    if (meeting.status == 'completed' || meeting.endTime.isBefore(DateTime.now())) {
      return colors.textSecondary;
    }
    if (_isMeetingLive(meeting)) return colors.success;
    return colors.primary;
  }

  String _statusLabelFor(Meeting meeting) {
    if (meeting.status == 'cancelled') return 'Cancelled';
    if (meeting.status == 'completed' || meeting.endTime.isBefore(DateTime.now())) {
      return 'Completed';
    }
    if (_isMeetingLive(meeting)) return 'Live';
    return 'Scheduled';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;

    if (_isLoading) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: const [
            SkeletonCard(height: 110),
            SkeletonCard(height: 110),
            SkeletonCard(height: 110),
            SkeletonCard(height: 110),
          ],
        ),
      );
    }

    final filtered = _filteredMeetings;

    return Scaffold(
      backgroundColor: colors.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
              child: Text(
                'Meetings',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.text,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _buildSegmentedTabs(colors),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadMeetings,
                color: colors.primary,
                child: filtered.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 40),
                          _emptyStateForTab(colors),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(24, 12, 24, 96),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final meeting = filtered[index];
                          return _MeetingCard(
                            meeting: meeting,
                            colors: colors,
                            isLive: _isMeetingLive(meeting),
                            statusColor: _statusColorFor(colors, meeting),
                            statusLabel: _statusLabelFor(meeting),
                            onJoin: () => _joinMeeting(meeting),
                            onCopy: () => _copyMeetingLink(meeting),
                            onEdit: () => _showCreateMeetingDialog(meeting),
                            onDelete: () => _deleteMeeting(meeting),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: ModernFab(
        icon: Icons.video_call_rounded,
        label: 'New Meeting',
        onPressed: () => _showCreateMeetingDialog(),
      ),
    );
  }

  Widget _buildSegmentedTabs(ThemeColors colors) {
    final tabs = <_MeetingTab>[
      const _MeetingTab(value: 'upcoming', label: 'Upcoming', icon: Icons.schedule_rounded),
      const _MeetingTab(value: 'completed', label: 'Completed', icon: Icons.check_circle_outline_rounded),
      const _MeetingTab(value: 'cancelled', label: 'Cancelled', icon: Icons.cancel_outlined),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: tabs.map((tab) {
          final selected = _filterStatus == tab.value;
          final count = _countFor(tab.value);
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _filterStatus = tab.value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? colors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: colors.text.withValues(alpha: 0.06),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      tab.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? colors.text : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: selected ? colors.primary : colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _emptyStateForTab(ThemeColors colors) {
    switch (_filterStatus) {
      case 'completed':
        return const EmptyState(
          icon: Icons.check_circle_outline_rounded,
          title: 'No completed meetings',
          subtitle: 'Meetings that wrap up will show up here with their notes.',
          tint: AppColors.success,
        );
      case 'cancelled':
        return const EmptyState(
          icon: Icons.event_busy_outlined,
          title: 'No cancelled meetings',
          subtitle: 'Nothing was cancelled — your calendar is clean.',
          tint: AppColors.error,
        );
      default:
        return EmptyState(
          icon: Icons.event_outlined,
          title: 'No upcoming meetings',
          subtitle: 'Create your first meeting and invite your team to join.',
          actionLabel: 'New Meeting',
          onAction: () => _showCreateMeetingDialog(),
        );
    }
  }
}

class _MeetingTab {
  final String value;
  final String label;
  final IconData icon;

  const _MeetingTab({
    required this.value,
    required this.label,
    required this.icon,
  });
}

class _MeetingCard extends StatelessWidget {
  final Meeting meeting;
  final ThemeColors colors;
  final bool isLive;
  final Color statusColor;
  final String statusLabel;
  final VoidCallback onJoin;
  final VoidCallback onCopy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _MeetingCard({
    required this.meeting,
    required this.colors,
    required this.isLive,
    required this.statusColor,
    required this.statusLabel,
    required this.onJoin,
    required this.onCopy,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final attendeeCount = meeting.attendees.length;
    final canJoin = meeting.status != 'cancelled' && meeting.status != 'completed';

    return ModernCard(
      padding: EdgeInsets.zero,
      margin: EdgeInsets.zero,
      onTap: onEdit,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left time block
            Container(
            width: 78,
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                bottomLeft: Radius.circular(20),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  DateFormat.Hm().format(meeting.startTime),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('d MMM').format(meeting.startTime),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                ModernBadge(
                  label: statusLabel,
                  color: statusColor,
                  icon: isLive ? Icons.fiber_manual_record : null,
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          meeting.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'copy') {
                            onCopy();
                          } else if (value == 'edit') {
                            onEdit();
                          } else if (value == 'delete') {
                            onDelete();
                          }
                        },
                        icon: Icon(Icons.more_vert_rounded,
                            size: 20, color: colors.textSecondary),
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                              value: 'copy', child: Text('Copy link')),
                          const PopupMenuItem(value: 'edit', child: Text('Edit')),
                          const PopupMenuItem(
                              value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ],
                  ),
                  if (meeting.description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        meeting.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colors.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      ModernBadge(
                        label: meeting.timezone,
                        color: colors.primary,
                        icon: Icons.public_outlined,
                      ),
                      if (attendeeCount > 0)
                        ModernBadge(
                          label:
                              '$attendeeCount attendee${attendeeCount > 1 ? 's' : ''}',
                          color: const Color(0xFF7C3AED),
                          icon: Icons.people_outline,
                        ),
                      if (meeting.password != null && meeting.password!.isNotEmpty)
                        ModernBadge(
                          label: 'Password',
                          color: colors.warning,
                          icon: Icons.lock_outline,
                        ),
                    ],
                  ),
                  if (canJoin) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 40,
                      child: ElevatedButton.icon(
                        onPressed: onJoin,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isLive ? colors.success : colors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: Icon(
                          isLive ? Icons.videocam_rounded : Icons.video_call_outlined,
                          size: 18,
                        ),
                        label: Text(
                          isLive ? 'Join Live' : 'Join Meeting',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
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

const List<String> timezones = [
  'UTC',
  'America/New_York',
  'America/Chicago',
  'America/Denver',
  'America/Los_Angeles',
  'Europe/London',
  'Europe/Paris',
  'Europe/Berlin',
  'Asia/Dubai',
  'Asia/Dhaka',
  'Asia/Kolkata',
  'Asia/Singapore',
  'Asia/Tokyo',
  'Australia/Sydney',
  'Pacific/Auckland'
];

class _MeetingDialogState extends State<_MeetingDialog> {
  final ApiService _api = ApiService();
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _passwordController = TextEditingController();
  final _maxParticipantsController = TextEditingController(text: '100');
  final _timezoneSearchController = TextEditingController();
  DateTime _startDate = DateTime.now().add(const Duration(hours: 1));
  DateTime _endDate = DateTime.now().add(const Duration(hours: 2));
  String _selectedTimezone = 'UTC';
  String _searchTimezone = '';
  final List<String> _selectedAttendeeIds = [];
  bool _isInstant = false;
  bool _waitingRoomEnabled = false;
  bool _recordingEnabled = false;
  bool _screenSharingEnabled = true;
  bool _isSaving = false;
  bool _showTimezoneDropdown = false;

  @override
  void initState() {
    super.initState();
    if (widget.meeting != null) {
      _titleController.text = widget.meeting!.title;
      _descriptionController.text = widget.meeting!.description;
      _passwordController.text = widget.meeting!.password ?? '';
      _maxParticipantsController.text = widget.meeting!.maxParticipants.toString();
      _startDate = widget.meeting!.startTime;
      _endDate = widget.meeting!.endTime;
      _selectedTimezone = widget.meeting!.timezone;
      _isInstant = widget.meeting!.isInstant;
      _waitingRoomEnabled = widget.meeting!.waitingRoomEnabled;
      _recordingEnabled = widget.meeting!.recordingEnabled;
      _screenSharingEnabled = widget.meeting!.screenSharingEnabled;
      _selectedAttendeeIds.addAll(widget.meeting!.attendees.map((a) => a.userId));
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _passwordController.dispose();
    _maxParticipantsController.dispose();
    _timezoneSearchController.dispose();
    super.dispose();
  }

  List<Map<String, String>> get _filteredTimezones {
    if (_searchTimezone.isEmpty) return timezoneData;
    return timezoneData.where((tz) =>
        tz['label']!.toLowerCase().contains(_searchTimezone.toLowerCase()) ||
        tz['name']!.toLowerCase().contains(_searchTimezone.toLowerCase())
    ).toList();
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
    if (!_endDate.isAfter(_startDate)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('End time must be after start time')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final maxParticipants = int.tryParse(_maxParticipantsController.text.trim());
      if (maxParticipants == null || maxParticipants < 2) {
        throw const FormatException('Max participants must be at least 2');
      }

      final data = {
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'startTime': _startDate.toUtc().toIso8601String(),
        'endTime': _endDate.toUtc().toIso8601String(),
        'timezone': _selectedTimezone,
        'isInstant': _isInstant,
        'password': _passwordController.text.trim().isEmpty ? null : _passwordController.text.trim(),
        'maxParticipants': maxParticipants,
        'waitingRoomEnabled': _waitingRoomEnabled,
        'recordingEnabled': _recordingEnabled,
        'screenSharingEnabled': _screenSharingEnabled,
        'attendeeIds': _selectedAttendeeIds,
      };
      final response = widget.meeting == null
          ? await _api.createMeeting(data)
          : await _api.updateMeeting(widget.meeting!.id, data);

      if (response.data['success'] == true) {
        final responseData = response.data['data'];
        if (responseData is! Map) {
          throw const FormatException('Invalid meeting response');
        }
        final meeting = Meeting.fromJson(Map<String, dynamic>.from(responseData));
        widget.onSaved(meeting);
        if (mounted) Navigator.pop(context);
      }
    } catch (e) {
      Logger.error('Error saving meeting: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
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
              crossAxisAlignment: CrossAxisAlignment.start,
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
                SwitchListTile(
                  title: const Text('Instant Meeting'),
                  value: _isInstant,
                  onChanged: (value) {
                    setState(() {
                      _isInstant = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                if (!_isInstant) ...[
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
                ],
                const SizedBox(height: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Timezone', style: TextStyle(fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () {
                        setState(() {
                          _showTimezoneDropdown = !_showTimezoneDropdown;
                        });
                      },
                      child: InputDecorator(
                        decoration: InputDecoration(
                          border: const OutlineInputBorder(),
                          suffixIcon: Icon(
                            _showTimezoneDropdown ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                          ),
                        ),
                        child: Text(
                          timezoneData.firstWhere(
                            (tz) => tz['name'] == _selectedTimezone,
                            orElse: () => {'label': _selectedTimezone},
                          )['label']!,
                        ),
                      ),
                    ),
                    if (_showTimezoneDropdown)
                      Container(
                        margin: const EdgeInsets.only(top: 8),
                        constraints: const BoxConstraints(maxHeight: 200),
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.colors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: TextField(
                                controller: _timezoneSearchController,
                                decoration: const InputDecoration(
                                  hintText: 'Search timezones...',
                                  prefixIcon: Icon(Icons.search),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                onChanged: (value) {
                                  setState(() {
                                    _searchTimezone = value;
                                  });
                                },
                              ),
                            ),
                            Expanded(
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _filteredTimezones.length,
                                itemBuilder: (context, index) {
                                  final tz = _filteredTimezones[index];
                                  final isSelected = tz['name'] == _selectedTimezone;
                                  return ListTile(
                                    title: Text(tz['label']!),
                                    trailing: isSelected
                                        ? const Icon(Icons.check, color: AppColors.success)
                                        : null,
                                    onTap: () {
                                      setState(() {
                                        _selectedTimezone = tz['name']!;
                                        _showTimezoneDropdown = false;
                                        _searchTimezone = '';
                                        _timezoneSearchController.clear();
                                      });
                                    },
                                    dense: true,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  decoration: const InputDecoration(
                    labelText: 'Meeting Password (Optional)',
                    hintText: 'Enter password to secure the meeting',
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _maxParticipantsController,
                  decoration: const InputDecoration(
                    labelText: 'Max Participants',
                    hintText: '100',
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Waiting Room'),
                  subtitle: const Text('Participants wait in a room before joining'),
                  value: _waitingRoomEnabled,
                  onChanged: (value) {
                    setState(() {
                      _waitingRoomEnabled = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Enable Recording'),
                  subtitle: const Text('Allow recording the meeting'),
                  value: _recordingEnabled,
                  onChanged: (value) {
                    setState(() {
                      _recordingEnabled = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  title: const Text('Enable Screen Sharing'),
                  subtitle: const Text('Allow participants to share their screens'),
                  value: _screenSharingEnabled,
                  onChanged: (value) {
                    setState(() {
                      _screenSharingEnabled = value;
                    });
                  },
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Text('Attendees', style: TextStyle(fontWeight: FontWeight.w500)),
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
