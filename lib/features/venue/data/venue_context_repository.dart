import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

class VenueContextRepository {
  final ApiClient _api = ApiClient();

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

  Future<VenueCheckinStats> getVenueCheckinStats(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.get(
      '/venues/$venueId/checkin-stats',
      headers: {'Authorization': 'Bearer $token'},
    );
    return VenueCheckinStats.fromJson(Map<String, dynamic>.from(data));
  }

  Future<Map<String, dynamic>> followVenue(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.post(
      '/venues/$venueId/follow',
      headers: {'Authorization': 'Bearer $token'},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> unfollowVenue(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final data = await _api.delete(
      '/venues/$venueId/follow',
      headers: {'Authorization': 'Bearer $token'},
    );
    return Map<String, dynamic>.from(data as Map);
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
