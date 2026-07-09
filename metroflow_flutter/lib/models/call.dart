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
      userId: (json['userId'] ?? json['user_id']) as String,
      status: (json['status'] as String?) ?? 'invited',
      joinedAt: (json['joinedAt'] ?? json['joined_at']) != null
          ? DateTime.parse((json['joinedAt'] ?? json['joined_at']) as String)
          : null,
      leftAt: (json['leftAt'] ?? json['left_at']) != null
          ? DateTime.parse((json['leftAt'] ?? json['left_at']) as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'status': status,
      'joinedAt': joinedAt?.toIso8601String(),
      'leftAt': leftAt?.toIso8601String(),
    };
  }
}

class Call {
  final String id;
  final String type;
  final String status;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final String createdById;
  final String hostId;
  final String? coHostId;
  final String callCode;
  final bool isGroupCall;
  final String? password;
  final int maxParticipants;
  final bool waitingRoomEnabled;
  final bool recordingEnabled;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<CallParticipant> participants;
  // Backward compatibility field
  final String jitsiRoomId;

  Call({
    required this.id,
    required this.type,
    required this.status,
    this.startedAt,
    this.endedAt,
    required this.createdById,
    required this.hostId,
    this.coHostId,
    required this.callCode,
    required this.isGroupCall,
    this.password,
    required this.maxParticipants,
    required this.waitingRoomEnabled,
    required this.recordingEnabled,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
    this.jitsiRoomId = '',
  });

  factory Call.fromJson(Map<String, dynamic> json) {
    return Call(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'video',
      status: (json['status'] as String?) ?? 'ongoing',
      startedAt: (json['startedAt'] ?? json['started_at']) != null
          ? DateTime.parse((json['startedAt'] ?? json['started_at']) as String)
          : null,
      endedAt: (json['endedAt'] ?? json['ended_at']) != null
          ? DateTime.parse((json['endedAt'] ?? json['ended_at']) as String)
          : null,
      createdById: (json['createdById'] ?? json['created_by'] ?? '') as String,
      hostId: (json['hostId'] ?? json['host_id'] ?? '') as String,
      coHostId: (json['coHostId'] ?? json['co_host_id']) as String?,
      callCode: (json['callCode'] ?? json['call_code'] ?? '') as String,
      isGroupCall: (json['isGroupCall'] ?? json['is_group_call'] ?? false) as bool,
      password: (json['password']) as String?,
      maxParticipants: (json['maxParticipants'] ?? json['max_participants'] ?? 10) as int,
      waitingRoomEnabled: (json['waitingRoomEnabled'] ?? json['waiting_room_enabled'] ?? false) as bool,
      recordingEnabled: (json['recordingEnabled'] ?? json['recording_enabled'] ?? false) as bool,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
      participants: ((json['participants'] as List<dynamic>?) ?? [])
          .map((e) => CallParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      jitsiRoomId: (json['jitsiRoomId'] ?? json['jitsi_room_id'] ?? '') as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'status': status,
      'startedAt': startedAt?.toIso8601String(),
      'endedAt': endedAt?.toIso8601String(),
      'createdById': createdById,
      'hostId': hostId,
      'coHostId': coHostId,
      'callCode': callCode,
      'isGroupCall': isGroupCall,
      'password': password,
      'maxParticipants': maxParticipants,
      'waitingRoomEnabled': waitingRoomEnabled,
      'recordingEnabled': recordingEnabled,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'participants': participants.map((e) => e.toJson()).toList(),
      'jitsiRoomId': jitsiRoomId,
    };
  }
}
