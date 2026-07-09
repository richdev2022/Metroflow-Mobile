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
      id: json['id'] as String,
      conversationId: (json['conversationId'] ?? json['conversation_id']) as String,
      senderId: (json['senderId'] ?? json['sender_id']) as String,
      content: (json['content'] as String?) ?? '',
      attachmentUrl: (json['attachmentUrl'] ?? json['attachment_url']) as String?,
      attachmentType: (json['attachmentType'] ?? json['attachment_type']) as String?,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      senderName: (json['senderName'] ?? json['sender_name']) as String?,
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
