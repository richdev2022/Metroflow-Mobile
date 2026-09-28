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

  /// Local-only flag: optimistic attachment bubbles shown while POST
  /// /chat/media is in flight (rendered with a spinner overlay, removed or
  /// replaced once the upload resolves). Never set by fromJson.
  final bool isPendingUpload;

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
    this.isPendingUpload = false,
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
    );
  }

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
    };
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  return DateTime.tryParse(value.toString());
}
