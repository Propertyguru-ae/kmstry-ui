import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'media_network_url.dart';

/// In-memory invalidation, not a second source of moderation decisions.
/// The proxy checks the current database decision on every revised URL.
/// Neither Google image bytes nor references are persisted here.
class GooglePhotoUpdates extends ChangeNotifier {
  static final instance = GooglePhotoUpdates();

  final Map<String, int> _revisions = {};
  int _epoch = 0;
  int _sequence = 0;
  String? affectedPlaceId;

  void handleUpdate(Map<String, dynamic> payload) {
    final placeId = payload['placeId'];
    if (placeId is! String ||
        !RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(placeId)) {
      return;
    }
    if (_revisions.length >= 512 && !_revisions.containsKey(placeId)) {
      _revisions.clear();
      _epoch++;
      affectedPlaceId = null;
    } else {
      affectedPlaceId = placeId;
    }
    _revisions[placeId] = ++_sequence;
    notifyListeners();
  }

  /// A socket reconnect or foreground return can have missed admin decisions.
  /// No polling or reload of unrelated page data. Do not debounce reconnects:
  /// a decision may have happened between a resume request and the new socket.
  void revalidate() {
    _epoch++;
    _revisions.clear();
    affectedPlaceId = null;
    notifyListeners();
  }

  String revisionFor(String url) {
    if (!isGooglePlacePhotoProxyUrl(url)) return '';
    final revision = _revisions[placeIdFor(url)] ?? 0;
    return _epoch == 0 && revision == 0 ? '' : '$_epoch-$revision';
  }

  String networkUrl(String url) {
    final resolved = resolveMediaNetworkUrl(url);
    final revision = revisionFor(resolved);
    if (revision.isEmpty) return resolved;
    final uri = Uri.parse(resolved);
    return uri
        .replace(
          queryParameters: {
            ...uri.queryParameters,
            '_kmstryPhotoRevision': revision,
          },
        )
        .toString();
  }

  /// Read identity only, never trust the decoded payload for access decisions.
  /// Its signature is still verified by the backend when fetching the photo.
  static String? placeIdFor(String url) {
    if (!isGooglePlacePhotoProxyUrl(url)) return null;
    try {
      final token = Uri.parse(url).pathSegments.last;
      final encoded = token.split('.').first;
      final data = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(encoded))),
      );
      if (data is! Map) return null;
      final reference = data['reference'];
      final candidate =
          data['placeId'] ??
          (data['kind'] == 'place'
              ? reference
              : data['kind'] == 'new' && reference is String
              ? RegExp(
                  r'^places/([A-Za-z0-9_-]+)/photos/',
                ).firstMatch(reference)?.group(1)
              : null);
      return candidate is String &&
              RegExp(r'^[A-Za-z0-9_-]{1,256}$').hasMatch(candidate)
          ? candidate
          : null;
    } catch (_) {
      return null;
    }
  }
}
