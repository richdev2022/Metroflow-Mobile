class BusinessProfile {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String industry;
  final String logoUrl;
  final String currency;

  BusinessProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.industry,
    required this.logoUrl,
    required this.currency,
  });

  factory BusinessProfile.fromJson(Map<String, dynamic> json) {
    return BusinessProfile(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      phoneNumber: (json['phone_number'] as String?) ?? '',
      industry: (json['industry'] as String?) ?? '',
      logoUrl: (json['logo_url'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'NGN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone_number': phoneNumber,
      'industry': industry,
      'logo_url': logoUrl,
      'currency': currency,
    };
  }
}
