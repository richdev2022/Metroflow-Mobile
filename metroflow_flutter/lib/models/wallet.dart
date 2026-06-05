class Wallet {
  final String id;
  final double balance;
  final String currency;
  final String? accountNumber;
  final String? virtualAccountNumber;
  final String? bankName;
  final String? bankCode;
  final String? accountName;
  final String type;

  Wallet({
    required this.id,
    required this.balance,
    required this.currency,
    this.accountNumber,
    this.virtualAccountNumber,
    this.bankName,
    this.bankCode,
    this.accountName,
    required this.type,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'];
    return Wallet(
      id: (json['id'] as String?) ?? '',
      balance: balance is num ? balance.toDouble() : double.tryParse('$balance') ?? 0,
      currency: (json['currency'] as String?) ?? 'NGN',
      accountNumber: json['account_number'] as String?,
      virtualAccountNumber: json['virtual_account_number'] as String?,
      bankName: json['bank_name'] as String?,
      bankCode: json['bank_code'] as String?,
      accountName: json['account_name'] as String?,
      type: (json['type'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'balance': balance,
      'currency': currency,
      'account_number': accountNumber,
      'virtual_account_number': virtualAccountNumber,
      'bank_name': bankName,
      'bank_code': bankCode,
      'account_name': accountName,
      'type': type,
    };
  }
}
