class CheckinPhoto {
  final String id;
  final String url;
  final bool isFeatured;

  CheckinPhoto({
    required this.id,
    required this.url,
    required this.isFeatured,
  });

  factory CheckinPhoto.fromJson(Map<String, dynamic> json) {
    return CheckinPhoto(
      id: json['id'] as String,
      url: json['url'] as String,
      isFeatured: (json['isFeatured'] ?? false) as bool,
    );
  }
}
