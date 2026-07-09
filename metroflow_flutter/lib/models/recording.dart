class Recording {
  final String id;
  final String businessId;
  final String? meetingId;
  final String? callId;
  final String recordedById;
  final String recordedByName;
  final String storageUrl;
  final int duration;
  final String status;
  final int size;
  final DateTime createdAt;
  final DateTime updatedAt;

  Recording({
    required this.id,
    required this.businessId,
    this.meetingId,
    this.callId,
    required this.recordedById,
    required this.recordedByName,
    required this.storageUrl,
    required this.duration,
    required this.status,
    required this.size,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Recording.fromJson(Map<String, dynamic> json) {
    return Recording(
      id: json['id'] as String,
      businessId: (json['businessId'] ?? json['business_id']) as String,
      meetingId: (json['meetingId'] ?? json['meeting_id']) as String?,
      callId: (json['callId'] ?? json['call_id']) as String?,
      recordedById: (json['recordedById'] ?? json['recorded_by_id']) as String,
      recordedByName: (json['recordedByName'] ?? json['recorded_by_name']) as String,
      storageUrl: (json['storageUrl'] ?? json['storage_url']) as String,
      duration: (json['duration']) as int,
      status: (json['status']) as String,
      size: (json['size']) as int,
      createdAt: DateTime.parse((json['createdAt'] ?? json['created_at']) as String),
      updatedAt: DateTime.parse((json['updatedAt'] ?? json['updated_at']) as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'meetingId': meetingId,
      'callId': callId,
      'recordedById': recordedById,
      'recordedByName': recordedByName,
      'storageUrl': storageUrl,
      'duration': duration,
      'status': status,
      'size': size,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }
}
