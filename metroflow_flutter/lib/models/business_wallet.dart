import 'wallet.dart';

class BusinessWallet extends Wallet {
  final String businessName;

  BusinessWallet({
    required super.id,
    required super.balance,
    required super.currency,
    super.accountNumber,
    super.virtualAccountNumber,
    super.bankName,
    super.bankCode,
    super.accountName,
    required super.type,
    required this.businessName,
  });

  factory BusinessWallet.fromJson(Map<String, dynamic> json) {
    final wallet = Wallet.fromJson(json);
    return BusinessWallet(
      id: wallet.id,
      balance: wallet.balance,
      currency: wallet.currency,
      accountNumber: wallet.accountNumber,
      virtualAccountNumber: wallet.virtualAccountNumber,
      bankName: wallet.bankName,
      bankCode: wallet.bankCode,
      accountName: wallet.accountName,
      type: wallet.type,
      businessName: (json['business_name'] as String?) ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() {
    final json = super.toJson();
    json['business_name'] = businessName;
    return json;
  }
}
