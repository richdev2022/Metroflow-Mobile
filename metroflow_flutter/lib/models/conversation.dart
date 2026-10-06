class ConversationParticipant {
  final String id;
  final String userId;
  final DateTime? lastReadAt;

  /// Presence parity: the backend enriches participants with the user's
  /// `last_seen_at` (best-effort; null on older payloads).
  final DateTime? lastSeenAt;
  final String? presenceStatus;

  // Enriched fields from the backend (LEFT JOIN users) — used to build the
  // profile sheet and derive display names when `displayName` is missing.
  final String name;
  final String email;
  final String? avatarUrl;

  ConversationParticipant({
    required this.id,
    required this.userId,
    this.lastReadAt,
    this.lastSeenAt,
    this.presenceStatus,
    this.name = '',
    this.email = '',
    this.avatarUrl,
  });

  factory ConversationParticipant.fromJson(Map<String, dynamic> json) {
    return ConversationParticipant(
      id: (json['id'] ?? '').toString(),
      userId: (json['userId'] ?? json['user_id'] ?? '').toString(),
      lastReadAt: _parseDate(json['lastReadAt'] ?? json['last_read_at']),
      lastSeenAt: _parseDate(json['lastSeenAt'] ?? json['last_seen_at']),
      presenceStatus: (json['presenceStatus'] ?? json['presence_status'])?.toString(),
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
  // Epoch support: JSON numbers arrive as seconds (< 1e11) or milliseconds.
  // Parsed as UTC instants — every formatter renders via toLocal()/AppTimezone.
  if (value is num && value > 0) {
    final ms = value >= 100000000000 ? value.toInt() : (value.toInt() * 1000);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  final raw = value.toString();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
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

  /// Presence parity (batch 4): the OTHER participant's last-seen instant —
  /// top-level `otherUserLastSeenAt` on the conversations payload or the
  /// participant's own `lastSeenAt`. Null on older backends.
  final DateTime? otherUserLastSeenAt;
  final String? otherUserPresenceStatus;

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
    this.otherUserLastSeenAt,
    this.otherUserPresenceStatus,
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
      // Case-fallback chain: the backend used to alias lastMessage with a
      // quoted camelCase alias, but the unquoted-SQL era lowercased it to
      // `lastmessage` (and `lastmessageat`). Quote-aliases landed
      // server-side so camelCase is primary again — the lowercase fallbacks
      // stay so older cached/proxied payloads keep rendering.
      lastMessage: (json['lastMessage'] ?? json['last_message'] ?? json['lastmessage'])
          ?.toString(),
      lastMessageAt: _parseDate(json['lastMessageAt'] ??
          json['last_message_at'] ??
          json['lastmessageat']),
      unreadCount: _parseIntOrZero(json['unreadCount'] ?? json['unread_count']),
      lastMessageSenderId:
          (json['lastMessageSenderId'] ?? json['last_message_sender_id'])?.toString(),
      isGroupFlag: json['isGroup'] is bool ? json['isGroup'] as bool : null,
      displayName: json['displayName']?.toString(),
      displayAvatarUrl: json['displayAvatarUrl']?.toString(),
      otherUserLastSeenAt: _parseDate(
          json['otherUserLastSeenAt'] ?? json['other_user_last_seen_at']),
      otherUserPresenceStatus:
          (json['otherUserPresenceStatus'] ?? json['other_user_presence_status'])?.toString(),
    );
  }

  /// Best-effort last-seen for the peer: the top-level enriched field first,
  /// then the participant row. Handles both ISO strings (already parsed by
  /// fromJson) and epoch MILLIS values smuggled through as num via the raw
  /// maps — the socket `presence:update` handler also normalizes there.
  DateTime? otherLastSeen(String? currentUserId) {
    if (otherUserLastSeenAt != null) return otherUserLastSeenAt;
    final other = otherParticipant(currentUserId);
    return other?.lastSeenAt;
  }

  String? otherPresenceStatus(String? currentUserId) {
    final provided = otherUserPresenceStatus?.trim();
    if (provided != null && provided.isNotEmpty) return provided;
    final other = otherParticipant(currentUserId);
    return other?.presenceStatus?.trim();
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
