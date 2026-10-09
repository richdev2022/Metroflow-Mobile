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
    // NULL-HARDENED: the backend's task_statuses table has a nullable color
    // (and legacy rows can miss is_default/sort_order). One null here used
    // to throw "type 'Null' is not a subtype..." — fetchData swallowed it
    // and the ENTIRE board rendered as empty.
    return TaskStatus(
      id: (json['id'] as String?) ?? '',
      businessId: (json['business_id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      color: (json['color'] as String?) ?? '#6B7280',
      isDefault: json['is_default'] == true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? '') ??
          DateTime.now(),
      tasks: json['tasks'] is List
          ? (json['tasks'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map(Task.fromJson)
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
