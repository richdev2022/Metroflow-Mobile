class Transfer {
  final String id;
  final double amount;
  final String currency;
  final String status;
  final String reference;
  final String recipientName;
  final String? recipientAccount;
  final String? recipientBank;
  final String? remark;
  final String? sourceType;
  final String? sourceId;
  final String? walletId;
  final double fee;
  final String? failureReason;
  final String createdAt;
  final String updatedAt;

  Transfer({
    required this.id,
    required this.amount,
    required this.currency,
    required this.status,
    required this.reference,
    required this.recipientName,
    this.recipientAccount,
    this.recipientBank,
    this.remark,
    this.sourceType,
    this.sourceId,
    this.walletId,
    required this.fee,
    this.failureReason,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Transfer.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final fee = json['fee'];
    return Transfer(
      id: (json['id'] as String?) ?? '',
      amount: amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0,
      currency: (json['currency'] as String?) ?? 'NGN',
      status: (json['status'] as String?) ?? 'pending',
      reference: (json['reference'] as String?) ?? '',
      recipientName: (json['recipient_name'] as String?) ?? '',
      recipientAccount: json['recipient_account'] as String?,
      recipientBank: json['recipient_bank'] as String?,
      remark: json['remark'] as String?,
      sourceType: json['source_type'] as String?,
      sourceId: json['source_id'] as String?,
      walletId: json['wallet_id'] as String?,
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
      failureReason: json['failure_reason'] as String?,
      createdAt: (json['created_at'] as String?) ?? '',
      updatedAt: (json['updated_at'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'amount': amount,
      'currency': currency,
      'status': status,
      'reference': reference,
      'recipient_name': recipientName,
      'recipient_account': recipientAccount,
      'recipient_bank': recipientBank,
      'remark': remark,
      'source_type': sourceType,
      'source_id': sourceId,
      'wallet_id': walletId,
      'fee': fee,
      'failure_reason': failureReason,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }
}
