class Bank {
  final String code;
  final String name;

  Bank({
    required this.code,
    required this.name,
  });

  factory Bank.fromJson(Map<String, dynamic> json) {
    return Bank(
      code: (json['code'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'code': code,
      'name': name,
    };
  }
}
