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

  /// NULL-SAFE, CASE-TOLERANT key lookup.
  ///
  /// The notifications endpoint historically returned raw snake_case rows
  /// (`business_id`, `expires_at`, …) while some releases serialize camelCase.
  /// Reading a missing key as a hard `as String` cast blew up the whole
  /// Notifications screen with "type 'Null' is not a subtype of type 'String'
  /// in type cast" — so every field goes through [readKey] (both spellings)
  /// and [asString]/[asDate] (null-safe with fallbacks).
  static String? _val(Map<String, dynamic> json, String camel, String snake) {
    final v = json[camel] ?? json[snake];
    return v == null ? null : v.toString();
  }

  static String asString(String? v, String fallback) =>
      (v == null || v.isEmpty) ? fallback : v;

  static DateTime asDate(String? v, DateTime fallback) {
    if (v == null) return fallback;
    return DateTime.tryParse(v) ?? fallback;
  }

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: asString(_val(json, 'id', 'id'), ''),
      businessId: asString(_val(json, 'businessId', 'business_id'), ''),
      userId: asString(_val(json, 'userId', 'user_id'), ''),
      type: asString(_val(json, 'type', 'type'), 'system'),
      title: asString(_val(json, 'title', 'title'), 'Notification'),
      message: asString(_val(json, 'message', 'message'), ''),
      actionUrl: _val(json, 'actionUrl', 'action_url'),
      actionType: _val(json, 'actionType', 'action_type'),
      metadata: json['metadata'] is Map<String, dynamic>
          ? json['metadata'] as Map<String, dynamic>
          : (json['metadata'] is Map
              ? Map<String, dynamic>.from(json['metadata'] as Map)
              : null),
      isRead: (json['isRead'] ?? json['is_read'] ?? false) == true,
      isActionable: (json['isActionable'] ?? json['is_actionable'] ?? false) == true,
      actionTaken: _val(json, 'actionTaken', 'action_taken'),
      createdAt: asDate(_val(json, 'createdAt', 'created_at'), DateTime.now()),
      // `expires_at` is nullable in some rows — fall back to "never".
      expiresAt: asDate(
        _val(json, 'expiresAt', 'expires_at'),
        DateTime.now().add(const Duration(days: 3650)),
      ),
      updatedAt: asDate(_val(json, 'updatedAt', 'updated_at'), DateTime.now()),
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
