class Address {
  final String country;
  final String state;
  final String city;
  final String street;
  final String houseNumber;

  Address({
    required this.country,
    required this.state,
    required this.city,
    required this.street,
    required this.houseNumber,
  });

  factory Address.fromJson(Map<String, dynamic> json) {
    return Address(
      country: (json['country'] as String?) ?? '',
      state: (json['state'] as String?) ?? '',
      city: (json['city'] as String?) ?? '',
      street: (json['street'] as String?) ?? '',
      houseNumber: (json['houseNumber'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'country': country,
      'state': state,
      'city': city,
      'street': street,
      'houseNumber': houseNumber,
    };
  }
}

class Business {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String industry;
  final String logoUrl;
  final String currency;
  final Address? address;
  final String kycStatus;
  final String? gtbAccountNumber;

  Business({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.industry,
    required this.logoUrl,
    required this.currency,
    this.address,
    required this.kycStatus,
    this.gtbAccountNumber,
  });

  factory Business.fromJson(Map<String, dynamic> json) {
    return Business(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      phoneNumber: (json['phone_number'] as String?) ?? '',
      industry: (json['industry'] as String?) ?? '',
      logoUrl: (json['logo_url'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'NGN',
      address: json['address'] != null
          ? Address.fromJson(json['address'] as Map<String, dynamic>)
          : null,
      kycStatus: (json['kycStatus'] as String?) ?? 'none',
      gtbAccountNumber: json['gtbAccountNumber'] as String?,
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
      'address': address?.toJson(),
      'kycStatus': kycStatus,
      'gtbAccountNumber': gtbAccountNumber,
    };
  }
}
