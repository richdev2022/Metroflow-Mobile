class TeamMember {
  final String id;
  final String name;
  final String email;
  final String role;
  final String status;
  final String? joinedAt;
  final String? businessId;
  final bool? emailVerified;
  final String? lastLogin;
  final String? createdAt;
  final String? updatedAt;
  final String? kycStatus;
  final double? salary;
  final String? salaryCurrency;
  final String? bankCode;
  final String? accountNumber;
  final String? accountName;

  TeamMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.status,
    this.joinedAt,
    this.businessId,
    this.emailVerified,
    this.lastLogin,
    this.createdAt,
    this.updatedAt,
    this.kycStatus,
    this.salary,
    this.salaryCurrency,
    this.bankCode,
    this.accountNumber,
    this.accountName,
  });

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      role: (json['role'] as String?) ?? '',
      status: (json['status'] as String?) ?? '',
      joinedAt: json['joinedAt'] as String?,
      businessId: json['businessId'] as String?,
      emailVerified: json['emailVerified'] as bool?,
      lastLogin: json['lastLogin'] as String?,
      createdAt: json['createdAt'] as String?,
      updatedAt: json['updatedAt'] as String?,
      kycStatus: json['kycStatus'] as String?,
      salary: (json['salary'] as num?)?.toDouble(),
      salaryCurrency: json['salaryCurrency'] as String?,
      bankCode: json['bankCode'] as String?,
      accountNumber: json['accountNumber'] as String?,
      accountName: json['accountName'] as String?,
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
      'businessId': businessId,
      'emailVerified': emailVerified,
      'lastLogin': lastLogin,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'kycStatus': kycStatus,
      'salary': salary,
      'salaryCurrency': salaryCurrency,
      'bankCode': bankCode,
      'accountNumber': accountNumber,
      'accountName': accountName,
    };
  }
}
