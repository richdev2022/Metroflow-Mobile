class Reaction {
  final String userId;
  final String? userName;
  final String type;

  Reaction({
    required this.userId,
    this.userName,
    required this.type,
  });

  factory Reaction.fromJson(Map<String, dynamic> json) {
    return Reaction(
      userId: (json['userId'] as String?) ?? '',
      userName: json['userName'] as String?,
      type: (json['type'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'userName': userName,
      'type': type,
    };
  }
}
