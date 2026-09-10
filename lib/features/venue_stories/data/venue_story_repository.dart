import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_story_model.dart';

class VenueStoryRepository {
  final ApiClient _api = ApiClient();

  /// Venue story'leri değiştiğinde (paylaşma/silme) artan sayaç. Home'daki story
  /// kartı bunu dinleyip kendini tazeler.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void _notifyChanged() => changes.value++;

  Future<VenueStoryItem> createVenueStory({
    required String venueId,
    required File file,
    required String mediaType,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/venue-stories');

    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );
    request.fields['media_type'] = mediaType;

    final streamed = await sendMultipartRequest(request);
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      throw Exception(
        'Venue story upload failed (${streamed.statusCode}): $body',
      );
    }

    final item = VenueStoryItem.fromJson(
      jsonDecode(body) as Map<String, dynamic>,
    );
    _notifyChanged();
    return item;
  }

  Future<List<VenueStoryItem>> getVenueStories(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/venue-stories',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => VenueStoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordView(String venueId, String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.post(
      '/venues/$venueId/venue-stories/$storyId/view',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  Future<void> deleteStory(String venueId, String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/venue-stories/$storyId',
      headers: {'Authorization': 'Bearer $token'},
    );
    _notifyChanged();
  }

  Future<List<Map<String, dynamic>>> getViewers(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/venue-stories/viewers',
      headers: {'Authorization': 'Bearer $token'},
    );
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }
}
