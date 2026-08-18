import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'external_partnership_model.dart';

class ExternalPartnershipRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<ExternalPartnershipModel>> getPartnerships(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/partnerships', headers: headers);
    return (data as List<dynamic>)
        .map((e) => ExternalPartnershipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<ExternalPartnershipModel>> getActivePartnerships(String venueId) async {
    final data = await _api.get('/venues/$venueId/partnerships/public');
    return (data as List<dynamic>)
        .map((e) => ExternalPartnershipModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<ExternalPartnershipModel> create(
    String venueId, {
    required String platform,
    String? platformLabel,
    required String offerType,
    required String offerLabel,
    String? externalUrl,
    String? proofImageUrl,
    DateTime? validUntil,
  }) async {
    final headers = await _authHeaders();
    final body = {
      'platform': platform,
      if (platformLabel != null) 'platform_label': platformLabel,
      'offer_type': offerType,
      'offer_label': offerLabel,
      if (externalUrl != null) 'external_url': externalUrl,
      if (proofImageUrl != null) 'proof_image_url': proofImageUrl,
      if (validUntil != null) 'valid_until': validUntil.toIso8601String(),
    };
    final data = await _api.post('/venues/$venueId/partnerships', headers: headers, body: body);
    return ExternalPartnershipModel.fromJson(data as Map<String, dynamic>);
  }

  Future<ExternalPartnershipModel> update(
    String venueId,
    String partnershipId,
    Map<String, dynamic> updates,
  ) async {
    final headers = await _authHeaders();
    final data = await _api.patch(
      '/venues/$venueId/partnerships/$partnershipId',
      headers: headers,
      body: updates,
    );
    return ExternalPartnershipModel.fromJson(data as Map<String, dynamic>);
  }

  Future<void> delete(String venueId, String partnershipId) async {
    final headers = await _authHeaders();
    await _api.delete('/venues/$venueId/partnerships/$partnershipId', headers: headers);
  }

  Future<List<ExternalPartnershipModel>> setEventPartnerships(
    String venueId,
    String eventId,
    List<String> partnershipIds,
  ) async {
    final headers = await _authHeaders();
    final data = await _api.post(
      '/venues/$venueId/events/$eventId/partnerships',
      headers: headers,
      body: {'partnershipIds': partnershipIds},
    );
    return (data as List<dynamic>)
        .map((e) => ExternalPartnershipModel.fromJson(
              (e as Map<String, dynamic>)['partnership'] as Map<String, dynamic>,
            ))
        .toList();
  }
}
