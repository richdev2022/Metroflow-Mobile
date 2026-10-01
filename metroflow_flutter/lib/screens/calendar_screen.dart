import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/meeting.dart';
import '../services/api.dart';
import '../utils/logger.dart';
import '../theme/app_theme.dart';
import 'meetings_screen.dart' show showMeetingCreator;
import 'video_call_screen.dart';

/// Metricorex Calendar — Google-style month grid of scheduled meetings.
///
/// Each occurrence of a recurring meeting is its own meeting row (own join
/// code), so the grid shows and joins every occurrence independently.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final ApiService _api = ApiService();
  late DateTime _visibleMonth;
  DateTime? _selectedDay;
  Map<DateTime, List<Meeting>> _meetingsByDay = {};
  bool _loading = true;
  String? _error;

  static const List<String> _weekdayLabels = [
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
    _load();
  }

  DateTime get _monthWindowStart =>
      DateTime(_visibleMonth.year, _visibleMonth.month, 1).subtract(const Duration(days: 7));
  DateTime get _monthWindowEnd =>
      DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0, 23, 59, 59).add(const Duration(days: 7));

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _api.getMeetings(
        page: 1,
        limit: 200,
        from: _monthWindowStart.toUtc().toIso8601String(),
        to: _monthWindowEnd.toUtc().toIso8601String(),
      );
      if (response.data['success'] == true) {
        final data = response.data['data'];
        final rawMeetings = data is Map ? data['meetings'] : null;
        final map = <DateTime, List<Meeting>>{};
        if (rawMeetings is List) {
          for (final raw in rawMeetings) {
            if (raw is! Map) continue;
            final meeting = Meeting.fromJson(Map<String, dynamic>.from(raw));
            final start = meeting.startTime.toLocal();
            final key = DateTime(start.year, start.month, start.day);
            map.putIfAbsent(key, () => []).add(meeting);
          }
        }
        for (final list in map.values) {
          list.sort((a, b) => a.startTime.compareTo(b.startTime));
        }
        if (mounted) {
          setState(() {
            _meetingsByDay = map;
            _loading = false;
          });
        }
      } else {
        throw Exception('Failed to load meetings');
      }
    } catch (e) {
      Logger.error('Calendar load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _error = ApiService.extractErrorMessage(e);
        });
      }
    }
  }

  void _goMonth(int delta) {
    setState(() {
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
      _selectedDay = null;
    });
    _load();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isToday(DateTime d) => _isSameDay(d, DateTime.now());

  Future<void> _joinMeeting(Meeting meeting) async {
    try {
      final response = await _api.joinMeeting(meeting.id);
      if (response.data['success'] == true && mounted) {
        final userName = await StorageService().getUserName();
        final joinData = response.data['data'];
        final callingRaw = joinData is Map ? joinData['calling'] : null;
        await VideoCallScreen.showModal(
          context: context,
          roomId: meeting.id,
          title: meeting.title,
          isMeeting: true,
          userName: userName,
          calling: callingRaw is Map ? Map<String, dynamic>.from(callingRaw) : null,
          onLeave: () {
            // Back from the room — refresh meeting status/attendance.
            _load();
          },
        );
      }
    } catch (e) {
      Logger.error('Calendar join error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiService.extractErrorMessage(e))),
        );
      }
    }
  }

  String _recurrenceLabel(Meeting meeting) {
    final raw = meeting.recurrenceRule;
    if (raw.isEmpty) return '';
    try {
      final rule = RegExp('"frequency"\\s*:\\s*"(\\w+)"').firstMatch(raw)?.group(1);
      switch (rule) {
        case 'DAILY':
          return 'Daily';
        case 'WEEKLY':
          return 'Weekly';
        case 'MONTHLY':
          return 'Monthly';
        case 'YEARLY':
          return 'Yearly';
        case 'CUSTOM':
          return 'Custom';
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colors;
    final monthLabel = DateFormat('MMMM yyyy').format(_visibleMonth);

    final firstWeekday = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday % 7; // 0=Sun
    final daysInMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 0).day;
    final cells = <DateTime?>[
      for (var i = 0; i < firstWeekday; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(_visibleMonth.year, _visibleMonth.month, d),
    ];
    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    final selectedDay = _selectedDay;
    final selectedMeetings = selectedDay == null
        ? const <Meeting>[]
        : _meetingsByDay[selectedDay] ?? const <Meeting>[];

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('Calendar', style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: colors.textSecondary),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center,
                          style: TextStyle(color: colors.textSecondary)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: _load, child: const Text('Try again')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      // Month header
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => _goMonth(-1),
                            icon: const Icon(Icons.chevron_left),
                          ),
                          Expanded(
                            child: Text(
                              monthLabel,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            onPressed: () => _goMonth(1),
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Weekday header
                      Row(
                        children: _weekdayLabels
                            .map(
                              (label) => Expanded(
                                child: Center(
                                  child: Text(
                                    label,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 6),
                      // Month grid
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 7,
                          mainAxisSpacing: 4,
                          crossAxisSpacing: 4,
                          childAspectRatio: 0.72,
                        ),
                        itemCount: cells.length,
                        itemBuilder: (context, index) {
                          final date = cells[index];
                          if (date == null) return const SizedBox.shrink();
                          final dayMeetings = _meetingsByDay[date] ?? const <Meeting>[];
                          final selected = selectedDay != null && _isSameDay(date, selectedDay);
                          final today = _isToday(date);

                          return InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () {
                              // One live/upcoming appointment → open (join) it;
                              // empty day → prompt the meeting creator for it;
                              // several (or finished/cancelled) → focus the day
                              // panel listing them all.
                              final solo = dayMeetings.length == 1 ? dayMeetings.first : null;
                              final joinable = solo != null &&
                                  solo.status != 'cancelled' &&
                                  solo.status != 'completed';
                              if (joinable) {
                                _joinMeeting(solo);
                              } else if (dayMeetings.isEmpty) {
                                showMeetingCreator(
                                  context,
                                  initialDate: DateTime(date.year, date.month, date.day),
                                  onSaved: (_) => _load(),
                                );
                              } else {
                                setState(() => _selectedDay = date);
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: selected
                                    ? colors.primary.withOpacity(0.10)
                                    : colors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? colors.primary
                                      : today
                                          ? colors.primary.withOpacity(0.5)
                                          : colors.border,
                                  width: selected || today ? 1.4 : 1,
                                ),
                              ),
                              padding: const EdgeInsets.all(3),
                              child: Column(
                                children: [
                                  Container(
                                    width: 20,
                                    height: 20,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: today ? colors.primary : Colors.transparent,
                                    ),
                                    child: Text(
                                      '${date.day}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: today ? FontWeight.w700 : FontWeight.w500,
                                        color: today ? Colors.white : colors.text,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  ...dayMeetings.take(2).map(
                                        (m) => Container(
                                          width: double.infinity,
                                          margin: const EdgeInsets.only(bottom: 1),
                                          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: m.status == 'cancelled'
                                                ? AppColors.error.withOpacity(0.15)
                                                : m.status == 'ongoing'
                                                    ? AppColors.success.withOpacity(0.18)
                                                    : colors.primary.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(3),
                                          ),
                                          child: Text(
                                            DateFormat.Hm().format(m.startTime.toLocal()),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              fontSize: 7.5,
                                              fontWeight: FontWeight.w700,
                                              color: m.status == 'cancelled'
                                                  ? AppColors.error
                                                  : m.status == 'ongoing'
                                                      ? AppColors.success
                                                      : colors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                  if (dayMeetings.length > 2)
                                    Text(
                                      '+${dayMeetings.length - 2}',
                                      style: TextStyle(
                                        fontSize: 7.5,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      // Selected day panel
                      if (selectedDay != null) ...[
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                DateFormat('EEEE, d MMMM').format(selectedDay),
                                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                            ),
                            Text(
                              '${selectedMeetings.length} meeting${selectedMeetings.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 12, color: colors.textSecondary),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (selectedMeetings.isEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 36),
                            decoration: BoxDecoration(
                              color: colors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: colors.border),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.event_available, size: 40, color: colors.textSecondary),
                                const SizedBox(height: 10),
                                Text(
                                  'No meetings on this day',
                                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        else
                          ...selectedMeetings.map(
                            (meeting) => Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colors.surface,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: colors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          meeting.title,
                                          style: const TextStyle(
                                              fontSize: 14, fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: meeting.status == 'ongoing'
                                              ? AppColors.success.withOpacity(0.15)
                                              : meeting.status == 'cancelled'
                                                  ? AppColors.error.withOpacity(0.12)
                                                  : colors.primary.withOpacity(0.12),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          meeting.status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 0.5,
                                            color: meeting.status == 'ongoing'
                                                ? AppColors.success
                                                : meeting.status == 'cancelled'
                                                    ? AppColors.error
                                                    : colors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${DateFormat.Hm().format(meeting.startTime.toLocal())}'
                                    ' – ${DateFormat.Hm().format(meeting.endTime.toLocal())}'
                                    ' · ${meeting.timezone}',
                                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                                  ),
                                  if (_recurrenceLabel(meeting).isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(Icons.repeat, size: 13, color: colors.textSecondary),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Repeats ${_recurrenceLabel(meeting)}',
                                          style: TextStyle(
                                              fontSize: 11, color: colors.textSecondary),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (meeting.attendees.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${meeting.attendees.length} attendee${meeting.attendees.length == 1 ? '' : 's'}',
                                      style: TextStyle(fontSize: 11, color: colors.textSecondary),
                                    ),
                                  ],
                                  const SizedBox(height: 10),
                                  if (meeting.status != 'cancelled' && meeting.status != 'completed')
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        onPressed: () => _joinMeeting(meeting),
                                        icon: const Icon(Icons.videocam, size: 16),
                                        label: Text(
                                          meeting.status == 'ongoing' ? 'Join now' : 'Join',
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: colors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 10),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(10),
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
    );
  }
}
