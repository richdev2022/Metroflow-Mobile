class FeeCondition {
  final double fee;
  final String operator;
  final double threshold;

  FeeCondition({
    required this.fee,
    required this.operator,
    required this.threshold,
  });

  factory FeeCondition.fromJson(Map<String, dynamic> json) {
    final fee = json['fee'];
    final threshold = json['threshold'];
    return FeeCondition(
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
      operator: (json['operator'] as String?) ?? '',
      threshold: threshold is num ? threshold.toDouble() : double.tryParse('$threshold') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'fee': fee,
      'operator': operator,
      'threshold': threshold,
    };
  }
}

class FeeRange {
  final double min;
  final double max;
  final double fee;

  FeeRange({
    required this.min,
    required this.max,
    required this.fee,
  });

  factory FeeRange.fromJson(Map<String, dynamic> json) {
    final min = json['min'];
    final max = json['max'];
    final fee = json['fee'];
    return FeeRange(
      min: min is num ? min.toDouble() : double.tryParse('$min') ?? 0,
      max: max is num ? max.toDouble() : double.tryParse('$max') ?? 0,
      fee: fee is num ? fee.toDouble() : double.tryParse('$fee') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'min': min,
      'max': max,
      'fee': fee,
    };
  }
}

class FeeConfigData {
  final double? amount;
  final double? percentage;
  final double? cap;
  final List<FeeCondition>? conditions;
  final List<FeeRange>? ranges;

  FeeConfigData({
    this.amount,
    this.percentage,
    this.cap,
    this.conditions,
    this.ranges,
  });

  factory FeeConfigData.fromJson(Map<String, dynamic> json) {
    double? readDouble(String key) {
      final value = json[key];
      if (value == null) return null;
      return value is num ? value.toDouble() : double.tryParse('$value');
    }

    return FeeConfigData(
      amount: readDouble('amount'),
      percentage: readDouble('percentage'),
      cap: readDouble('cap'),
      conditions: json['conditions'] != null
          ? (json['conditions'] as List<dynamic>)
              .map((e) => FeeCondition.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
      ranges: json['ranges'] != null
          ? (json['ranges'] as List<dynamic>)
              .map((e) => FeeRange.fromJson(e as Map<String, dynamic>))
              .toList()
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'percentage': percentage,
      'cap': cap,
      'conditions': conditions?.map((e) => e.toJson()).toList(),
      'ranges': ranges?.map((e) => e.toJson()).toList(),
    };
  }
}

class FeeConfig {
  final String id;
  final String name;
  final String feeType;
  final String configType;
  final FeeConfigData config;
  final String currency;

  FeeConfig({
    required this.id,
    required this.name,
    required this.feeType,
    required this.configType,
    required this.config,
    required this.currency,
  });

  factory FeeConfig.fromJson(Map<String, dynamic> json) {
    return FeeConfig(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      feeType: (json['fee_type'] as String?) ?? '',
      configType: (json['config_type'] as String?) ?? 'flat',
      config: FeeConfigData.fromJson((json['config'] as Map<String, dynamic>?) ?? const {}),
      currency: (json['currency'] as String?) ?? 'NGN',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'fee_type': feeType,
      'config_type': configType,
      'config': config.toJson(),
      'currency': currency,
    };
  }
}
