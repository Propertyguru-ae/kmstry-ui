import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import '../../../core/media/media_reference.dart';

class StoryUser {
  final String id;
  final String? username;
  final String? fullName;
  final String? photo;
  final MediaReference? photoReference;

  const StoryUser({
    required this.id,
    this.username,
    this.fullName,
    this.photo,
    this.photoReference,
  });

  factory StoryUser.fromJson(Map<String, dynamic> j) {
    final id = j['id']?.toString() ?? '';
    final reference = MediaReference.profilePhoto(j, userId: id);
    return StoryUser(
      id: id,
      username: j['username'] as String?,
      fullName: j['full_name'] as String?,
      photo: reference.url.isEmpty ? null : reference.url,
      photoReference: reference.url.isEmpty ? null : reference,
    );
  }

  String get displayName => fullName ?? username ?? 'User';
}

class StoryItem {
  final String id;
  final String mediaUrl;
  final String mediaType; // 'photo' | 'video'
  final String? thumbnailUrl;
  final int? durationSecs;
  final DateTime expiresAt;
  final DateTime createdAt;
  final StoryUser? user;
  final MediaReference? mediaReference;

  const StoryItem({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.durationSecs,
    required this.expiresAt,
    required this.createdAt,
    this.user,
    this.mediaReference,
    this.checkinFeaturedPhotoUrl,
    this.venueId,
    this.venueName,
    this.viewCount = 0,
    this.viewedByMe = false,
    this.isUploadingPlaceholder = false,
    this.textOverlay,
    this.isVenueStory = false,
  });

  final String? checkinFeaturedPhotoUrl;
  final String? venueId;
  final String? venueName;
  final int viewCount;
  final bool viewedByMe;

  /// true → bu bir venue hesabının kendi story'si (VenueStory). Viewer,
  /// izlenmeyi venue endpoint'ine kaydeder. false → kişisel story.
  final bool isVenueStory;

  /// Medya üzerine eklenen metin overlay'i (client render eder).
  final MediaTextOverlay? textOverlay;

  /// Henüz yüklenmekte olan story için viewer'da "Loading…" gösteren placeholder.
  final bool isUploadingPlaceholder;

  bool get isVideo => mediaType == 'video';

  /// Yüklenmekte olan story için geçici placeholder öğesi.
  factory StoryItem.uploadingPlaceholder() => StoryItem(
    id: '__uploading__',
    mediaUrl: '',
    mediaType: 'photo',
    expiresAt: DateTime.now().add(const Duration(hours: 24)),
    createdAt: DateTime.now(),
    isUploadingPlaceholder: true,
  );

  factory StoryItem.fromJson(Map<String, dynamic> j) {
    String? featuredPhotoUrl;
    final checkin = j['checkin'] as Map<String, dynamic>?;
    if (checkin != null) {
      final media = checkin['media'] as List?;
      if (media != null && media.isNotEmpty) {
        final m = media.first as Map<String, dynamic>;
        featuredPhotoUrl = m['thumbnail_url'] as String? ?? m['url'] as String?;
      }
    }
    final venueMap = j['venue'] as Map<String, dynamic>?;
    final id = j['id'] as String;
    final mediaReference = MediaReference.fromJson(
      j,
      fallbackId: id,
      legacyUrlKeys: const ['media_url', 'mediaUrl'],
    );
    return StoryItem(
      id: id,
      mediaUrl: mediaReference.url,
      mediaReference: mediaReference,
      mediaType: j['media_type'] as String,
      thumbnailUrl: j['thumbnail_url'] as String?,
      durationSecs: j['duration_secs'] as int?,
      expiresAt: DateTime.parse(j['expires_at'] as String),
      createdAt: DateTime.parse(j['created_at'] as String),
      user: j['user'] != null
          ? StoryUser.fromJson(j['user'] as Map<String, dynamic>)
          : null,
      checkinFeaturedPhotoUrl: featuredPhotoUrl,
      venueId: venueMap?['id'] as String?,
      venueName: venueMap?['name'] as String?,
      viewedByMe: (j['viewed_by_me'] as bool?) ?? false,
      textOverlay: MediaTextOverlay.fromJson(j['text_overlay']),
      isVenueStory: (j['is_venue_story'] as bool?) ?? false,
    );
  }
}

/// One bubble in the story tray — a user with their ordered stories.
class StoryGroup {
  final StoryUser user;
  final List<StoryItem> stories;
  final String? featuredPhotoUrl;
  final bool isCurrentUserOwner;

  /// When set, this bubble represents a followed venue's stories (rendered with
  /// a venue badge + this label) instead of a person. Null for friend stories.
  final String? venueLabel;

  const StoryGroup({
    required this.user,
    required this.stories,
    this.featuredPhotoUrl,
    this.isCurrentUserOwner = false,
    this.venueLabel,
  });

  /// Bubble'da gösterilecek URL: featured checkin fotosu → profil fotosu
  String? get bubbleImageUrl {
    if (featuredPhotoUrl != null && featuredPhotoUrl!.isNotEmpty) {
      return featuredPhotoUrl;
    }
    if (stories.isNotEmpty) {
      final featured = stories.first.checkinFeaturedPhotoUrl;
      if (featured != null && featured.isNotEmpty) return featured;
    }
    return user.photo;
  }

  MediaReference? get bubbleMediaReference {
    if (venueLabel != null || bubbleImageUrl != user.photo) return null;
    return user.photoReference;
  }

  factory StoryGroup.fromJson(Map<String, dynamic> j) => StoryGroup(
    user: StoryUser.fromJson(j['user'] as Map<String, dynamic>),
    featuredPhotoUrl: j['featured_photo_url'] as String?,
    venueLabel: j['venue_label'] as String?,
    stories: (j['stories'] as List)
        .map((s) => StoryItem.fromJson(s as Map<String, dynamic>))
        .toList(),
  );
}
