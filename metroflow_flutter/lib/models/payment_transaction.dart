class PaymentTransaction {
  final String id;
  final String? businessId;
  final String? planId;
  final dynamic amount;
  final String currency;
  final String reference;
  final String status;
  final dynamic gatewayResponse;
  final String createdAt;
  final String? updatedAt;
  final String? transactionType;
  final String? planName;
  final String? walletId;
  final String? direction;
  final String? userId;
  final String? type;
  final String? description;
  final dynamic fee;

  PaymentTransaction({
    required this.id,
    this.businessId,
    this.planId,
    required this.amount,
    required this.currency,
    required this.reference,
    required this.status,
    this.gatewayResponse,
    required this.createdAt,
    this.updatedAt,
    this.transactionType,
    this.planName,
    this.walletId,
    this.direction,
    this.userId,
    this.type,
    this.description,
    this.fee,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: (json['id'] as String?) ?? '',
      businessId: json['business_id'] as String?,
      planId: json['plan_id'] as String?,
      amount: json['amount'],
      currency: (json['currency'] as String?) ?? 'NGN',
      reference: (json['reference'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      gatewayResponse: json['gateway_response'],
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: json['updated_at'] as String?,
      transactionType: json['transaction_type'] as String?,
      planName: json['plan_name'] as String?,
      walletId: json['wallet_id'] as String?,
      direction: json['direction'] as String?,
      userId: json['user_id'] as String?,
      type: json['type'] as String?,
      description: json['description'] as String?,
      fee: json['fee'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'plan_id': planId,
      'amount': amount,
      'currency': currency,
      'reference': reference,
      'status': status,
      'gateway_response': gatewayResponse,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'transaction_type': transactionType,
      'plan_name': planName,
      'wallet_id': walletId,
      'direction': direction,
      'user_id': userId,
      'type': type,
      'description': description,
      'fee': fee,
    };
  }
}
