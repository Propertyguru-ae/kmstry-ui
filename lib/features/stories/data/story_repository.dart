import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'story_model.dart';

class StoryRepository {
  final ApiClient _api = ApiClient();

  /// Upload a photo or video story for the given checkin.
  Future<StoryItem> createStory({
    required String checkinId,
    required File file,
    required String mediaType, // 'photo' | 'video'
    int? durationSecs,
    String? textOverlayJson,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final uri =
        Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/stories');

    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType =
        lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');

    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    request.fields['media_type'] = mediaType;
    if (durationSecs != null) {
      request.fields['duration_secs'] = durationSecs.toString();
    }
    if (textOverlayJson != null && textOverlayJson.isNotEmpty) {
      request.fields['textOverlay'] = textOverlayJson;
    }

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode >= 400) {
      throw Exception('Story upload failed (${streamed.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return StoryItem.fromJson(json);
  }

  /// Returns story groups for the venue (other users).
  Future<List<StoryGroup>> getVenueStories(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/stories',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => StoryGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns the current user's own active stories.
  Future<List<StoryItem>> getMyStories() async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/stories/me',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => StoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Home feed story row: matched friends + followed venues' stories.
  Future<List<StoryGroup>> getHomeStories() async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/stories/home',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => StoryGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Returns story groups from matched friends (all venues).
  Future<List<StoryGroup>> getFriendsStories() async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/stories/friends',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => StoryGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record that the current user viewed a story.
  Future<void> recordView(String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.post(
      '/stories/$storyId/view',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  /// Kullanıcının kendi story'sini siler (DB + Spaces dosyaları backend'de).
  Future<void> deleteStory(String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/stories/$storyId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
