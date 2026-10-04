class ProductDocumentation {
  final String id;
  final String businessId;
  final String ideaId;
  final String title;
  final String content;
  final String? logoUrl;
  final String createdBy;
  final String createdAt;
  final String updatedAt;

  ProductDocumentation({
    required this.id,
    required this.businessId,
    required this.ideaId,
    required this.title,
    required this.content,
    this.logoUrl,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductDocumentation.fromJson(Map<String, dynamic> json) {
    return ProductDocumentation(
      id: (json['id'] as String?) ?? '',
      businessId: (json['businessId'] as String?) ?? '',
      ideaId: (json['ideaId'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      content: (json['content'] as String?) ?? '',
      logoUrl: json['logoUrl'] as String?,
      createdBy: (json['createdBy'] as String?) ?? '',
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'businessId': businessId,
      'ideaId': ideaId,
      'title': title,
      'content': content,
      'logoUrl': logoUrl,
      'createdBy': createdBy,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}
