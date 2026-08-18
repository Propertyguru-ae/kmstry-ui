import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_owner_stats_model.dart';
import 'venue_analytics_model.dart';
import 'venue_follower_model.dart';

class VenueOwnerRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<VenueOwnerStatsResponse> getOwnerStats(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get(
      '/venues/$venueId/owner-stats',
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    return VenueOwnerStatsResponse.fromJson(map);
  }

  /// Venue'yu takip eden kullanıcılar. [sort]: 'latest' | 'earliest'.
  Future<List<VenueFollower>> getFollowers(
    String venueId, {
    String sort = 'latest',
  }) async {
    final headers = await _authHeaders();
    final data = await _api.get(
      '/venues/$venueId/followers?sort=$sort',
      headers: headers,
    );
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .whereType<Map>()
        .map((e) => VenueFollower.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Venue-account push notification preferences for this membership.
  /// Returns { team: bool, events: bool }.
  Future<Map<String, bool>> getNotificationPrefs(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get(
      '/venues/$venueId/notification-prefs',
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    return {'team': map['team'] != false, 'events': map['events'] != false};
  }

  Future<void> setNotificationPrefs(
    String venueId, {
    bool? team,
    bool? events,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (team != null) body['team'] = team;
    if (events != null) body['events'] = events;
    await _api.patch(
      '/venues/$venueId/notification-prefs',
      headers: headers,
      body: body,
    );
  }

  /// range: '7d' | '30d' | '90d'. from/to verilirse (YYYY-MM-DD) özel aralık.
  Future<VenueAnalytics> getAnalytics(
    String venueId, {
    String range = '7d',
    String? from,
    String? to,
  }) async {
    final headers = await _authHeaders();
    final q = (from != null && to != null)
        ? 'from=$from&to=$to'
        : 'range=$range';
    final data = await _api.get(
      '/venues/$venueId/analytics?$q',
      headers: headers,
    );
    return VenueAnalytics.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<WeeklyReport>> getWeeklyReports(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/reports', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    return (map['reports'] as List? ?? [])
        .whereType<Map>()
        .map((e) => WeeklyReport.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<VenueOwnerStatsVenue> updateVenue(
    String venueId, {
    String? name,
    String? description,
    String? photo,
    String? type,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (description != null) body['description'] = description;
    if (photo != null) body['photo'] = photo;
    if (type != null) body['type'] = type;

    final data = await _api.patch(
      '/venues/$venueId',
      body: body,
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    return VenueOwnerStatsVenue.fromJson(map);
  }

  Future<VenueOwnerStatsVenue> uploadVenuePhoto(
    String venueId,
    File file,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers['Authorization'] = 'Bearer $token';

    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final mimeParts = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType(mimeParts[0], mimeParts[1]),
      ),
    );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw Exception('Photo upload failed (${response.statusCode}): $body');
    }

    final json = jsonDecode(body) as Map<String, dynamic>;
    return VenueOwnerStatsVenue.fromJson(
      Map<String, dynamic>.from(json['venue'] as Map),
    );
  }

  /// Venue'nun 2km yakınındaki kullanıcılara push bildirimi gönderir.
  /// Returns: { sent: int, rateLimited: bool, rateLimitedUntil: String }
  Future<Map<String, dynamic>> notifyNearby(
    String venueId,
    String title,
    String message,
  ) async {
    final headers = await _authHeaders();
    final data = await _api.post(
      '/venues/$venueId/notify-nearby',
      headers: headers,
      body: {'title': title, 'message': message},
    );
    return Map<String, dynamic>.from(data as Map);
  }
}
