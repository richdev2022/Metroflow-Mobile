class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? attachmentUrl;
  final String? attachmentType;
  final String? attachmentName;
  final int? attachmentSize;
  final String? messageType;
  final DateTime createdAt;
  final String? senderName;

  /// Parity with the web batch-4 chat contract (PATCH / DELETE message):
  /// - [editedAt] set when the sender edited the text (≤24h window).
  /// - [deletedForEveryone] renders the "This message was deleted" tombstone.
  /// - [deletedForMe] hides the message for THIS user only.
  /// - [replyTo] is the quoted (id, sender, snippet) block of the message
  ///   being replied to.
  final DateTime? editedAt;
  final bool deletedForEveryone;
  final bool deletedForMe;
  final MessageReplyRef? replyTo;

  /// Local-only flag: optimistic attachment bubbles shown while POST
  /// /chat/media is in flight (rendered with a spinner overlay, removed or
  /// replaced once the upload resolves). Never set by fromJson.
  final bool isPendingUpload;

  /// Local-only flag: set when THIS user deletes the message for everyone —
  /// the optimistic tombstone (the socket echo still updates the real copy).
  final bool isPendingDelete;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.attachmentUrl,
    this.attachmentType,
    this.attachmentName,
    this.attachmentSize,
    this.messageType,
    required this.createdAt,
    this.senderName,
    this.editedAt,
    this.deletedForEveryone = false,
    this.deletedForMe = false,
    this.replyTo,
    this.isPendingUpload = false,
    this.isPendingDelete = false,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final rawSize = json['attachmentSize'] ?? json['attachment_size'];
    return Message(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? json['conversation_id'] ?? '').toString(),
      senderId: (json['senderId'] ?? json['sender_id'] ?? '').toString(),
      content: (json['content'] as String?) ?? '',
      attachmentUrl: (json['attachmentUrl'] ?? json['attachment_url'])?.toString(),
      attachmentType: (json['attachmentType'] ?? json['attachment_type'])?.toString(),
      attachmentName: (json['attachmentName'] ?? json['attachment_name'])?.toString(),
      attachmentSize: rawSize is num ? rawSize.toInt() : int.tryParse('$rawSize'),
      messageType: (json['messageType'] ?? json['message_type'])?.toString(),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      senderName: (json['senderName'] ?? json['sender_name'])?.toString(),
      editedAt: _parseDate(json['editedAt'] ?? json['edited_at']),
      deletedForEveryone: json['deletedForEveryone'] == true ||
          json['deleted_for_everyone'] == true,
      deletedForMe: json['deletedForMe'] == true || json['deleted_for_me'] == true,
      replyTo: _parseReplyRef(json['replyTo'] ?? json['reply_to']),
    );
  }

  static MessageReplyRef? _parseReplyRef(dynamic raw) {
    if (raw is! Map) return null;
    final id = (raw['id'] ?? raw['messageId'] ?? '').toString();
    if (id.isEmpty) return null;
    return MessageReplyRef(
      id: id,
      senderName: (raw['senderName'] ?? raw['sender_name'])?.toString(),
      content: (raw['content'] ?? raw['snippet'])?.toString() ?? '',
      messageType: (raw['messageType'] ?? raw['message_type'])?.toString(),
    );
  }

  /// Copy helper used by the message:updated socket handler / optimistic
  /// delete + edit flows.
  Message copyWith({
    String? content,
    DateTime? editedAt,
    bool? deletedForEveryone,
    bool? deletedForMe,
    bool? isPendingDelete,
  }) {
    return Message(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      content: content ?? this.content,
      attachmentUrl: attachmentUrl,
      attachmentType: attachmentType,
      attachmentName: attachmentName,
      attachmentSize: attachmentSize,
      messageType: messageType,
      createdAt: createdAt,
      senderName: senderName,
      editedAt: editedAt ?? this.editedAt,
      deletedForEveryone: deletedForEveryone ?? this.deletedForEveryone,
      deletedForMe: deletedForMe ?? this.deletedForMe,
      replyTo: replyTo,
      isPendingUpload: isPendingUpload,
      isPendingDelete: isPendingDelete ?? this.isPendingDelete,
    );
  }

  /// True when this message should render as a tombstone for the viewer.
  bool get isTombstone =>
      deletedForEveryone || deletedForMe || isPendingDelete;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'content': content,
      'attachmentUrl': attachmentUrl,
      'attachmentType': attachmentType,
      'attachmentName': attachmentName,
      'attachmentSize': attachmentSize,
      'messageType': messageType,
      'createdAt': createdAt.toIso8601String(),
      'senderName': senderName,
      if (editedAt != null) 'editedAt': editedAt!.toIso8601String(),
      'deletedForEveryone': deletedForEveryone,
      'deletedForMe': deletedForMe,
      if (replyTo != null) 'replyTo': replyTo!.toJson(),
    };
  }
}

/// Quoted reference of the message being replied to (subset of fields the
/// composer + bubble need; the backend sends `replyTo` hydrated or null).
class MessageReplyRef {
  final String id;
  final String? senderName;
  final String content;
  final String? messageType;

  const MessageReplyRef({
    required this.id,
    this.senderName,
    required this.content,
    this.messageType,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        if (senderName != null) 'senderName': senderName,
        'content': content,
        if (messageType != null) 'messageType': messageType,
      };
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  // Epoch support: JSON numbers arrive as seconds (< 1e11) or milliseconds.
  // Parsed as UTC instants — every formatter renders via .toLocal().
  if (value is num && value > 0) {
    final ms = value >= 100000000000 ? value.toInt() : (value.toInt() * 1000);
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
  }
  final raw = value.toString();
  if (raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}
