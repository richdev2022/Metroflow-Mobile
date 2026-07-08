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
      userId: json['user_id'] as String,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.parse(json['last_read_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'last_read_at': lastReadAt?.toIso8601String(),
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
      type: json['type'] as String,
      createdBy: json['created_by'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      participants: (json['participants'] as List<dynamic>)
          .map((e) => ConversationParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      lastMessage: json['last_message'] as String?,
      lastMessageAt: json['last_message_at'] != null
          ? DateTime.parse(json['last_message_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'type': type,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'participants': participants.map((e) => e.toJson()).toList(),
      'last_message': lastMessage,
      'last_message_at': lastMessageAt?.toIso8601String(),
    };
  }
}
