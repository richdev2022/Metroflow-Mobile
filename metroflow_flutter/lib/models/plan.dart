class Plan {
  final String id;
  final String name;
  final double price;
  final String? discount;
  final String? duration;
  final String? currency;
  final String description;
  final List<String> features;
  final int maxTeamMembers;
  final int trialDays;

  Plan({
    required this.id,
    required this.name,
    required this.price,
    this.discount,
    this.duration,
    this.currency,
    required this.description,
    required this.features,
    required this.maxTeamMembers,
    required this.trialDays,
  });

  factory Plan.fromJson(Map<String, dynamic> json) {
    final price = json['price'];
    final featuresList = (json['features'] as List<dynamic>?) ?? [];
    final features = featuresList.map((f) => f.toString()).toList();
    return Plan(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      price: price is num ? price.toDouble() : double.tryParse('$price') ?? 0,
      discount: json['discount']?.toString(),
      duration: json['duration'] as String?,
      currency: json['currency'] as String?,
      description: (json['description'] as String?) ?? '',
      features: features,
      maxTeamMembers: (json['max_team_members'] is num) ? (json['max_team_members'] as num).toInt() : int.tryParse('${json['max_team_members']}') ?? 0,
      trialDays: (json['trial_days'] is num) ? (json['trial_days'] as num).toInt() : int.tryParse('${json['trial_days']}') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'discount': discount,
      'duration': duration,
      'currency': currency,
      'description': description,
      'features': features,
      'max_team_members': maxTeamMembers,
      'trial_days': trialDays,
    };
  }
}
