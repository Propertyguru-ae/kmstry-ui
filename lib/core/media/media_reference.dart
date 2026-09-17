class MediaReference {
  const MediaReference({
    required this.mediaId,
    required this.url,
    this.refreshPath,
    this.expiresAt,
  });

  final String mediaId;
  final String url;
  final String? refreshPath;
  final DateTime? expiresAt;

  bool get canRefresh =>
      mediaId.isNotEmpty && refreshPath != null && refreshPath!.isNotEmpty;

  factory MediaReference.fromJson(
    Map<String, dynamic> json, {
    required String fallbackId,
    required List<String> legacyUrlKeys,
    String idKey = 'media_id',
    String temporaryUrlKey = 'temporary_url',
    String refreshPathKey = 'refresh_path',
    String expiresAtKey = 'url_expires_at',
  }) {
    String? readString(Iterable<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    return MediaReference(
      mediaId: readString([idKey, 'mediaId']) ?? fallbackId,
      url:
          readString([temporaryUrlKey, 'temporaryUrl', ...legacyUrlKeys]) ?? '',
      refreshPath: readString([refreshPathKey, 'refreshPath']),
      expiresAt: DateTime.tryParse(
        readString([expiresAtKey, 'urlExpiresAt']) ?? '',
      ),
    );
  }

  /// Profile photos use the user id as their stable cache identity. The
  /// backend rotates the signed URL, while this reference keeps cache entries
  /// stable and gives [CachedImage] exactly one authenticated refresh path.
  factory MediaReference.profilePhoto(
    Map<String, dynamic> json, {
    String? userId,
  }) {
    String? readString(Iterable<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final resolvedUserId =
        userId ?? readString(const ['id', 'userId', 'user_id']);
    final mediaId =
        readString(const ['photo_media_id', 'photoMediaId']) ??
        (resolvedUserId == null ? '' : '$resolvedUserId:profile');
    final refreshPath =
        readString(const ['photo_refresh_path', 'photoRefreshPath']) ??
        (resolvedUserId == null ? null : '/users/$resolvedUserId/photo-url');

    return MediaReference(
      mediaId: mediaId,
      url:
          readString(const [
            'photo_temporary_url',
            'photoTemporaryUrl',
            'photo',
            'profilePhoto',
            'profile_photo',
            'avatarUrl',
            'avatar_url',
          ]) ??
          '',
      refreshPath: refreshPath,
      expiresAt: DateTime.tryParse(
        readString(const ['photo_url_expires_at', 'photoUrlExpiresAt']) ?? '',
      ),
    );
  }

  /// Venue cover photos use the venue id as a stable cache identity. Google
  /// Places-only results deliberately receive no refresh path because their
  /// URLs are owned by Google rather than KMSTRY storage.
  factory MediaReference.venuePhoto(
    Map<String, dynamic> json, {
    required String venueId,
    required bool allowRefresh,
  }) {
    String? readString(Iterable<String> keys) {
      for (final key in keys) {
        final value = json[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
      return null;
    }

    final mediaId =
        readString(const ['photo_media_id', 'photoMediaId']) ??
        (venueId.isEmpty ? '' : '$venueId:venue-photo');
    final refreshPath =
        readString(const ['photo_refresh_path', 'photoRefreshPath']) ??
        (allowRefresh && venueId.isNotEmpty
            ? '/venues/$venueId/photo-url'
            : null);

    return MediaReference(
      mediaId: mediaId,
      url:
          readString(const [
            'photo_temporary_url',
            'photoTemporaryUrl',
            'photo',
            'photoUrl',
            'photo_url',
          ]) ??
          '',
      refreshPath: refreshPath,
      expiresAt: DateTime.tryParse(
        readString(const ['photo_url_expires_at', 'photoUrlExpiresAt']) ?? '',
      ),
    );
  }
}
