import '../network/api_client.dart';
import '../storage/secure_storage.dart';
import 'media_reference.dart';

typedef MediaRefreshTransport =
    Future<Map<String, dynamic>> Function(String path);

class SignedMediaResolver {
  SignedMediaResolver({MediaRefreshTransport? transport})
    : _transport = transport ?? _defaultTransport;

  static final SignedMediaResolver instance = SignedMediaResolver();
  static final ApiClient _api = ApiClient();

  final MediaRefreshTransport _transport;
  final Map<String, Future<MediaReference?>> _inFlight = {};
  final Map<String, MediaReference> _cache = {};

  MediaReference current(MediaReference reference) {
    final cached = _cache[reference.mediaId];
    if (cached == null) return reference;
    if (cached.expiresAt?.isBefore(DateTime.now()) == true) {
      _cache.remove(reference.mediaId);
      return reference;
    }
    return cached;
  }

  /// One call represents the single retry allowed by the image/file consumer.
  /// Concurrent failures for the same media ID share one network request.
  Future<MediaReference?> refreshOnce(MediaReference reference) {
    if (!reference.canRefresh) return Future.value(null);
    return _inFlight.putIfAbsent(reference.mediaId, () async {
      try {
        final json = await _transport(reference.refreshPath!);
        final refreshed = MediaReference.fromJson(
          json,
          fallbackId: reference.mediaId,
          legacyUrlKeys: const ['url'],
        );
        if (refreshed.url.isEmpty) return null;
        _cache[reference.mediaId] = refreshed;
        return refreshed;
      } catch (_) {
        return null;
      } finally {
        _inFlight.remove(reference.mediaId);
      }
    });
  }

  void evict(String mediaId) => _cache.remove(mediaId);

  static Future<Map<String, dynamic>> _defaultTransport(String path) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) return const {};
    final response = await _api.get(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );
    return response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
  }
}
