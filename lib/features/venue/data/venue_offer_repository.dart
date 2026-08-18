import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_offer_model.dart';

class VenueOfferRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<VenueOfferModel>> getOffers(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/offers', headers: headers);
    return (data as List<dynamic>)
        .map((e) => VenueOfferModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<VenueOfferModel>> getActiveOffers(String venueId) async {
    final data = await _api.get('/venues/$venueId/offers/public');
    return (data as List<dynamic>)
        .map((e) => VenueOfferModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<VenueOfferModel> create(String venueId, Map<String, dynamic> body) async {
    final headers = await _authHeaders();
    final data = await _api.post('/venues/$venueId/offers', headers: headers, body: body);
    return VenueOfferModel.fromJson(data as Map<String, dynamic>);
  }

  Future<VenueOfferModel> update(
    String venueId,
    String offerId,
    Map<String, dynamic> updates,
  ) async {
    final headers = await _authHeaders();
    final data = await _api.patch(
      '/venues/$venueId/offers/$offerId',
      headers: headers,
      body: updates,
    );
    return VenueOfferModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String venueId, String offerId) async {
    final headers = await _authHeaders();
    await _api.delete('/venues/$venueId/offers/$offerId', headers: headers);
  }

  Future<OfferRedemptionModel> redeem(String offerId) async {
    final headers = await _authHeaders();
    final data = await _api.post('/offers/$offerId/redeem', headers: headers, body: {});
    return OfferRedemptionModel.fromJson(data as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> verifyCode(String code, String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.post(
      '/offers/verify/$code',
      headers: headers,
      body: {'venue_id': venueId},
    );
    return data as Map<String, dynamic>;
  }
}
