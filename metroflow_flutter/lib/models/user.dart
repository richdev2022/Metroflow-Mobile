class User {
  final String id;
  final String email;
  final String name;
  final String phone;
  final String kycStatus;
  final String role;

  User({
    required this.id,
    required this.email,
    required this.name,
    required this.phone,
    required this.kycStatus,
    required this.role,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String,
      phone: json['phone'] as String,
      kycStatus: json['kyc_status'] as String,
      role: json['role'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'name': name,
      'phone': phone,
      'kyc_status': kycStatus,
      'role': role,
    };
  }
}
