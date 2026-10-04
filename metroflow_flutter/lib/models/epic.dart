class Epic {
  final String id;
  final String businessId;
  final String name;
  final String? description;
  final String status;
  final String createdAt;
  final String updatedAt;

  Epic({
    required this.id,
    required this.businessId,
    required this.name,
    this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Epic.fromJson(Map<String, dynamic> json) {
    return Epic(
      id: (json['id'] as String?) ?? '',
      businessId: (json['businessId'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      description: json['description'] as String?,
      status: (json['status'] as String?) ?? 'active',
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'name': name,
      'description': description,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
