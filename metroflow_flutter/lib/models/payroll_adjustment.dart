class PayrollAdjustment {
  final String id;
  final String businessId;
  final String userId;
  final String type;
  final String amount;
  final String currency;
  final String reason;
  final String status;
  final String? transferId;
  final String createdAt;
  final String updatedAt;
  final String? processedAt;
  final String? userName;
  final String? userEmail;

  PayrollAdjustment({
    required this.id,
    required this.businessId,
    required this.userId,
    required this.type,
    required this.amount,
    required this.currency,
    required this.reason,
    required this.status,
    this.transferId,
    required this.createdAt,
    required this.updatedAt,
    this.processedAt,
    this.userName,
    this.userEmail,
  });

  factory PayrollAdjustment.fromJson(Map<String, dynamic> json) {
    return PayrollAdjustment(
      id: (json['id'] as String?) ?? '',
      businessId: (json['business_id'] as String?) ?? '',
      userId: (json['user_id'] as String?) ?? '',
      type: (json['type'] as String?) ?? 'bonus',
      amount: '${json['amount'] ?? '0'}',
      currency: (json['currency'] as String?) ?? 'NGN',
      reason: (json['reason'] as String?) ?? '',
      status: (json['status'] as String?) ?? 'pending',
      transferId: json['transfer_id'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
      processedAt: json['processed_at'] as String?,
      userName: json['user_name'] as String?,
      userEmail: json['user_email'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'business_id': businessId,
      'user_id': userId,
      'type': type,
      'amount': amount,
      'currency': currency,
      'reason': reason,
      'status': status,
      'transfer_id': transferId,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'processed_at': processedAt,
      'user_name': userName,
      'user_email': userEmail,
    };
  }
}
