class AdjustmentItem {
  final String userId;
  final String type;
  final String amount;
  final String currency;

  AdjustmentItem({
    required this.userId,
    required this.type,
    required this.amount,
    required this.currency,
  });

  factory AdjustmentItem.fromJson(Map<String, dynamic> json) {
    return AdjustmentItem(
      userId: (json['userId'] as String?) ?? (json['user_id'] as String?) ?? '',
      type: (json['type'] as String?) ?? '',
      amount: '${json['amount'] ?? '0'}',
      currency: (json['currency'] as String?) ?? 'NGN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'userId': userId,
      'type': type,
      'amount': amount,
      'currency': currency,
    };
  }
}

class Adjustments {
  final int bonuses;
  final int deductions;
  final List<AdjustmentItem> bonusList;
  final List<AdjustmentItem> deductionList;

  Adjustments({
    required this.bonuses,
    required this.deductions,
    required this.bonusList,
    required this.deductionList,
  });

  factory Adjustments.fromJson(Map<String, dynamic> json) {
    return Adjustments(
      bonuses: (json['bonuses'] as num?)?.toInt() ?? 0,
      deductions: (json['deductions'] as num?)?.toInt() ?? 0,
      bonusList: ((json['bonus_list'] as List<dynamic>?) ?? const [])
          .map((e) => AdjustmentItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      deductionList: ((json['deduction_list'] as List<dynamic>?) ?? const [])
          .map((e) => AdjustmentItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bonuses': bonuses,
      'deductions': deductions,
      'bonus_list': bonusList.map((e) => e.toJson()).toList(),
      'deduction_list': deductionList.map((e) => e.toJson()).toList(),
    };
  }
}

class Employee {
  final String id;
  final String name;
  final String email;
  final dynamic salary;
  final String salaryCurrency;
  final String? bankAccountNumber;
  final String? bankCode;
  final String? accountName;
  final String role;
  final int? bonusesTotal;
  final int? deductionsTotal;
  final double netSalary;
  final String? nextPayDate;
  final String? salaryCalculationStatus;
  final String? contractStartDate;
  final Adjustments? adjustments;

  Employee({
    required this.id,
    required this.name,
    required this.email,
    required this.salary,
    required this.salaryCurrency,
    this.bankAccountNumber,
    this.bankCode,
    this.accountName,
    required this.role,
    this.bonusesTotal,
    this.deductionsTotal,
    required this.netSalary,
    this.nextPayDate,
    this.salaryCalculationStatus,
    this.contractStartDate,
    this.adjustments,
  });

  factory Employee.fromJson(Map<String, dynamic> json) {
    final netSalaryValue = json['net_salary'] ?? json['netSalary'];
    return Employee(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      email: (json['email'] as String?) ?? '',
      salary: json['salary'],
      salaryCurrency: (json['salary_currency'] as String?) ?? 'NGN',
      bankAccountNumber: json['bank_account_number'] as String?,
      bankCode: json['bank_code'] as String?,
      accountName: json['account_name'] as String?,
      role: (json['role'] as String?) ?? '',
      bonusesTotal: (json['bonuses_total'] as num?)?.toInt() ?? (json['bonusesTotal'] as num?)?.toInt(),
      deductionsTotal: (json['deductions_total'] as num?)?.toInt() ?? (json['deductionsTotal'] as num?)?.toInt(),
      netSalary: netSalaryValue is num ? netSalaryValue.toDouble() : double.tryParse('$netSalaryValue') ?? 0,
      nextPayDate: json['next_pay_date'] as String?,
      salaryCalculationStatus: json['salary_calculation_status'] as String?,
      contractStartDate: json['contract_start_date'] as String?,
      adjustments: json['adjustments'] != null
          ? Adjustments.fromJson(json['adjustments'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'salary': salary,
      'salary_currency': salaryCurrency,
      'bank_account_number': bankAccountNumber,
      'bank_code': bankCode,
      'account_name': accountName,
      'role': role,
      'bonuses_total': bonusesTotal,
      'deductions_total': deductionsTotal,
      'netSalary': netSalary,
      'next_pay_date': nextPayDate,
      'salary_calculation_status': salaryCalculationStatus,
      'contract_start_date': contractStartDate,
      'adjustments': adjustments?.toJson(),
    };
  }
}
