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
      id: json['id'] as String,
      userId: (json['userId'] ?? json['user_id']) as String,
      status: json['status'] as String,
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
    return Meeting(
      id: json['id'] as String,
      title: json['title'] as String,
      description: (json['description'] as String?) ?? '',
      startTime: DateTime.parse((json['startTime'] ?? json['start_time']) as String),
      endTime: DateTime.parse((json['endTime'] ?? json['end_time']) as String),
      timezone: (json['timezone'] as String?) ?? 'UTC',
      createdById: (json['createdById'] ?? json['created_by'] ?? '') as String,
      hostId: (json['hostId'] ?? json['host_id'] ?? '') as String,
      coHostId: (json['coHostId'] ?? json['co_host_id']) as String?,
      status: (json['status'] as String?) ?? 'scheduled',
      meetingCode: (json['meetingCode'] ?? json['meeting_code'] ?? '') as String,
      isInstant: (json['isInstant'] ?? json['is_instant'] ?? false) as bool,
      password: (json['password']) as String?,
      maxParticipants: (json['maxParticipants'] ?? json['max_participants'] ?? 100) as int,
      waitingRoomEnabled: (json['waitingRoomEnabled'] ?? json['waiting_room_enabled'] ?? false) as bool,
      recordingEnabled: (json['recordingEnabled'] ?? json['recording_enabled'] ?? false) as bool,
      screenSharingEnabled: (json['screenSharingEnabled'] ?? json['screen_sharing_enabled'] ?? true) as bool,
      googleEventId: (json['googleEventId'] ?? json['google_event_id']) as String?,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
      attendees: ((json['attendees'] as List<dynamic>?) ?? [])
          .map((e) => MeetingAttendee.fromJson(e as Map<String, dynamic>))
          .toList(),
      meetingUrl: (json['meetingUrl'] ?? json['meeting_url'] ?? '') as String,
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
