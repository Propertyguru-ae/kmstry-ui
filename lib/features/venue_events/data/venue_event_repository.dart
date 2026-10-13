import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/venue/venue_read_changes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'venue_event_mutation.dart';
import 'venue_event_deletion.dart';
import 'venue_event_calendar_entry.dart';

/// One "Today's events" item: the event plus which venue it belongs to, so the
/// home feed can render it and open the venue-scoped event detail page.
class TodayEvent {
  final VenueUpcomingEvent event;
  final String venueId;
  final String venueName;
  final String? venuePhoto;

  /// "Happening Nearby" / Discover için mekana uzaklık (metre). Yoksa null.
  final int? distanceMeters;

  const TodayEvent({
    required this.event,
    required this.venueId,
    required this.venueName,
    this.venuePhoto,
    this.distanceMeters,
  });

  factory TodayEvent.fromJson(Map<String, dynamic> j) => TodayEvent(
    event: VenueUpcomingEvent.fromJson(j),
    venueId: (j['venueId'] ?? j['venue_id'] ?? '').toString(),
    venueName: (j['venueName'] ?? j['venue_name'] ?? '').toString(),
    venuePhoto: (j['venuePhoto'] ?? j['venue_photo'])?.toString(),
    distanceMeters: (j['distanceMeters'] ?? j['distance_meters']) is num
        ? ((j['distanceMeters'] ?? j['distance_meters']) as num).toInt()
        : null,
  );
}

/// A committed change to the current user's KMSTRY calendar, not a booking.
class PersonalEventCalendarChange {
  const PersonalEventCalendarChange({
    required this.venueId,
    required this.eventId,
    required this.saved,
    required this.session,
    this.entry,
  });

  final String venueId;
  final String eventId;
  final bool saved;
  final int session;
  final TodayEvent? entry;

  List<TodayEvent> applyToday(List<TodayEvent> current, {DateTime? now}) {
    // Without a snapshot, only the subsequent authenticated read can add it.
    if (saved &&
        (entry == null ||
            entry!.venueId != venueId ||
            entry!.event.id != eventId)) {
      return current;
    }
    final events = current
        .where((item) => item.venueId != venueId || item.event.id != eventId)
        .toList();
    final date = (now ?? DateTime.now()).toLocal();
    final start = entry?.event.startAt.toLocal();
    if (saved &&
        entry?.venueId == venueId &&
        entry?.event.id == eventId &&
        start?.year == date.year &&
        start?.month == date.month &&
        start?.day == date.day) {
      events.add(entry!);
    }
    events.sort((a, b) => a.event.startAt.compareTo(b.event.startAt));
    return events;
  }
}

class VenueEventRepository {
  static final calendarChanges = ValueNotifier<PersonalEventCalendarChange?>(
    null,
  );
  VenueEventRepository({
    ApiClient? apiClient,
    AuthenticatedMultipartUpload? multipart,
    PendingPublicMediaService? uploads,
  }) : _api = apiClient ?? ApiClient(),
       _multipart = multipart ?? AuthenticatedMultipartUpload(),
       _uploads = uploads ?? PendingPublicMediaService.instance;
  final ApiClient _api;
  final AuthenticatedMultipartUpload _multipart;
  final PendingPublicMediaService _uploads;

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

