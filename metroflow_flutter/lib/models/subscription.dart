class Subscription {
  final String id;
  final String name;
  final String subscriptionStatus;
  final String? trialEndsAt;
  final String planId;
  final String planName;
  final String planPrice;
  final String? planDiscount;
  final int maxTeamMembers;
  final List<String> features;
  final int teamUsage;
  final String? nextDueSubscriptionDate;

  Subscription({
    required this.id,
    required this.name,
    required this.subscriptionStatus,
    this.trialEndsAt,
    required this.planId,
    required this.planName,
    required this.planPrice,
    this.planDiscount,
    required this.maxTeamMembers,
    required this.features,
    required this.teamUsage,
    this.nextDueSubscriptionDate,
  });

  // Getter to parse plan price to double
  double get price {
    try {
      return double.tryParse(planPrice) ?? 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  factory Subscription.fromJson(Map<String, dynamic> json) {
    final featuresList = (json['features'] as List<dynamic>?) ?? [];
    final features = featuresList.map((f) => f.toString()).toList();
    
    final planPriceValue = json['plan_price'];
    final planPriceStr = planPriceValue is num ? planPriceValue.toString() : (planPriceValue as String?) ?? '0';
    
    return Subscription(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      subscriptionStatus: (json['subscription_status'] as String?) ?? 'inactive',
      trialEndsAt: json['trial_ends_at'] as String?,
      planId: (json['plan_id'] as String?) ?? '',
      planName: (json['plan_name'] as String?) ?? 'Free Plan',
      planPrice: planPriceStr,
      planDiscount: json['plan_discount']?.toString(),
      maxTeamMembers: (json['max_team_members'] is num) ? (json['max_team_members'] as num).toInt() : int.tryParse('${json['max_team_members']}') ?? 0,
      features: features,
      teamUsage: (json['team_usage'] is num) ? (json['team_usage'] as num).toInt() : int.tryParse('${json['team_usage']}') ?? 0,
      nextDueSubscriptionDate: json['next_due_subscription_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'subscription_status': subscriptionStatus,
      'trial_ends_at': trialEndsAt,
      'plan_id': planId,
      'plan_name': planName,
      'plan_price': planPrice,
      'plan_discount': planDiscount,
      'max_team_members': maxTeamMembers,
      'features': features,
      'team_usage': teamUsage,
      'next_due_subscription_date': nextDueSubscriptionDate,
    };
  }
}
