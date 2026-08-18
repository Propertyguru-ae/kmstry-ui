class VenueGalleryItem {
  final String id;
  final String url;
  final String? thumbnailUrl;
  final String mediaType; // 'photo' | 'video'
  final DateTime? createdAt;

  const VenueGalleryItem({
    required this.id,
    required this.url,
    this.thumbnailUrl,
    required this.mediaType,
    this.createdAt,
  });

  bool get isVideo => mediaType == 'video';

  factory VenueGalleryItem.fromJson(Map<String, dynamic> json) {
    return VenueGalleryItem(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      thumbnailUrl: (json['thumbnailUrl'] ?? json['thumbnail_url'])?.toString(),
      mediaType: (json['mediaType'] ?? json['media_type'])?.toString() ?? 'photo',
      createdAt: DateTime.tryParse((json['createdAt'] ?? json['created_at'])?.toString() ?? ''),
    );
  }
}