  /// Home feed "Places you might like": takip edilen venue'lerin yaklaşan
  /// event'leri. Boş liste → bölüm gizlenir.
  Future<List<TodayEvent>> getFollowedVenuesEvents({int limit = 20}) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/me/following/events?limit=$limit',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => TodayEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// "Happening Nearby" / Discover Events: takip edilmeyen mekanların yaklaşan
  /// event'leri. Konum verilirse mesafeye göre sıralı. Opsiyonel filtreler:
  /// [platform] (partnership) ve [when] ('today'|'week'|'month'|'all').
  Future<List<TodayEvent>> getDiscoverEvents({
    double? latitude,
    double? longitude,
    int limit = 20,
    int offset = 0,
    String? platform,
    String? when,
    DateTime? from,
    DateTime? to,
    String? scope,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
      if (latitude != null) 'latitude': '$latitude',
      if (longitude != null) 'longitude': '$longitude',
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (when != null && when.isNotEmpty && when != 'all') 'when': when,
      if (from != null) 'from': from.toIso8601String(),
      if (to != null) 'to': to.toIso8601String(),
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final data = await _api.get(
      '/venues/events/discover?$query',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => TodayEvent.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<Set<String>> getDiscoverEventsCalendarDays({
    required int year,
    required int month,
    String? platform,
    String? scope,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final params = <String, String>{
      'year': '$year',
      'month': '$month',
      if (platform != null && platform.isNotEmpty) 'platform': platform,
      if (scope != null && scope.isNotEmpty) 'scope': scope,
    };
    final query = params.entries
        .map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    final data = await _api.get(
      '/venues/events/discover/calendar?$query',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map) return <String>{};
    final days = data['days'];
    if (days is! List) return <String>{};
    return days.map((e) => e.toString()).toSet();
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

  /// All calendar dates, without images, descriptions or heavy relations.
  Future<List<VenueEventCalendarEntry>> getEventCalendar(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/events/calendar',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (data as List)
        .whereType<Map>()
        .map(
          (e) => VenueEventCalendarEntry.fromJson(Map<String, dynamic>.from(e)),
        )
        .toList();
  }

  /// Full event details for one device-local month. End is exclusive and UTC
  /// boundaries preserve local day selection, including daylight-saving days.
  Future<List<VenueUpcomingEvent>> listEventMonth(
    String venueId,
    DateTime month,
  ) async {
    final token = await SecureStorage.getAccessToken();
    final from = DateTime(month.year, month.month).toUtc();
    final to = DateTime(month.year, month.month + 1).toUtc();
    final query = Uri(
      queryParameters: {
        'from': from.toIso8601String(),
        'to': to.toIso8601String(),
      },
    ).query;
    final data = await _api.get(
      '/venues/$venueId/events?$query',
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
    final session = PendingPublicMediaService.instance.sessionGeneration;
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
    final result = Map<String, dynamic>.from(data as Map);
    VenueReadChanges.committed(venueId, {VenueReadSection.events}, session);
    return result;
  }

  Future<Map<String, dynamic>> uploadPhoto({
    required String venueId,
    required String eventId,
    required File file,
    required PendingPublicMedia pendingDraft,
    required int uploadSession,
  }) => _uploadPhoto(
    '/venues/$venueId/events/$eventId/photos',
    file,
    pendingDraft,
    uploadSession,
    venueId: venueId,
    eventId: eventId,
  );

  /// Recurring seri için tek foto yükler; backend URL'i tüm occurrence'lara uygular.
  Future<Map<String, dynamic>> uploadRecurringPhoto({
    required String venueId,
    required String ruleId,
    required File file,
    required PendingPublicMedia pendingDraft,
    required int uploadSession,
  }) => _uploadPhoto(
    '/venues/$venueId/events/recurring/$ruleId/photos',
    file,
    pendingDraft,
    uploadSession,
    venueId: venueId,
    recurringRuleId: ruleId,
  );

  Future<Map<String, dynamic>> _uploadPhoto(
    String path,
    File file,
    PendingPublicMedia draft,
    int session, {
    required String venueId,
    String? eventId,
    String? recurringRuleId,
  }) async {
    if (draft.kind != PendingPublicMediaKind.eventPhoto ||
        draft.venueId != venueId ||
        draft.eventId != eventId ||
        draft.recurringRuleId != recurringRuleId ||
        (draft.venueId?.isEmpty ?? true) ||
        ((draft.eventId?.isEmpty ?? true) &&
            (draft.recurringRuleId?.isEmpty ?? true))) {
      throw ArgumentError('Invalid event photo target');
    }
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    return _uploads.runUpload<Map<String, dynamic>>(
      draft: draft,
      token: token,
      expectedGeneration: session,
      // Event target IDs are shared by several photos; never match by event ID.
      receiptId: (json) => json['moderation_item_id']?.toString(),
      send: (progress) async {
        final response = await _multipart.send(
          initialToken: token,
          isCurrentSession: () =>
              _uploads.isCurrentSession(session) &&
              !_uploads.isEventPhotoTargetDeleted(draft),
          cancellation: _uploads.eventPhotoCancellation(
            draft.uploadId ?? draft.id,
          ),
          timeout: const Duration(minutes: 5),
          createRequest: (headers) async {
            final request = http.MultipartRequest(
              'POST',
              Uri.parse('${AppConfig.baseUrl}$path'),
            );
            request.headers.addAll(headers);
            request.files.add(
              await multipartFileWithProgress(
                field: 'file',
                file: file,
                contentType: http_parser.MediaType.parse(
                  lookupMimeType(file.path) ?? 'image/jpeg',
                ),
                onProgress: progress,
              ),
            );
            return request;
          },
        );
        if (response.statusCode >= 400) {
          if (response.statusCode < 500 && response.statusCode != 408) {
            throw PublicMediaUploadRejected(
              'Event photo upload rejected (${response.statusCode})',
            );
          }
          throw const HttpException(
            'Event photo upload could not be confirmed',
          );
        }
        return Map<String, dynamic>.from(jsonDecode(response.body) as Map);
      },
    );
  }

  Future<VenueEventMutation> updateEvent({
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
    bool clearRecurrence = false,
    List<String>? partnershipIds,
    Map<String, dynamic>? offer,
    bool clearOffer = false,
  }) async {
    final session = PendingPublicMediaService.instance.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    final response = await _api.patch(
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
        if (clearRecurrence)
          'recurrence': null
        else if (recurrence != null)
          'recurrence': recurrence,
        'partnershipIds': ?partnershipIds,
        if (clearOffer) 'offer': null else 'offer': ?offer,
      },
    );
    final result = VenueEventMutation.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
    VenueReadChanges.committed(venueId, {VenueReadSection.events}, session);
    return result;
  }

  Future<VenueEventDeletion> deleteRecurringSeries({
    required String venueId,
    required String ruleId,
  }) async {
    final session = _uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    final response = await _api.delete(
      '/venues/$venueId/recurring-rules/$ruleId',
      headers: {'Authorization': 'Bearer $token'},
    );
    final deletion = VenueEventDeletion.fromJson(response, ruleId: ruleId);
    _uploads.confirmEventDeletion(
      venueId: venueId,
      removedEventIds: deletion.removedEventIds,
      removedRecurringRuleId: deletion.removedRecurringRuleId,
      expectedGeneration: session,
    );
    VenueReadChanges.committed(venueId, {VenueReadSection.events}, session);
    return deletion;
  }

  Future<void> removePhoto({
    required String venueId,
    required String eventId,
    required String photoUrl,
  }) async {
    final session = PendingPublicMediaService.instance.sessionGeneration;
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
    VenueReadChanges.committed(venueId, {VenueReadSection.events}, session);
  }

  Future<VenueEventDeletion> deleteEvent({
    required String venueId,
    required String eventId,
  }) async {
    final session = _uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    final response = await _api.delete(
      '/venues/$venueId/events/$eventId',
      headers: {'Authorization': 'Bearer $token'},
    );
    final deletion = VenueEventDeletion.fromJson(response, eventId: eventId);
    _uploads.confirmEventDeletion(
      venueId: venueId,
      removedEventIds: deletion.removedEventIds,
      removedRecurringRuleId: deletion.removedRecurringRuleId,
      expectedGeneration: session,
    );
    VenueReadChanges.committed(venueId, {VenueReadSection.events}, session);
    return deletion;
  }

  Future<Map<String, dynamic>> rsvpEvent({
    required String venueId,
    required String eventId,
    TodayEvent? calendarEntry,
  }) async {
    final session = _uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    if (!_uploads.isCurrentSession(session)) {
      throw StateError('Event calendar session changed.');
    }
    final data = await _api.post(
      '/venues/$venueId/events/$eventId/rsvp',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
    final result = Map<String, dynamic>.from(data as Map);
    if (result['success'] != true) {
      throw StateError('Event could not be added to your calendar.');
    }
    if (_uploads.isCurrentSession(session)) {
      calendarChanges.value = PersonalEventCalendarChange(
        venueId: venueId,
        eventId: eventId,
        saved: true,
        session: session,
        entry: calendarEntry,
      );
    }
    return result;
  }

  Future<void> cancelRsvp({
    required String venueId,
    required String eventId,
  }) async {
    final session = _uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    if (!_uploads.isCurrentSession(session)) {
      throw StateError('Event calendar session changed.');
    }
    final data = await _api.delete(
      '/venues/$venueId/events/$eventId/rsvp',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map || data['success'] != true) {
      throw StateError('Event could not be removed from your calendar.');
    }
    if (_uploads.isCurrentSession(session)) {
      calendarChanges.value = PersonalEventCalendarChange(
        venueId: venueId,
        eventId: eventId,
        saved: false,
        session: session,
      );
    }
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
