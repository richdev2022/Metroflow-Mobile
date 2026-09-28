class ConversationParticipant {
  final String id;
  final String userId;
  final DateTime? lastReadAt;

  // Enriched fields from the backend (LEFT JOIN users) — used to build the
  // profile sheet and derive display names when `displayName` is missing.
  final String name;
  final String email;
  final String? avatarUrl;

  ConversationParticipant({
    required this.id,
    required this.userId,
    this.lastReadAt,
    this.name = '',
    this.email = '',
    this.avatarUrl,
  });

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      lastReadAt: _parseDate(json['lastReadAt'] ?? json['last_read_at']),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      avatarUrl: (json['avatarUrl'] ?? json['avatar_url'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'lastReadAt': lastReadAt?.toIso8601String(),
      'name': name,
      'email': email,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}

int _parseIntOrZero(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
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
  final int unreadCount;
  final String? lastMessageSenderId;

  // Backend display helpers (GET /chat/conversations): direct chats show the
  // OTHER participant's name/avatar, groups show the group name. Null on
  // older payloads / socket-created conversations — the derived getters below
  // fall back to the participants list.
  final bool? isGroupFlag;
  final String? displayName;
  final String? displayAvatarUrl;

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
    this.unreadCount = 0,
    this.lastMessageSenderId,
    this.isGroupFlag,
    this.displayName,
    this.displayAvatarUrl,
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
      unreadCount: _parseIntOrZero(json['unreadCount'] ?? json['unread_count']),
      lastMessageSenderId:
          (json['lastMessageSenderId'] ?? json['last_message_sender_id'])?.toString(),
      isGroupFlag: json['isGroup'] is bool ? json['isGroup'] as bool : null,
      displayName: json['displayName']?.toString(),
      displayAvatarUrl: json['displayAvatarUrl']?.toString(),
    );
  }

  bool get isGroup => isGroupFlag ?? type == 'group';

  /// The participant that is NOT me (best-effort; requires [currentUserId]).
  ConversationParticipant? otherParticipant(String? currentUserId) {
    for (final participant in participants) {
      if (participant.userId.isNotEmpty && participant.userId != currentUserId) {
        return participant;
      }
    }
    return participants.isEmpty ? null : participants.first;
  }

  /// Row/header name: backend `displayName` → other participant's name →
  /// conversation name → 'Direct chat' / 'Group chat'.
  String displayTitle(String? currentUserId) {
    final provided = displayName?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    if (!isGroup) {
      final other = otherParticipant(currentUserId);
      final otherName = other?.name.trim() ?? '';
      if (otherName.isNotEmpty) return otherName;
      final ownName = name?.trim() ?? '';
      if (ownName.isNotEmpty && !ownName.contains('@')) return ownName;
      return 'Direct chat';
    }
    return (name?.trim().isNotEmpty ?? false) ? name!.trim() : 'Group chat';
  }

  /// Row/header avatar: backend `displayAvatarUrl` → other participant's
  /// avatar. Groups intentionally return null (group badge instead).
  String? displayAvatar(String? currentUserId) {
    final provided = displayAvatarUrl?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    if (!isGroup) {
      return otherParticipant(currentUserId)?.avatarUrl;
    }
    return null;
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
      'unreadCount': unreadCount,
      if (lastMessageSenderId != null) 'lastMessageSenderId': lastMessageSenderId,
      'isGroup': isGroup,
      'displayName': displayName,
      'displayAvatarUrl': displayAvatarUrl,
    };
  }
}
