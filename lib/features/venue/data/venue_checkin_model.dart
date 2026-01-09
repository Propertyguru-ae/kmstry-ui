class VenueCheckin {
  final String id;
  final String userId;
  final String? fullName;
  final String userPhoto;
  final String? featuredPhoto;

  VenueCheckin({
    required this.id,
    required this.userId,
    this.fullName,
    required this.userPhoto,
    this.featuredPhoto,
  });

  factory VenueCheckin.fromJson(Map<String, dynamic> json) {
    final user = json['user'] ?? {};
    final photos = json['photos'] as List? ?? [];

    return VenueCheckin(
      id: json['id'] as String,
      userId: user['id'] as String,
      fullName: user['full_name'], // nullable OK
      userPhoto:
          user['photo'] ?? 'https://via.placeholder.com/300x300.png?text=User',
      featuredPhoto: photos.isNotEmpty ? photos.first['url'] : null,
    );
  }
}

extension VenueCheckinX on VenueCheckin {
  /// Grid + Hero için tek foto kaynağı:
  /// featured varsa onu, yoksa userPhoto
  String get displayPhoto => featuredPhoto ?? userPhoto;
}
