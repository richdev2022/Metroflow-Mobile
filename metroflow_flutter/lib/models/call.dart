class CallParticipant {
  final String id;
  final String userId;
  final String status;
  final DateTime? joinedAt;
  final DateTime? leftAt;

  CallParticipant({
    required this.id,
    required this.userId,
    required this.status,
    this.joinedAt,
    this.leftAt,
  });

  factory CallParticipant.fromJson(Map<String, dynamic> json) {
    return CallParticipant(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      status: json['status'] as String,
      joinedAt: json['joined_at'] != null
          ? DateTime.parse(json['joined_at'] as String)
          : null,
      leftAt: json['left_at'] != null
          ? DateTime.parse(json['left_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'status': status,
      'joined_at': joinedAt?.toIso8601String(),
      'left_at': leftAt?.toIso8601String(),
    };
  }
}

class Call {
  final String id;
  final String type;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String createdBy;
  final String jitsiRoomId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CallParticipant> participants;

  Call({
    required this.id,
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.createdBy,
    required this.jitsiRoomId,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
  });

  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['id'] as String,
      type: json['type'] as String,
      status: json['status'] as String,
      startedAt: json['started_at'] != null
          ? DateTime.parse(json['started_at'] as String)
          : null,
      endedAt: json['ended_at'] != null
          ? DateTime.parse(json['ended_at'] as String)
          : null,
      createdBy: json['created_by'] as String,
      jitsiRoomId: json['jitsi_room_id'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      participants: (json['participants'] as List<dynamic>)
          .map((e) => CallParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'status': status,
      'started_at': startedAt?.toIso8601String(),
      'ended_at': endedAt?.toIso8601String(),
      'created_by': createdBy,
      'jitsi_room_id': jitsiRoomId,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'participants': participants.map((e) => e.toJson()).toList(),
    };
  }
}
