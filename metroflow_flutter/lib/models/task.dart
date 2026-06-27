import 'attachment.dart';
import 'comment.dart';

class Task {
  final String id;
  final String businessId;
  final String createdBy;
  final String title;
  final String? description;
  final String? epic;
  final String? epicId;
  final String? sprint;
  final double targetValue;
  final double accomplishedValue;
  final String startDate;
  final String endDate;
  final String? dueDate;
  final String status;
  final bool isOverdue;
  final List<String>? assignedTo;
  final List<Attachment>? attachments;
  final List<Comment>? comments;
  final List<String>? images;
  final String createdAt;
  final String updatedAt;

  Task({
    required this.id,
    required this.businessId,
    required this.createdBy,
    required this.title,
    this.description,
    this.epic,
    this.epicId,
    this.sprint,
    required this.targetValue,
    required this.accomplishedValue,
    required this.startDate,
    required this.endDate,
    this.dueDate,
    required this.status,
    required this.isOverdue,
    this.assignedTo,
    this.attachments,
    this.comments,
    this.images,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: (json['id'] as String?) ?? '',
      businessId: (json['businessId'] as String?) ?? '',
      createdBy: (json['createdBy'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      description: json['description'] as String?,
      epic: json['epic'] as String?,
      epicId: json['epicId'] as String?,
      sprint: json['sprint'] as String?,
      targetValue: (json['targetValue'] is num) ? (json['targetValue'] as num).toDouble() : double.tryParse('${json['targetValue']}') ?? 0.0,
      accomplishedValue: (json['accomplishedValue'] is num) ? (json['accomplishedValue'] as num).toDouble() : double.tryParse('${json['accomplishedValue']}') ?? 0.0,
      startDate: (json['startDate'] as String?) ?? '',
      endDate: (json['endDate'] as String?) ?? '',
      dueDate: json['dueDate'] as String?,
      status: (json['status'] as String?) ?? 'pending',
      isOverdue: (json['isOverdue'] as bool?) ?? false,
      assignedTo: json['assignedTo'] != null
          ? List<String>.from(json['assignedTo'] as List<dynamic>)
          : null,
      attachments: json['attachments'] != null
          ? (json['attachments'] as List<dynamic>)
              .map((e) {
                try {
                  return Attachment.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Attachment>()
              .toList()
          : null,
      comments: json['comments'] != null
          ? (json['comments'] as List<dynamic>)
              .map((e) {
                try {
                  return Comment.fromJson(e as Map<String, dynamic>);
                } catch (e) {
                  return null;
                }
              })
              .whereType<Comment>()
              .toList()
          : null,
      images: json['images'] != null
          ? List<String>.from(json['images'] as List<dynamic>)
          : null,
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'createdBy': createdBy,
      'title': title,
      'description': description,
      'epic': epic,
      'epicId': epicId,
      'sprint': sprint,
      'targetValue': targetValue,
      'accomplishedValue': accomplishedValue,
      'startDate': startDate,
      'endDate': endDate,
      'dueDate': dueDate,
      'status': status,
      'isOverdue': isOverdue,
      'assignedTo': assignedTo,
      'attachments': attachments?.map((e) => e.toJson()).toList(),
      'comments': comments?.map((e) => e.toJson()).toList(),
      'images': images,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Task && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
