import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/checkin_photo_model.dart';
import 'package:kmstry_frontend/features/venue/data/ping_response.dart';
import 'venue_checkin_model.dart';

class VenueCheckinRepository {
  Future<List<VenueCheckin>> getWhoIsHere(String venueId) async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth');
    }
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/venues/$venueId/checkins'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${accessToken}',
      },
    );

    if (res.statusCode >= 400) {
      throw Exception('Failed to load venue checkins');
    }

    final List data = jsonDecode(res.body);
    return data.map((e) => VenueCheckin.fromJson(e)).toList();
  }

  Future<List<CheckinPhoto>> getProfilePhotos(String checkinId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/profile-photos'),
      headers: {'Content-Type': 'application/json'},
    );

    if (res.statusCode >= 400) {
      throw Exception('Failed to load profile photos');
    }

    final List data = jsonDecode(res.body) as List;
    return data.map((e) => CheckinPhoto.fromJson(e)).toList();
  }

  Future<PingResponse> pingCheckin({
    required String checkinId,
    required double latitude,
    required double longitude,
  }) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/ping'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    if (res.statusCode >= 400) {
      throw Exception('Failed to ping checkin');
    }

    return PingResponse.fromJson(jsonDecode(res.body));
  }
}
