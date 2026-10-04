class Attachment {
  final String id;
  final String name;
  final String url;
  final String type;

  Attachment({
    required this.id,
    required this.name,
    required this.url,
    required this.type,
  });

  factory Attachment.fromJson(Map<String, dynamic> json) {
    return Attachment(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type,
    };
  }
}
