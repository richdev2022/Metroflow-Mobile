class Idea {
  final String id;
  final String businessId;
  final String userId;
  final String? userName;
  final String title;
  final String description;
  final String status;
  final String createdAt;
  final String updatedAt;

  Idea({
    required this.id,
    required this.businessId,
    required this.userId,
    this.userName,
    required this.title,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Idea.fromJson(Map<String, dynamic> json) {
    return Idea(
      id: (json['id'] as String?) ?? '',
      businessId: (json['businessId'] as String?) ?? '',
      userId: (json['userId'] as String?) ?? '',
      userName: json['userName'] as String?,
      title: (json['title'] as String?) ?? '',
      description: (json['description'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'under_review',
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'userId': userId,
      'userName': userName,
      'title': title,
      'description': description,
      'status': status,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
