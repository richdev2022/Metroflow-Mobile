class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? attachmentUrl;
  final String? attachmentType;
  final DateTime createdAt;
  final String? senderName;

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.attachmentUrl,
    this.attachmentType,
    required this.createdAt,
    this.senderName,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: (json['id'] ?? '').toString(),
      conversationId: (json['conversationId'] ?? json['conversation_id'] ?? '').toString(),
      senderId: (json['senderId'] ?? json['sender_id'] ?? '').toString(),
      content: (json['content'] as String?) ?? '',
      attachmentUrl: (json['attachmentUrl'] ?? json['attachment_url'])?.toString(),
      attachmentType: (json['attachmentType'] ?? json['attachment_type'])?.toString(),
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
