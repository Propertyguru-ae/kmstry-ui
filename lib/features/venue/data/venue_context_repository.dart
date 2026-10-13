import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/google_photo_source.dart';

class VenueFollowChange {
  const VenueFollowChange({
    required this.venueId,
    required this.following,
    required this.session,
  });

  final String venueId;
  final bool following;
  final int session;
}

class VenueContextRepository {
  static final followChanges = ValueNotifier<VenueFollowChange?>(null);

  VenueContextRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<GooglePhotoSource> getGooglePhotoSource(String photoUrl) async {
    final response = await _api.get(googlePhotoSourcePath(photoUrl));
    return GooglePhotoSource.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }

  Future<Uri?> getVenueReportUrl(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final response = await _api.get(
      '/reports/venues/${Uri.encodeComponent(venueId)}/destination',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response is Map && response['destination'] == 'KMSTRY') return null;
    final url = response is Map && response['destination'] == 'GOOGLE_MAPS'
        ? safeGooglePhotoLink(response['url'])
        : null;
    if (url == null) {
      throw const FormatException('Invalid venue report destination');
    }
    return url;
  }

  Future<Map<String, dynamic>> getPlaceDetails(String placeId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/places/details?placeId=$placeId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVenueDetails(String placeId) async {
    final response = await _api.get('/venues/details/$placeId');
    return response as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> claimVenueFromPlace(String placeId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.post(
      '/venues/from-place',
      headers: {'Authorization': 'Bearer $token'},
      body: {'googlePlaceId': placeId},
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resolveVenueFromPlace(String placeId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.post(
      '/venues/resolve-from-place',
      headers: {'Authorization': 'Bearer $token'},
      body: {'googlePlaceId': placeId},
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVenueById(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/$venueId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getVenueDetailIdentity(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/$venueId/detail/identity',
      headers: {'Authorization': 'Bearer $token'},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<VenueUpcomingEvent>> getVenueDetailUpcomingEvents(
    String venueId,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/$venueId/detail/upcoming-events',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map(
          (event) =>
              VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(event)),
        )
        .toList(growable: false);
  }

  Future<VenueCheckinStats> getVenueCheckinStats(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/$venueId/checkin-stats',
      headers: {'Authorization': 'Bearer $token'},
    );
    return VenueCheckinStats.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> followVenue(String venueId) =>
      _setFollowing(venueId, true);

  Future<Map<String, dynamic>> unfollowVenue(String venueId) =>
      _setFollowing(venueId, false);

  Future<Map<String, dynamic>> _setFollowing(
    String venueId,
    bool following,
  ) async {
    final uploads = PendingPublicMediaService.instance;
    final session = uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    if (!uploads.isCurrentSession(session)) {
      throw StateError('Venue follow session changed.');
    }
    final path = '/venues/$venueId/follow';
    final headers = {'Authorization': 'Bearer $token'};
    final data = following
        ? await _api.post(path, headers: headers)
        : await _api.delete(path, headers: headers);
    final result = Map<String, dynamic>.from(data as Map);
    if (result['ok'] != true || result['isFollowing'] != following) {
      throw StateError('Venue follow could not be confirmed.');
    }
    // Home may be retained behind another route/tab. Notify only after the
    // authenticated write succeeds, never on an optimistic button change.
    if (uploads.isCurrentSession(session)) {
      followChanges.value = VenueFollowChange(
        venueId: venueId,
        following: following,
        session: session,
      );
    }
    return result;
  }

  Future<List<Venue>> getFollowedVenues() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/following',
      headers: {'Authorization': 'Bearer $token'},
    );
    final rawItems = data is Map
        ? (data['items'] ?? data['data'] ?? data['venues'])
        : data;
    if (rawItems is! List) return const <Venue>[];
    return rawItems
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          map['source'] ??= 'db';
          map['isInDb'] ??= true;
          map['canCheckin'] ??= true;
          map['isFollowing'] ??= true;
          return Venue.fromJson(map);
        })
        .toList(growable: false);
  }

  /// Kullanıcının konumunu backend'e ping'ler (fire-and-forget).
  /// Hata olursa sessizce yutulur.
  Future<void> pingLocation(double lat, double lng) async {
    try {
      final token = await SecureStorage.getAccessToken();
      if (token == null) return;
      await _api.patch(
        '/users/me/location',
        headers: {'Authorization': 'Bearer $token'},
        body: {'lat': lat, 'lng': lng},
      );
    } catch (_) {
      // Fire-and-forget — errors are intentionally ignored
    }
  }
}
