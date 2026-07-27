import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

/// One "Today's events" item: the event plus which venue it belongs to, so the
/// home feed can render it and open the venue-scoped event detail page.
class TodayEvent {
  final VenueUpcomingEvent event;
  final String venueId;
  final String venueName;
  final String? venuePhoto;

  const TodayEvent({
    required this.event,
    required this.venueId,
    required this.venueName,
    this.venuePhoto,
  });

  factory TodayEvent.fromJson(Map<String, dynamic> j) => TodayEvent(
    event: VenueUpcomingEvent.fromJson(j),
    venueId: (j['venueId'] ?? j['venue_id'] ?? '').toString(),
    venueName: (j['venueName'] ?? j['venue_name'] ?? '').toString(),
    venuePhoto: (j['venuePhoto'] ?? j['venue_photo'])?.toString(),
  );
}

class VenueEventRepository {
  final ApiClient _api = ApiClient();

  /// Home feed: events the user has RSVP'd to that happen today.
  Future<List<TodayEvent>> getMyTodayEvents() async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/me/events/today',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => TodayEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<List<TodayEvent>> getMyEvents({String filter = 'today'}) async {
    final token = await SecureStorage.getAccessToken();
    final encoded = Uri.encodeQueryComponent(filter);
    final data = await _api.get(
      '/venues/me/events?filter=$encoded',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => TodayEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Hafif event listesi — owner-stats'ın ağır sorgusunu çalıştırmaz.
  Future<List<VenueUpcomingEvent>> listEvents(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/events',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Tek event'in taze hâlini çeker (filtre yok — güncelleme sonrası detay yenilemek için).
  Future<VenueUpcomingEvent> getEventDetail({
    required String venueId,
    required String eventId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/events/$eventId',
      headers: {'Authorization': 'Bearer $token'},
    );
    return VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<Map<String, dynamic>> createEvent({
    required String venueId,
    required String title,
    String? description,
    required DateTime startAt,
    required DateTime endAt,
    int? priceAed,
    String currency = 'TRY',
    int? capacity,
    Map<String, dynamic>? recurrence,
    List<String>? partnershipIds,
    Map<String, dynamic>? offer,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.post(
      '/venues/$venueId/events',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        'startAt': startAt.toUtc().toIso8601String(),
        'endAt': endAt.toUtc().toIso8601String(),
        if (priceAed != null) 'priceAed': priceAed,
        'currency': currency,
        if (capacity != null) 'capacity': capacity,
        if (recurrence != null) 'recurrence': recurrence,
        if (partnershipIds != null && partnershipIds.isNotEmpty)
          'partnershipIds': partnershipIds,
        if (offer != null) 'offer': offer,
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
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/$venueId/events/$eventId/photos',
    );
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

  /// Recurring seri için tek foto yükler; backend URL'i tüm occurrence'lara uygular.
  Future<void> uploadRecurringPhoto({
    required String venueId,
    required String ruleId,
    required File file,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/$venueId/events/recurring/$ruleId/photos',
    );
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
    int? capacity,
    bool clearCapacity = false,
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
        if (clearPrice)
          'priceAed': null
        else if (priceAed != null)
          'priceAed': priceAed,
        if (currency != null) 'currency': currency,
        if (clearCapacity)
          'capacity': null
        else if (capacity != null)
          'capacity': capacity,
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
    final uri = Uri.parse(
      '${AppConfig.baseUrl}/venues/$venueId/events/$eventId/photos',
    );
    final req = http.Request('DELETE', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..headers['Content-Type'] = 'application/json'
      ..body = '{"photoUrl":"${photoUrl.replaceAll('"', '\\"')}"}';
    final resp = await req.send();
    if (resp.statusCode >= 400) {
      throw Exception('Remove photo failed (${resp.statusCode})');
    }
  }

  Future<void> deleteEvent({
    required String venueId,
    required String eventId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/events/$eventId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> rsvpEvent({
    required String venueId,
    required String eventId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.post(
      '/venues/$venueId/events/$eventId/rsvp',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> cancelRsvp({
    required String venueId,
    required String eventId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/events/$eventId/rsvp',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<List<Map<String, dynamic>>> getEventRsvps({
    required String venueId,
    required String eventId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/events/$eventId/rsvps',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }
}
