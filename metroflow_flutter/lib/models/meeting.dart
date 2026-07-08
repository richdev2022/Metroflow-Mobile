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
  final String status;
  final String meetingUrl;
  final String? googleEventId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MeetingAttendee> attendees;

  Meeting({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.timezone,
    required this.createdById,
    required this.status,
    required this.meetingUrl,
    this.googleEventId,
    required this.createdAt,
    required this.updatedAt,
    required this.attendees,
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
      status: (json['status'] as String?) ?? 'scheduled',
      meetingUrl: (json['meetingUrl'] ?? json['meeting_url'] ?? '') as String,
      googleEventId: (json['googleEventId'] ?? json['google_event_id']) as String?,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
      attendees: ((json['attendees'] as List<dynamic>?) ?? [])
          .map((e) => MeetingAttendee.fromJson(e as Map<String, dynamic>))
          .toList(),
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
      'status': status,
      'meetingUrl': meetingUrl,
      'googleEventId': googleEventId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'attendees': attendees.map((e) => e.toJson()).toList(),
    };
  }
}
