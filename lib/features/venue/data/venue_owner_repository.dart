import 'dart:io';

import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/venue/venue_read_changes.dart';
import 'package:kmstry_frontend/features/content_moderation/data/avatar_upload_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'venue_owner_stats_model.dart';
import 'venue_analytics_model.dart';
import 'venue_follower_model.dart';
import 'venue_model.dart';

class VenueOwnerRepository {
  VenueOwnerRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

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

  /// Full profile/event data, without unrelated dashboard counters or guests.
  /// Deliberately no result cache: avatar/event edits must remain fresh.
  Future<VenueOwnerStatsVenue> getOwnerProfile(String venueId) async {
    final data = await _api.get(
      '/venues/$venueId/owner-profile',
      headers: await _authHeaders(),
    );
    return VenueOwnerStatsVenue.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  Future<VenueOwnerGuestsResponse> getOwnerGuests(String venueId) async {
    final data = await _api.get(
      '/venues/$venueId/owner-guests',
      headers: await _authHeaders(),
    );
    return VenueOwnerGuestsResponse.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  /// All identity fields, independently of full event history/media signing.
  /// No new result cache: approved photo and venue edits remain fresh.
  Future<VenueOwnerStatsVenue> getOwnerProfileIdentity(String venueId) async {
    final data = await _api.get(
      '/venues/$venueId/owner-profile/identity',
      headers: await _authHeaders(),
    );
    return VenueOwnerStatsVenue.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
  }

  /// Exact rolling-week overlap used by VenueUpcomingEventsSection. All event
  /// fields and ongoing events are preserved; historical dates remain in the
  /// separate Events calendar/full-profile endpoints.
  Future<List<VenueUpcomingEvent>> getOwnerProfileUpcomingEvents(
    String venueId, {
    DateTime? now,
  }) async {
    final from = now ?? DateTime.now();
    final to = from.add(const Duration(days: 7));
    final query = Uri(
      queryParameters: {
        'from': from.toUtc().toIso8601String(),
        'to': to.toUtc().toIso8601String(),
      },
    ).query;
    final data = await _api.get(
      '/venues/$venueId/owner-profile/upcoming-events?$query',
      headers: await _authHeaders(),
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Matches the existing Today's Events widget's device-local overlap window.
  /// All today's events and all their detail fields are retained; there is no cap.
  Future<VenueOwnerStatsResponse> getOwnerDashboard(
    String venueId, {
    DateTime? now,
  }) async {
    final day = now ?? DateTime.now();
    final start = DateTime(day.year, day.month, day.day);
    final end = start.add(const Duration(days: 1));
    final query = Uri(
      queryParameters: {
        'from': start.toUtc().toIso8601String(),
        'to': end.toUtc().toIso8601String(),
      },
    ).query;
    final data = await _api.get(
      '/venues/$venueId/owner-dashboard?$query',
      headers: await _authHeaders(),
    );
    return VenueOwnerStatsResponse.fromJson(
      Map<String, dynamic>.from(data as Map),
    );
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

  /// Resolve on every download: the backend rechecks membership and permissions.
  Future<String> getWeeklyReportDownloadUrl(
    String venueId,
    String reportId,
  ) async {
    final data = await _api.get(
      '/venues/${Uri.encodeComponent(venueId)}/reports/${Uri.encodeComponent(reportId)}/download-url',
      headers: await _authHeaders(),
    );
    final value = data is Map ? data['url'] : null;
    final uri = value is String ? Uri.tryParse(value) : null;
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw const FormatException('Invalid report download response');
    }
    return uri.toString();
  }

  Future<VenueOwnerStatsVenue> updateVenue(
    String venueId, {
    String? name,
    String? description,
    String? photo,
    String? type,
  }) async {
    final session = PendingPublicMediaService.instance.sessionGeneration;
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
    final venue = VenueOwnerStatsVenue.fromJson(map);
    VenueReadChanges.committed(venueId, {VenueReadSection.identity}, session);
    return venue;
  }

  Future<VenueOwnerStatsVenue> uploadVenuePhoto(
    String venueId,
    File file,
  ) async {
    final json = await AvatarUploadRepository().upload(
      file: file,
      session: PendingPublicMediaService.instance.sessionGeneration,
      draft: PendingPublicMedia(
        id: PendingPublicMediaService.newUploadId(),
        kind: PendingPublicMediaKind.venueAvatar,
        venueId: venueId,
        localPath: file.path,
        isVideo: false,
        createdAt: DateTime.now(),
        hasServerReceipt: false,
      ),
    );
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
