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
}
