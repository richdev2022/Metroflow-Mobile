import 'task.dart';

class TaskStatus {
  final String id;
  final String businessId;
  final String name;
  final String color;
  final bool isDefault;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<Task>? tasks;

  TaskStatus({
    required this.id,
    required this.businessId,
    required this.name,
    required this.color,
    required this.isDefault,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
    this.tasks,
  });

  factory TaskStatus.fromJson(Map<String, dynamic> json) {
    return TaskStatus(
      id: json['id'],
      businessId: json['business_id'],
      name: json['name'],
      color: json['color'],
      isDefault: json['is_default'],
      sortOrder: json['sort_order'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
      tasks: json['tasks'] != null
          ? (json['tasks'] as List<dynamic>)
              .map((e) => Task.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'name': name,
      'color': color,
      'is_default': isDefault,
      'sort_order': sortOrder,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'tasks': tasks?.map((e) => e.toJson()).toList(),
    };
  }
}
