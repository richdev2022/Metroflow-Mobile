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
  // Admin-configured revenue feature knobs (Payment Links / Invoices / AI credits)
  final bool paymentLinksEnabled;
  final int? maxPaymentLinks;
  final double? paymentLinkFeeDiscountPercent;
  final double? aiCreditDiscountPercent;
  final bool invoicesEnabled;
  final int? maxInvoicesPerMonth;
  final double? invoiceFeeDiscountPercent;
  // Daily-use business revenue features (Storefront / Recurring Billing)
  final bool storeEnabled;
  final int? maxStoreProducts;
  final double? storeFeeDiscountPercent;
  final bool recurringEnabled;
  final int? maxSubscriptionPlans;
  final double? subscriptionFeeDiscountPercent;

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
    this.paymentLinksEnabled = true,
    this.maxPaymentLinks,
    this.paymentLinkFeeDiscountPercent,
    this.aiCreditDiscountPercent,
    this.invoicesEnabled = true,
    this.maxInvoicesPerMonth,
    this.invoiceFeeDiscountPercent,
    this.storeEnabled = true,
    this.maxStoreProducts,
    this.storeFeeDiscountPercent,
    this.recurringEnabled = true,
    this.maxSubscriptionPlans,
    this.subscriptionFeeDiscountPercent,
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
      paymentLinksEnabled: json['payment_links_enabled'] != false,
      maxPaymentLinks: _optionalInt(json['max_payment_links']),
      paymentLinkFeeDiscountPercent: _optionalDouble(json['payment_link_fee_discount_percent']),
      aiCreditDiscountPercent: _optionalDouble(json['ai_credit_discount_percent']),
      invoicesEnabled: json['invoices_enabled'] != false,
      maxInvoicesPerMonth: _optionalInt(json['max_invoices_per_month']),
      invoiceFeeDiscountPercent: _optionalDouble(json['invoice_fee_discount_percent']),
      storeEnabled: json['store_enabled'] != false,
      maxStoreProducts: _optionalInt(json['max_store_products']),
      storeFeeDiscountPercent: _optionalDouble(json['store_fee_discount_percent']),
      recurringEnabled: json['recurring_enabled'] != false,
      maxSubscriptionPlans: _optionalInt(json['max_subscription_plans']),
      subscriptionFeeDiscountPercent: _optionalDouble(json['subscription_fee_discount_percent']),
    );
  }

  static int? _optionalInt(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _optionalDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
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
