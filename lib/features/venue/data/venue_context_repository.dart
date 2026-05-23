import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';

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
    return response.data;
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
