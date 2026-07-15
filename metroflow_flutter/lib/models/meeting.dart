class MeetingAttendee {
  final String id;
  final String userId;
  final String status;

  MeetingAttendee({
    required this.id,
    required this.userId,
    required this.status,
  });

  factory MeetingAttendee.fromJson(Map<String, dynamic> json) {
    return MeetingAttendee(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      status: (json['status'] ?? 'invited').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'status': status,
    };
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

int _parseInt(dynamic value, int fallback) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

bool _parseBool(dynamic value, bool fallback) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().toLowerCase();
  if (text == 'true') return true;
  if (text == 'false') return false;
  return fallback;
}

class Meeting {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String timezone;
  final String createdById;
  final String hostId;
  final String? coHostId;
  final String status;
  final String meetingCode;
  final bool isInstant;
  final String? password;
  final int maxParticipants;
  final bool waitingRoomEnabled;
  final bool recordingEnabled;
  final bool screenSharingEnabled;
  final String? googleEventId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MeetingAttendee> attendees;
  // Backward compatibility fields
  final String meetingUrl;

  Meeting({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.createdById,
    required this.hostId,
    this.coHostId,
    required this.status,
    required this.meetingCode,
    required this.isInstant,
    this.password,
    required this.maxParticipants,
    required this.waitingRoomEnabled,
    required this.recordingEnabled,
    required this.screenSharingEnabled,
    this.googleEventId,
    required this.createdAt,
    required this.updatedAt,
    required this.attendees,
    this.meetingUrl = '',
  });

  factory Meeting.fromJson(Map<String, dynamic> json) {
    final now = DateTime.now();
    final parsedStart = _parseDate(json['startTime'] ?? json['start_time']) ?? now;
    return Meeting(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Untitled meeting').toString(),
      description: (json['description'] as String?) ?? '',
      startTime: parsedStart,
      endTime: _parseDate(json['endTime'] ?? json['end_time']) ?? parsedStart.add(const Duration(hours: 1)),
      timezone: (json['timezone'] as String?) ?? 'UTC',
      createdById: (json['createdById'] ?? json['created_by'] ?? '').toString(),
      hostId: (json['hostId'] ?? json['host_id'] ?? '').toString(),
      coHostId: (json['coHostId'] ?? json['co_host_id'])?.toString(),
      status: (json['status'] as String?) ?? 'scheduled',
      meetingCode: (json['meetingCode'] ?? json['meeting_code'] ?? '').toString(),
      isInstant: _parseBool(json['isInstant'] ?? json['is_instant'], false),
      password: json['password']?.toString(),
      maxParticipants: _parseInt(json['maxParticipants'] ?? json['max_participants'], 100),
      waitingRoomEnabled: _parseBool(json['waitingRoomEnabled'] ?? json['waiting_room_enabled'], false),
      recordingEnabled: _parseBool(json['recordingEnabled'] ?? json['recording_enabled'], false),
      screenSharingEnabled: _parseBool(json['screenSharingEnabled'] ?? json['screen_sharing_enabled'], true),
      googleEventId: (json['googleEventId'] ?? json['google_event_id'])?.toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']) ?? now,
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']) ?? now,
      attendees: ((json['attendees'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => MeetingAttendee.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      meetingUrl: (json['meetingUrl'] ?? json['meeting_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'timezone': timezone,
      'createdById': createdById,
      'hostId': hostId,
      'coHostId': coHostId,
      'status': status,
      'meetingCode': meetingCode,
      'isInstant': isInstant,
      'password': password,
      'maxParticipants': maxParticipants,
      'waitingRoomEnabled': waitingRoomEnabled,
      'recordingEnabled': recordingEnabled,
      'screenSharingEnabled': screenSharingEnabled,
      'googleEventId': googleEventId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'attendees': attendees.map((e) => e.toJson()).toList(),
      'meetingUrl': meetingUrl,
    };
  }
}
