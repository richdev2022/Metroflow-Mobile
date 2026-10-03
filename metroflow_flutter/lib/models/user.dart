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

  /// DEFENSIVE on purpose — this model feeds the chat "New Conversation"
  /// participant picker, the team screens and call pickers.
  ///
  /// HISTORY: `json['phone'] as String` threw a TypeError for EVERY backend
  /// /team row (the API returns `phoneNumber`, not `phone`), the exception
  /// aborted the whole `.map()` in _loadTeamMembers, the silent catch left
  /// the member list EMPTY, and the New-Conversation dialog showed a blank
  /// "Select Participants" box. One strict cast broke the entire picker —
  /// every field is now null-safe and accepts both spellings.
  factory User.fromJson(Map<String, dynamic> json) {
    String asString(dynamic v, [String fallback = '']) {
      if (v == null) return fallback;
      return v.toString();
    }

    return User(
      id: asString(json['id'] ?? json['user_id']),
      email: asString(json['email']),
      name: asString(
        (json['name'] as String?)?.isNotEmpty == true
            ? json['name']
            : (json['email'] ?? 'Teammate'),
      ),
      phone: asString(json['phone'] ?? json['phoneNumber'] ?? json['phone_number']),
      kycStatus: asString(json['kyc_status'] ?? json['kycStatus'], 'pending'),
      role: asString(json['role'], 'member'),
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
