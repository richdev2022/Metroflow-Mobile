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

class QueuedTransferRecipient {
  final String accountNumber;
  final String bankCode;
  final String accountName;

  QueuedTransferRecipient({
    required this.accountNumber,
    required this.bankCode,
    required this.accountName,
  });

  factory QueuedTransferRecipient.fromJson(Map<String, dynamic> json) {
    return QueuedTransferRecipient(
      accountNumber: (json['accountNumber'] as String?) ?? '',
      bankCode: (json['bankCode'] as String?) ?? '',
      accountName: (json['accountName'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'accountNumber': accountNumber,
      'bankCode': bankCode,
      'accountName': accountName,
    };
  }
}

class QueuedTransfer {
  final String id;
  final String reference;
  final double amount;
  final String currency;
  final double fee;
  final QueuedTransferRecipient recipient;
  final String status;
  final String? paymentProvider;
  final String createdAt;

  QueuedTransfer({
    required this.id,
    required this.reference,
    required this.amount,
    required this.currency,
    required this.fee,
    required this.recipient,
    required this.status,
    this.paymentProvider,
    required this.createdAt,
  });

  factory QueuedTransfer.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final fee = json['fee'];
    return QueuedTransfer(
      id: (json['id'] as String?) ?? '',
      reference: (json['reference'] as String?) ?? '',
      amount: amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0,
      currency: (json['currency'] as String?) ?? 'NGN',
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
      recipient: QueuedTransferRecipient.fromJson(json['recipient'] as Map<String, dynamic>? ?? {}),
      status: (json['status'] as String?) ?? 'pending',
      paymentProvider: json['paymentProvider'] as String?,
      createdAt: (json['createdAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference': reference,
      'amount': amount,
      'currency': currency,
      'fee': fee,
      'recipient': recipient.toJson(),
      'status': status,
      'paymentProvider': paymentProvider,
      'createdAt': createdAt,
    };
  }
}

class TransferTotals {
  final double amount;
  final double fee;
  final double total;

  TransferTotals({
    required this.amount,
    required this.fee,
    required this.total,
  });

  factory TransferTotals.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final fee = json['fee'];
    final total = json['total'];
    return TransferTotals(
      amount: amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0,
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
      total: total is num ? total.toDouble() : double.tryParse('$total') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'fee': fee,
      'total': total,
    };
  }
}

class BulkTransferResponseData {
  final int queued;
  final String type;
  final String walletId;
  final TransferTotals totals;
  final List<QueuedTransfer> transfers;

  BulkTransferResponseData({
    required this.queued,
    required this.type,
    required this.walletId,
    required this.totals,
    required this.transfers,
  });

  factory BulkTransferResponseData.fromJson(Map<String, dynamic> json) {
    final transfersList = json['transfers'] as List<dynamic>? ?? [];
    return BulkTransferResponseData(
      queued: (json['queued'] as int?) ?? 0,
      type: (json['type'] as String?) ?? '',
      walletId: (json['walletId'] as String?) ?? '',
      totals: TransferTotals.fromJson(json['totals'] as Map<String, dynamic>? ?? {}),
      transfers: transfersList.map((e) => QueuedTransfer.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'queued': queued,
      'type': type,
      'walletId': walletId,
      'totals': totals.toJson(),
      'transfers': transfers.map((e) => e.toJson()).toList(),
    };
  }
}

class BulkTransferResponse {
  final bool success;
  final String? message;
  final BulkTransferResponseData? data;

  BulkTransferResponse({
    required this.success,
    this.message,
    this.data,
  });

  factory BulkTransferResponse.fromJson(Map<String, dynamic> json) {
    return BulkTransferResponse(
      success: (json['success'] as bool?) ?? false,
      message: json['message'] as String?,
      data: json['data'] != null ? BulkTransferResponseData.fromJson(json['data'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'data': data?.toJson(),
    };
  }
}

class SingleTransferResponseData {
  final String id;
  final String reference;
  final double amount;
  final String currency;
  final double fee;
  final double total;
  final QueuedTransferRecipient recipient;
  final String status;
  final String walletId;
  final String? paymentProvider;
  final String createdAt;
  final String updatedAt;

  SingleTransferResponseData({
    required this.id,
    required this.reference,
    required this.amount,
    required this.currency,
    required this.fee,
    required this.total,
    required this.recipient,
    required this.status,
    required this.walletId,
    this.paymentProvider,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SingleTransferResponseData.fromJson(Map<String, dynamic> json) {
    final amount = json['amount'];
    final fee = json['fee'];
    final total = json['total'];
    return SingleTransferResponseData(
      id: (json['id'] as String?) ?? '',
      reference: (json['reference'] as String?) ?? '',
      amount: amount is num ? amount.toDouble() : double.tryParse('$amount') ?? 0,
      currency: (json['currency'] as String?) ?? 'NGN',
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
      total: total is num ? total.toDouble() : double.tryParse('$total') ?? 0,
      recipient: QueuedTransferRecipient.fromJson(json['recipient'] as Map<String, dynamic>? ?? {}),
      status: (json['status'] as String?) ?? 'pending',
      walletId: (json['walletId'] as String?) ?? '',
      paymentProvider: json['paymentProvider'] as String?,
      createdAt: (json['createdAt'] as String?) ?? '',
      updatedAt: (json['updatedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'reference': reference,
      'amount': amount,
      'currency': currency,
      'fee': fee,
      'total': total,
      'recipient': recipient.toJson(),
      'status': status,
      'walletId': walletId,
      'paymentProvider': paymentProvider,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }
}

class SingleTransferResponse {
  final bool success;
  final String? message;
  final SingleTransferResponseData? data;

  SingleTransferResponse({
    required this.success,
    this.message,
    this.data,
  });

  factory SingleTransferResponse.fromJson(Map<String, dynamic> json) {
    return SingleTransferResponse(
      success: (json['success'] as bool?) ?? false,
      message: json['message'] as String?,
      data: json['data'] != null ? SingleTransferResponseData.fromJson(json['data'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'message': message,
      'data': data?.toJson(),
    };
  }
}
