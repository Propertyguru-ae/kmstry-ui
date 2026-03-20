import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

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
}
