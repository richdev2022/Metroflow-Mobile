class KycUserStatus {
  final String bvnStatus;
  final String ninStatus;
  final String? rejectionReason;

  KycUserStatus({
    required this.bvnStatus,
    required this.ninStatus,
    this.rejectionReason,
  });

  factory KycUserStatus.fromJson(Map<String, dynamic> json) {
    String normalizedStatus(String status) {
      return status == 'true' ? 'verified' : status;
    }

    return KycUserStatus(
      bvnStatus: normalizedStatus(
        (json['bvnStatus'] as String?) ??
            (json['bvn_status'] as String?) ??
            (json['bvn_verified'] == true ? 'verified' : 'none'),
      ),
      ninStatus: normalizedStatus(
        (json['ninStatus'] as String?) ??
            (json['nin_status'] as String?) ??
            (json['nin_verified'] == true ? 'verified' : 'none'),
      ),
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'bvnStatus': bvnStatus,
      'ninStatus': ninStatus,
      'rejection_reason': rejectionReason,
    };
  }
}

class KycBusinessStatus {
  final String status;
  final String? rejectionReason;

  KycBusinessStatus({
    required this.status,
    this.rejectionReason,
  });

  factory KycBusinessStatus.fromJson(Map<String, dynamic> json) {
    return KycBusinessStatus(
      status: (json['status'] as String?) ??
          (json['business_kyc_status'] as String?) ??
          'none',
      rejectionReason: json['rejection_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'rejection_reason': rejectionReason,
    };
  }
}

class KycStatus {
  final KycUserStatus user;
  final KycBusinessStatus business;

  KycStatus({
    required this.user,
    required this.business,
  });

  factory KycStatus.fromJson(Map<String, dynamic> json) {
    final flatUser = {
      'bvnStatus': json['bvnStatus'] ?? json['bvn_status'],
      'ninStatus': json['ninStatus'] ?? json['nin_status'],
      'bvn_verified': json['bvn_verified'],
      'nin_verified': json['nin_verified'],
      'rejection_reason': json['rejection_reason'],
    };
    final flatBusiness = {
      'status': json['business_kyc_status'],
      'rejection_reason': json['business_rejection_reason'],
    };

    return KycStatus(
      user: KycUserStatus.fromJson(
        (json['user'] as Map<String, dynamic>?) ?? flatUser,
      ),
      business: KycBusinessStatus.fromJson(
        (json['business'] as Map<String, dynamic>?) ?? flatBusiness,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user': user.toJson(),
      'business': business.toJson(),
    };
  }

  bool get isTier1Verified {
    return user.bvnStatus == 'verified' || user.ninStatus == 'verified';
  }

  bool get isTier2Verified {
    return (user.bvnStatus == 'verified' && user.ninStatus == 'verified');
  }

  bool get isTier3Verified {
    return business.status == 'verified';
  }
}
