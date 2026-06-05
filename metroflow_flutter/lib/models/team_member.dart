class TeamMember {
  final String id;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? joinedAt;

  TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.joinedAt,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      joinedAt: json['joinedAt'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'status': status,
      'joinedAt': joinedAt,
    };
  }
}
