import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'dart:convert';

import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';

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

  Future<void> uploadCheckinMedia({
    required String checkinId,
    required File file,
    required bool isFeatured,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final uri = Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/media');

    final request = http.MultipartRequest('POST', uri);

    request.headers['Authorization'] = 'Bearer $token';

    // ✅ MIME TYPE FIX
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    request.fields['isFeatured'] = isFeatured.toString();

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      throw Exception(
        'Media upload failed (${response.statusCode}): $responseBody',
      );
    }
  }

  Future<List<dynamic>> getMyCheckinMedia() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    final data = await _api.get(
      '/users/me/checkin-media',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (data is! List) return [];

    return data;
  }

  /// Logged-in user's check-in photos (for own profile moments list).
  /// Tries GET /users/me/checkin-photos; response: list of { url } or list of url strings.
  Future<List<String>> getMyCheckinPhotos() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    try {
      final data = await _api.get(
        '/users/me/checkin-photos',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (data is! List) return [];
      final list = data as List;
      return list
          .map((e) {
            if (e is String) return e;
            if (e is Map && e['url'] != null) return e['url'] as String;
            return null;
          })
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
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

  Future<void> setFeaturedPhoto(String photoId) async {
    final token = await SecureStorage.getAccessToken();

    await _api.patch(
      '/checkins/photos/$photoId/feature',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> updateVibe({
    required String checkinId,
    required String vibe,
  }) async {
    final token = await SecureStorage.getAccessToken();

    await _api.patch(
      '/checkins/$checkinId/vibe',
      headers: {'Authorization': 'Bearer $token'},
      body: {"vibe": vibe},
    );
  }

  Future<void> deletePhoto(String photoId) async {
    final token = await SecureStorage.getAccessToken();

    await _api.delete(
      '/checkins/photos/$photoId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> sendFeedAction({
    required String targetUserId,
    required String venueId,
    // required String checkinId,
    required String action,
  }) async {
    final token = await SecureStorage.getAccessToken();

    await _api.post(
      '/feed/actions',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'target_user_id': targetUserId,
        'venue_id': venueId,
        //'checkin_id': checkinId,
        'action': action,
      },
    );
  }
}
