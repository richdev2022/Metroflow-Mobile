class ConversationParticipant {
  final String id;
  final String userId;
  final DateTime? lastReadAt;

  ConversationParticipant({
    required this.id,
    required this.userId,
    this.lastReadAt,
  });

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      lastReadAt: _parseDate(json['lastReadAt'] ?? json['last_read_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'lastReadAt': lastReadAt?.toIso8601String(),
    };
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

class Conversation {
  final String id;
  final String? name;
  final String type;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<ConversationParticipant> participants;
  final String? lastMessage;
  final DateTime? lastMessageAt;

  Conversation({
    required this.id,
    this.name,
    required this.type,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
    this.lastMessage,
    this.lastMessageAt,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(
      id: (json['id'] ?? '').toString(),
      name: json['name']?.toString(),
      type: (json['type'] as String?) ?? 'direct',
      createdBy: (json['createdBy'] ?? json['created_by'] ?? '').toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updatedAt'] ?? json['updated_at']) ?? DateTime.now(),
      participants: ((json['participants'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => ConversationParticipant.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      lastMessage: (json['lastMessage'] ?? json['last_message'])?.toString(),
      lastMessageAt: _parseDate(json['lastMessageAt'] ?? json['last_message_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'participants': participants.map((e) => e.toJson()).toList(),
      'lastMessage': lastMessage,
      'lastMessageAt': lastMessageAt?.toIso8601String(),
    };
  }
}
