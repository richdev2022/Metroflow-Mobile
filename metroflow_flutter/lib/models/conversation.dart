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
      id: json['id'] as String,
      userId: (json['userId'] ?? json['user_id']) as String,
      lastReadAt: (json['lastReadAt'] ?? json['last_read_at']) != null
          ? DateTime.parse((json['lastReadAt'] ?? json['last_read_at']) as String)
          : null,
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
      id: json['id'] as String,
      name: json['name'] as String?,
      type: (json['type'] as String?) ?? 'direct',
      createdBy: (json['createdBy'] ?? json['created_by'] ?? '') as String,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
      participants: ((json['participants'] as List<dynamic>?) ?? [])
          .map((e) => ConversationParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastMessage: (json['lastMessage'] ?? json['last_message']) as String?,
      lastMessageAt: (json['lastMessageAt'] ?? json['last_message_at']) != null
          ? DateTime.parse((json['lastMessageAt'] ?? json['last_message_at']) as String)
          : null,
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
