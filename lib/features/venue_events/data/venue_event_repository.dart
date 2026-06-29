import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

class VenueEventRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, dynamic>> createEvent({
    required String venueId,
    required String title,
    String? description,
    required DateTime startAt,
    required DateTime endAt,
    int? priceAed,
    String currency = 'TRY',
    Map<String, dynamic>? recurrence,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.post(
      '/venues/$venueId/events',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'title': title,
        if (description != null && description.isNotEmpty) 'description': description,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        if (priceAed != null) 'priceAed': priceAed,
        'currency': currency,
        if (recurrence != null) 'recurrence': recurrence,
      },
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> uploadPhoto({
    required String venueId,
    required String eventId,
    required File file,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/events/$eventId/photos');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();
    if (streamed.statusCode >= 400) {
      throw Exception('Photo upload failed (${streamed.statusCode}): $body');
    }
  }

  Future<void> updateEvent({
    required String venueId,
    required String eventId,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    int? priceAed,
    bool clearPrice = false,
    String? currency,
    String? editScope, // 'this' | 'thisAndFollowing' | 'all'
    Map<String, dynamic>? recurrence,
  }) async {
    final token = await SecureStorage.getAccessToken();
    await _api.patch(
      '/venues/$venueId/events/$eventId',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (startAt != null) 'startAt': startAt.toUtc().toIso8601String(),
        if (endAt != null) 'endAt': endAt.toUtc().toIso8601String(),
        if (clearPrice) 'priceAed': null else if (priceAed != null) 'priceAed': priceAed,
        if (currency != null) 'currency': currency,
        if (editScope != null) 'editScope': editScope,
        if (recurrence != null) 'recurrence': recurrence,
      },
    );
  }

  Future<void> deleteRecurringSeries({
    required String venueId,
    required String ruleId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/recurring-rules/$ruleId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> removePhoto({
    required String venueId,
    required String eventId,
    required String photoUrl,
  }) async {
    final token = await SecureStorage.getAccessToken();
    // DELETE with body — use patch endpoint workaround via http directly
    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/events/$eventId/photos');
    final req = http.Request('DELETE', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = '{"photoUrl":"${photoUrl.replaceAll('"', '\\"')}"}';
    final resp = await req.send();
    if (resp.statusCode >= 400) {
      throw Exception('Remove photo failed (${resp.statusCode})');
    }
  }

  Future<void> deleteEvent({required String venueId, required String eventId}) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/events/$eventId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
