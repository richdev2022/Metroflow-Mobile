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
  // Admin-configured RTC limits / capability flags
  final int? maxMeetingDuration;
  final int? maxParticipants;
  final int? maxRecordingDuration;
  final int? maxRecordingStorage;
  final bool waitingRoomEnabled;
  final bool recordingEnabled;
  final bool screenSharingEnabled;
  final bool breakoutRoomsEnabled;
  final bool virtualBackgrounds;
  final bool liveCaptions;

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
    this.maxMeetingDuration,
    this.maxParticipants,
    this.maxRecordingDuration,
    this.maxRecordingStorage,
    this.waitingRoomEnabled = false,
    this.recordingEnabled = false,
    this.screenSharingEnabled = true,
    this.breakoutRoomsEnabled = false,
    this.virtualBackgrounds = false,
    this.liveCaptions = false,
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
      maxMeetingDuration: _optionalInt(json['max_meeting_duration']),
      maxParticipants: _optionalInt(json['max_participants']),
      maxRecordingDuration: _optionalInt(json['max_recording_duration']),
      maxRecordingStorage: _optionalInt(json['max_recording_storage']),
      waitingRoomEnabled: json['waiting_room_enabled'] == true,
      recordingEnabled: json['recording_enabled'] == true,
      screenSharingEnabled: json['screen_sharing_enabled'] != false,
      breakoutRoomsEnabled: json['breakout_rooms_enabled'] == true,
      virtualBackgrounds: json['virtual_backgrounds'] == true,
      liveCaptions: json['live_captions'] == true,
    );
  }

  static int? _optionalInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
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
