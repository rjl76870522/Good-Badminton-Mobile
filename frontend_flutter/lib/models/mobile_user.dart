class MobileUser {
  const MobileUser({
    required this.userId,
    required this.displayName,
    required this.createdAt,
    required this.updatedAt,
  });

  final String userId;
  final String displayName;
  final double createdAt;
  final double updatedAt;

  factory MobileUser.fromJson(Map<String, dynamic> json) {
    return MobileUser(
      userId: json['user_id']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      createdAt: _number(json['created_at']),
      updatedAt: _number(json['updated_at']),
    );
  }
}

double _number(dynamic value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}
