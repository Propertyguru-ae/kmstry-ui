class BlockedUser {
  final String userId;
  final String fullName;

  BlockedUser({
    required this.userId,
    required this.fullName,
  });

  factory BlockedUser.fromJson(Map<String, dynamic> json) {
    final user = json['user'] is Map<String, dynamic>
        ? json['user'] as Map<String, dynamic>
        : null;
    final blocked = json['blocked'] is Map<String, dynamic>
        ? json['blocked'] as Map<String, dynamic>
        : null;

    final userId =
        json['user_id'] as String? ??
        json['blocked_id'] as String? ??
        json['blocked_user_id'] as String? ??
        json['target_user_id'] as String? ??
        json['userId'] as String? ??
        blocked?['id'] as String? ??
        user?['id'] as String? ??
        '';

    final fullName =
        json['full_name'] as String? ??
        json['name'] as String? ??
        json['fullName'] as String? ??
        blocked?['full_name'] as String? ??
        blocked?['fullName'] as String? ??
        user?['full_name'] as String? ??
        user?['fullName'] as String? ??
        '';

    return BlockedUser(
      userId: userId,
      fullName: fullName,
    );
  }
}
