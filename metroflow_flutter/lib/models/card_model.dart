class CardModel {
  final String id;
  final String last4;
  final String cardType;
  final String expMonth;
  final String expYear;
  final bool isActive;

  CardModel({
    required this.id,
    required this.last4,
    required this.cardType,
    required this.expMonth,
    required this.expYear,
    required this.isActive,
  });

  factory CardModel.fromJson(Map<String, dynamic> json) {
    return CardModel(
      id: (json['id'] as String?) ?? '',
      last4: (json['last4'] as String?) ?? '',
      cardType: (json['card_type'] as String?) ?? '',
      expMonth: '${json['exp_month'] ?? ''}',
      expYear: '${json['exp_year'] ?? ''}',
      isActive: (json['is_active'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'last4': last4,
      'card_type': cardType,
      'exp_month': expMonth,
      'exp_year': expYear,
      'is_active': isActive,
    };
  }
}
