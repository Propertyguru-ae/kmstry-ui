class VenueFollower {
  final String userId;
  final String fullName;
  final String? username;
  final String? photo;
  final String? bio;
  final DateTime? followedAt;

  const VenueFollower({
    required this.userId,
    required this.fullName,
    this.username,
    this.photo,
    this.bio,
    this.followedAt,
  });

  factory VenueFollower.fromJson(Map<String, dynamic> json) {
    final followedRaw = json['followedAt']?.toString();
    return VenueFollower(
      userId: json['userId']?.toString() ?? '',
      fullName: json['fullName']?.toString() ?? '',
      username: json['username']?.toString(),
      photo: json['photo']?.toString(),
      bio: json['bio']?.toString(),
      followedAt: followedRaw != null ? DateTime.tryParse(followedRaw) : null,
    );
  }
}
