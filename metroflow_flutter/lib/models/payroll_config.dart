class PayrollConfig {
  final String salaryInterval;
  final String? salaryCustomDate;

  PayrollConfig({
    required this.salaryInterval,
    this.salaryCustomDate,
  });

  factory PayrollConfig.fromJson(Map<String, dynamic> json) {
    final data = (json['config'] as Map<String, dynamic>?) ??
        (json['data'] as Map<String, dynamic>?) ??
        json;
    return PayrollConfig(
      salaryInterval: (data['salary_interval'] as String?) ?? 'monthly',
      salaryCustomDate: data['salary_custom_date'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'salary_interval': salaryInterval,
      'salary_custom_date': salaryCustomDate,
    };
  }
}
