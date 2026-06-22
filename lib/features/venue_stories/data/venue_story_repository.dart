import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_story_model.dart';

class VenueStoryRepository {
  final ApiClient _api = ApiClient();

  Future<VenueStoryItem> createVenueStory({
    required String venueId,
    required File file,
    required String mediaType,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/$venueId/venue-stories',
    );

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

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

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      throw Exception('Venue story upload failed (${streamed.statusCode}): $body');
    }

    return VenueStoryItem.fromJson(jsonDecode(body) as Map<String, dynamic>);
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
}
