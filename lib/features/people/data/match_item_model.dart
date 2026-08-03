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
  final String? venueName;
  final String? venueType;
  final String? venuePhoto;
  final String? bio;

  /// Yalnızca galeriden yüklenen profil avatarı (check-in featured fotosu değil).
  final String? userPhotoUrl;

  MatchItem({
    required this.matchId,
    this.chatId,
    required this.userId,
    this.username,
    required this.fullName,
    this.checkinId,
    this.venueId,
    this.venueName,
    this.venueType,
    this.venuePhoto,
    this.bio,
    this.userPhotoUrl,
  });

  factory MatchItem.fromJson(Map<String, dynamic> json) {
    final userRaw = json['user'];
    final user = userRaw is Map<String, dynamic>
        ? userRaw
        : (userRaw is Map ? Map<String, dynamic>.from(userRaw) : null);
    final matchId =
        json['match_id'] as String? ?? json['matchId'] as String? ?? '';
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
    final checkinId =
        json['checkin_id'] as String? ?? json['checkinId'] as String?;
    final venueId = json['venue_id'] as String? ?? json['venueId'] as String?;
    final venueRaw = json['venue'];
    final venue = venueRaw is Map<String, dynamic>
        ? venueRaw
        : (venueRaw is Map ? Map<String, dynamic>.from(venueRaw) : null);
    final venueName =
        json['venue_name'] as String? ??
        json['venueName'] as String? ??
        venue?['name'] as String?;
    final venueType =
        json['venue_type'] as String? ??
        json['venueType'] as String? ??
        venue?['type'] as String?;
    final venuePhoto =
        json['venue_photo'] as String? ??
        json['venuePhoto'] as String? ??
        venue?['photo'] as String?;
    final userPhoto =
        json['photo'] as String? ??
        json['photoUrl'] as String? ??
        json['photo_url'] as String? ??
        user?['photo'] as String? ??
        user?['photoUrl'] as String? ??
        user?['photo_url'] as String?;
    final bio =
        (json['bio'] ??
                json['bio_text'] ??
                json['about'] ??
                json['aboutMe'] ??
                user?['bio'] ??
                user?['bio_text'] ??
                user?['about'] ??
                user?['aboutMe'])
            ?.toString()
            .trim();

    return MatchItem(
      matchId: matchId,
      chatId: chatId,
      userId: userId,
      username: username,
      fullName: fullName,
      checkinId: checkinId,
      venueId: venueId,
      venueName: (venueName != null && venueName.trim().isNotEmpty)
          ? venueName.trim()
          : null,
      venueType: (venueType != null && venueType.trim().isNotEmpty)
          ? venueType.trim()
          : null,
      venuePhoto: (venuePhoto != null && venuePhoto.trim().isNotEmpty)
          ? venuePhoto.trim()
          : null,
      bio: (bio != null && bio.isNotEmpty) ? bio : null,
      userPhotoUrl: (userPhoto != null && userPhoto.trim().isNotEmpty)
          ? userPhoto.trim()
          : null,
    );
  }
}
