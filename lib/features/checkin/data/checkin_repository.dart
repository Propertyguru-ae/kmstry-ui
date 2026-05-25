import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';

import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
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
    List<String>? whatBringsYou,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final selectedReasons = (whatBringsYou ?? [])
        .where((item) => item.trim().isNotEmpty)
        .map((item) => item.trim())
        .toList();

    final baseBody = <String, dynamic>{
      'venue_id': venueId,
      'checkin_method': 'gps',
      'latitude': latitude,
      'longitude': longitude,
      'vibe': vibe,
    };

    final enrichedBody = <String, dynamic>{
      ...baseBody,
      if (selectedReasons.isNotEmpty) 'what_brings_to_kmstry': selectedReasons,
    };

    Map<String, dynamic> data;
    try {
      data = await _api.post(
        '/checkins',
        headers: {'Authorization': 'Bearer $token'},
        body: enrichedBody,
      );
    } on ApiException catch (e) {
      // Safe fallback for older backends that don't accept this new field yet.
      if (selectedReasons.isNotEmpty && _isUnknownWhatBringsFieldError(e)) {
        data = await _api.post(
          '/checkins',
          headers: {'Authorization': 'Bearer $token'},
          body: baseBody,
        );
      } else {
        rethrow;
      }
    }

    return data['id'] as String;
  }

  bool _isUnknownWhatBringsFieldError(ApiException error) {
    if (error.statusCode != 400) return false;
    final message = error.data.toString().toLowerCase();
    return message.contains('what_brings_you') ||
        message.contains('unknown') ||
        message.contains('not allowed') ||
        message.contains('additional properties');
  }

  Future<List<String>> getWhatBringsOptions() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    final data = await _api.get(
      '/checkins/options/what-brings',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (data is Map && data['options'] is List) {
      return List<String>.from(data['options']);
    }

    return [];
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
      final list = data;
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
    String? venueId,
    // required String checkinId,
    required String action,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final body = <String, dynamic>{
      'target_user_id': targetUserId,
      //'checkin_id': checkinId,
      'action': action,
    };
    if (venueId != null && venueId.isNotEmpty) {
      body['venue_id'] = venueId;
    }

    await _api.post(
      '/feed/actions',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );
  }

  Future<void> blockUser(String targetUserId) async {
    final token = await SecureStorage.getAccessToken();

    await _api.post(
      '/blocks',
      headers: {'Authorization': 'Bearer $token'},
      body: {'blocked_id': targetUserId},
    );
  }

  Future<void> reportUser({
    required String targetUserId,
    required String reason,
    String? details,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      'reported_user_id': targetUserId,
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
    };

    await _api.post(
      '/reports/users',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );
  }

  Future<void> unblockUser(String targetUserId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.delete(
      '/blocks/$targetUserId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Set<String>> getBlockedUserIds() async {
    final token = await SecureStorage.getAccessToken();
    dynamic data;
    try {
      data = await _api.get(
        '/blocks/me',
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      data = await _api.get(
        '/blocks/me',
        headers: {'Authorization': 'Bearer $token'},
      );
    }

    final list = _extractList(data);
    final result = <String>{};
    for (final raw in list) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final user = json['user'] is Map
          ? Map<String, dynamic>.from(json['user'] as Map)
          : null;
      final id =
          json['user_id'] as String? ??
          json['blocked_id'] as String? ??
          json['blocked_user_id'] as String? ??
          json['target_user_id'] as String? ??
          json['userId'] as String? ??
          user?['id'] as String?;
      if (id != null && id.isNotEmpty) result.add(id);
    }
    return result;
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final nested =
          data['items'] ??
          data['data'] ??
          data['blocks'] ??
          data['blocked'] ??
          data['results'];
      if (nested is List) return nested;
    }
    return const [];
  }

  /// Kullanıcının aktif check-in'ini manuel olarak kapatır.
  /// Backend: DELETE /checkins/:id
  Future<void> checkout(String checkinId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.delete(
      '/checkins/$checkinId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
