/// Model for GET /matches list item.
/// Backend returns: match_id, chat_id, user_id, full_name.
class MatchItem {
  final String matchId;
  final String? chatId;
  final String userId;
  final String? username;
  final String fullName;
  final String? checkinId;
  final String? venueId;

  MatchItem({
    required this.matchId,
    this.chatId,
    required this.userId,
    this.username,
    required this.fullName,
    this.checkinId,
    this.venueId,
  });

  factory MatchItem.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    final user = userRaw is Map<String, dynamic>
        ? userRaw
        : (userRaw is Map ? Map<String, dynamic>.from(userRaw) : null);
    final matchId = json['match_id'] as String? ?? json['matchId'] as String? ?? '';
    final chatId = json['chat_id'] as String? ?? json['chatId'] as String?;
    final userId =
        json['user_id'] as String? ??
        json['userId'] as String? ??
        user?['id'] as String? ??
        '';
    final username =
        json['username'] as String? ??
        json['user_name'] as String? ??
        user?['username'] as String? ??
        user?['user_name'] as String?;
    final fullName =
        json['full_name'] as String? ??
        json['fullName'] as String? ??
        user?['full_name'] as String? ??
        user?['fullName'] as String? ??
        '';
    final checkinId = json['checkin_id'] as String? ?? json['checkinId'] as String?;
    final venueId = json['venue_id'] as String? ?? json['venueId'] as String?;

    return MatchItem(
      matchId: matchId,
      chatId: chatId,
      userId: userId,
      username: username,
      fullName: fullName,
      checkinId: checkinId,
      venueId: venueId,
    );
  }
}
