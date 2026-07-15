class AppNotification {
  final String id;
  final String businessId;
  final String userId;
  final String type;
  final String title;
  final String message;
  final String? actionUrl;
  final String? actionType;
  final Map<String, dynamic>? metadata;
  final bool isRead;
  final bool isActionable;
  final String? actionTaken;
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime updatedAt;

  AppNotification({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    this.actionUrl,
    this.actionType,
    this.metadata,
    required this.isRead,
    required this.isActionable,
    this.actionTaken,
    required this.createdAt,
    required this.expiresAt,
    required this.updatedAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      businessId: json['businessId'] as String,
      userId: json['userId'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      message: json['message'] as String,
      actionUrl: json['actionUrl'] as String?,
      actionType: json['actionType'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
      isRead: json['isRead'] as bool,
      isActionable: json['isActionable'] as bool,
      actionTaken: json['actionTaken'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'userId': userId,
      'type': type,
      'title': title,
      'message': message,
      'actionUrl': actionUrl,
      'actionType': actionType,
      'metadata': metadata,
      'isRead': isRead,
      'isActionable': isActionable,
      'actionTaken': actionTaken,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  AppNotification copyWith({
    String? id,
    String? businessId,
    String? userId,
    String? type,
    String? title,
    String? message,
    String? actionUrl,
    String? actionType,
    Map<String, dynamic>? metadata,
    bool? isRead,
    bool? isActionable,
    String? actionTaken,
    DateTime? createdAt,
    DateTime? expiresAt,
    DateTime? updatedAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      userId: userId ?? this.userId,
      type: type ?? this.type,
      title: title ?? this.title,
      message: message ?? this.message,
      actionUrl: actionUrl ?? this.actionUrl,
      actionType: actionType ?? this.actionType,
      metadata: metadata ?? this.metadata,
      isRead: isRead ?? this.isRead,
      isActionable: isActionable ?? this.isActionable,
      actionTaken: actionTaken ?? this.actionTaken,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
