import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_owner_stats_model.dart';

class VenueOwnerRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<VenueOwnerStatsResponse> getOwnerStats(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/owner-stats', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    return VenueOwnerStatsResponse.fromJson(map);
  }

  Future<VenueOwnerStatsVenue> updateVenue(
    String venueId, {
    String? name,
    String? description,
    String? photo,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (photo != null) body['photo'] = photo;

    final data = await _api.patch(
      '/venues/$venueId',
      body: body,
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    return VenueOwnerStatsVenue.fromJson(map);
  }
}
