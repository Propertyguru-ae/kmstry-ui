import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'dart:convert';

import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';

class CheckinRepository {
  final ApiClient _api = ApiClient();

  /// 1️⃣ Check-in oluştur (JSON)
  Future<String> createCheckin({
    required String venueId,
    required double latitude,
    required double longitude,
    required String vibe,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final data = await _api.post(
      '/checkins',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'venue_id': venueId,
        'checkin_method': 'gps',
        'latitude': latitude,
        'longitude': longitude,
        'vibe': vibe,
      },
    );

    return data['id'] as String;
  }

  /// 2️⃣ Foto yükle (MULTIPART)
  Future<void> uploadCheckinPhoto({
    required String checkinId,
    required File file,
    required bool isFeatured,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final uri = Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/photos');

    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $token';

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    request.fields['isFeatured'] = isFeatured.toString();

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      throw Exception('Upload failed (${response.statusCode}): $responseBody');
    }
  }

  Future<CheckinProfile> getCheckinProfile(String checkinId) async {
    final token = await SecureStorage.getAccessToken();

    final data = await _api.get(
      '/checkins/$checkinId/profile',
      headers: {'Authorization': 'Bearer $token'},
    );

    return CheckinProfile.fromJson(data);
  }
}
