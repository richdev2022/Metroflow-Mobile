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
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      status: (json['status'] as String?) ?? 'invited',
      joinedAt: _parseDate(json['joinedAt'] ?? json['joined_at']),
      leftAt: _parseDate(json['leftAt'] ?? json['left_at']),
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
      id: (json['id'] ?? '').toString(),
      type: (json['type'] as String?) ?? 'video',
      status: (json['status'] as String?) ?? 'ongoing',
      startedAt: _parseDate(json['startedAt'] ?? json['started_at']),
      endedAt: _parseDate(json['endedAt'] ?? json['ended_at']),
      createdById: (json['createdById'] ?? json['created_by'] ?? '').toString(),
      hostId: (json['hostId'] ?? json['host_id'] ?? '').toString(),
      coHostId: (json['coHostId'] ?? json['co_host_id'])?.toString(),
      callCode: (json['callCode'] ?? json['call_code'] ?? '').toString(),
      isGroupCall: _parseBool(json['isGroupCall'] ?? json['is_group_call'], false),
      password: json['password']?.toString(),
      maxParticipants: _parseInt(json['maxParticipants'] ?? json['max_participants'], 10),
      waitingRoomEnabled: _parseBool(json['waitingRoomEnabled'] ?? json['waiting_room_enabled'], false),
      recordingEnabled: _parseBool(json['recordingEnabled'] ?? json['recording_enabled'], false),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
      participants: ((json['participants'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => CallParticipant.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      jitsiRoomId: (json['jitsiRoomId'] ?? json['jitsi_room_id'] ?? '').toString(),
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
