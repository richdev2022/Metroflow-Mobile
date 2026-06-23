class VirtualAccount {
  final String? id;
  final String? walletId;
  final String? paymentProvider;
  final String? virtualAccountNumber;
  final String? bankCode;
  final String? accountName;
  final String? customerIdentifier;
  final String? beneficiaryAccount;
  final Map<String, dynamic>? providerMetadata;
  final String? createdAt;
  final String? updatedAt;
  final bool? isActive;

  VirtualAccount({
    this.id,
    this.walletId,
    this.paymentProvider,
    this.virtualAccountNumber,
    this.bankCode,
    this.accountName,
    this.customerIdentifier,
    this.beneficiaryAccount,
    this.providerMetadata,
    this.createdAt,
    this.updatedAt,
    this.isActive,
  });

  factory VirtualAccount.fromJson(Map<String, dynamic> json) {
    return VirtualAccount(
      id: json['id'] as String?,
      walletId: json['wallet_id'] as String?,
      paymentProvider: json['payment_provider'] as String?,
      virtualAccountNumber: json['virtual_account_number'] as String?,
      bankCode: json['bank_code'] as String?,
      accountName: json['account_name'] as String?,
      customerIdentifier: json['customer_identifier'] as String?,
      beneficiaryAccount: json['beneficiary_account'] as String?,
      providerMetadata: json['provider_metadata'] as Map<String, dynamic>?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      isActive: json['is_active'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'wallet_id': walletId,
      'payment_provider': paymentProvider,
      'virtual_account_number': virtualAccountNumber,
      'bank_code': bankCode,
      'account_name': accountName,
      'customer_identifier': customerIdentifier,
      'beneficiary_account': beneficiaryAccount,
      'provider_metadata': providerMetadata,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'is_active': isActive,
    };
  }
}

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
  final List<VirtualAccount> virtualAccounts;

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
    this.virtualAccounts = const [],
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    final balance = json['balance'];
    final virtualAccountsJson = json['virtual_accounts'] as List<dynamic>?;
    final virtualAccounts = virtualAccountsJson
            ?.map((e) => VirtualAccount.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
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
      virtualAccounts: virtualAccounts,
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
      'virtual_accounts': virtualAccounts.map((e) => e.toJson()).toList(),
    };
  }
}
