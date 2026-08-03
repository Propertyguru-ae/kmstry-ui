class ActiveCheckin {
  final String id;
  final String venueId;
  final String? venueName;
  final String? venuePhoto;
  final DateTime? expiresAt;

  /// Kullanıcının profil avatarı (varsa).
  final String? userPhoto;

  /// Check-in sırasında seçilen featured foto (avatar yoksa gösterilir).
  final String? featuredPhoto;

  ActiveCheckin({
    required this.id,
    required this.venueId,
    this.venueName,
    this.venuePhoto,
    this.expiresAt,
    this.userPhoto,
    this.featuredPhoto,
  });

  factory ActiveCheckin.fromJson(Map<String, dynamic> json) {
    // Handle both snake_case and camelCase field names
    final venueRaw = json['venue'];
    final venue = venueRaw is Map ? venueRaw : null;
    final venueId = json['venue_id'] as String? ??
                    json['venueId'] as String? ??
                    (venue != null ? venue['id'] as String? : null);

    if (venueId == null) {
      throw Exception('ActiveCheckin missing venue_id field');
    }

    String? asString(dynamic v) =>
        (v is String && v.trim().isNotEmpty) ? v : null;

    return ActiveCheckin(
      id: json['id'] as String,
      venueId: venueId,
      venueName: venue != null ? venue['name'] as String? : null,
      venuePhoto: venue != null ? venue['photo'] as String? : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : json['expiresAt'] != null
              ? DateTime.parse(json['expiresAt'] as String)
              : null,
      userPhoto: asString(json['userPhoto'] ?? json['user_photo']),
      featuredPhoto: asString(json['featuredPhoto'] ?? json['featured_photo']),
    );
  }

  bool get isActive {
    if (expiresAt == null) return true;
    return DateTime.now().isBefore(expiresAt!);
  }
}
