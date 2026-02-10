/// Model for GET /matches list item.
/// Backend returns: match_id, chat_id, user_id, full_name.
class MatchItem {
  final String matchId;
  final String? chatId;
  final String userId;
  final String fullName;

  MatchItem({
    required this.matchId,
    this.chatId,
    required this.userId,
    required this.fullName,
  });

  factory MatchItem.fromJson(Map<String, dynamic> json) {
    final matchId = json['match_id'] as String? ?? json['matchId'] as String? ?? '';
    final chatId = json['chat_id'] as String? ?? json['chatId'] as String?;
    final userId = json['user_id'] as String? ?? json['userId'] as String? ?? '';
    final fullName = json['full_name'] as String? ?? json['fullName'] as String? ?? '';

    return MatchItem(
      matchId: matchId,
      chatId: chatId,
      userId: userId,
      fullName: fullName,
    );
  }
}
