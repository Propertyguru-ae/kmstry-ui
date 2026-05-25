import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_model.dart';
class NearbyVenuesResponse {
  final List<Venue> mapItems;
  final List<Venue> items;

  NearbyVenuesResponse({
    required this.mapItems,
    required this.items,
  });

  factory NearbyVenuesResponse.fromJson(Map<String, dynamic> json) {
    return NearbyVenuesResponse(
      mapItems: (json['mapItems'] as List? ?? [])
          .map((e) => Venue.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      items: (json['items'] as List? ?? [])
          .map((e) => Venue.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
class VenueRepository {
  final ApiClient _api = ApiClient();

  Future<List<Venue>> getNearbyVenues1({
    required double latitude,
    required double longitude,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final headers = token == null
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};

    // Prefer the new hybrid listing endpoint.
    final nearbyPaths = <String>[
      '/venues/discover?lat=$latitude&lng=$longitude',
      '/venues/discover?latitude=$latitude&longitude=$longitude',
      '/venues/nearby-google?lat=$latitude&lng=$longitude',
      '/venues/nearby-google?latitude=$latitude&longitude=$longitude',
      '/venues',
    ];

    Object? lastError;
    for (final path in nearbyPaths) {
      try {
        final data = await _api.get(path, headers: headers);
        final parsed = _parseVenueList(data);
        if (parsed.isNotEmpty || path == '/venues') return parsed;
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }


Future<NearbyVenuesResponse> getNearbyVenues({
  required double latitude,
  required double longitude,
}) async {
  final token = await SecureStorage.getAccessToken();
  final headers = token == null
      ? const <String, String>{}
      : <String, String>{'Authorization': 'Bearer $token'};

  final path = '/venues/discover?latitude=$latitude&longitude=$longitude';

  final data = await _api.get(path, headers: headers);

  return NearbyVenuesResponse.fromJson(data);
}

  Future<List<Venue>> getMapMarkers({
    required double latitude,
    required double longitude,
    int radiusMeters = 3000,
    int limit = 400,
    String? keyword,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final headers = token == null
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};

    final normalizedLimit = limit.clamp(1, 1000);
    final normalizedRadius = radiusMeters < 1 ? 3000 : radiusMeters;
    final q = keyword?.trim();
    final hasKeyword = q != null && q.isNotEmpty;

    final candidatePaths = <String>[
      '/venues/map-markers?latitude=$latitude&longitude=$longitude&radiusMeters=$normalizedRadius&limit=$normalizedLimit${hasKeyword ? '&keyword=${Uri.encodeQueryComponent(q)}' : ''}',
      '/venues/map-markers?lat=$latitude&lng=$longitude&radiusMeters=$normalizedRadius&limit=$normalizedLimit${hasKeyword ? '&keyword=${Uri.encodeQueryComponent(q)}' : ''}',
    ];

    Object? lastError;
    for (final path in candidatePaths) {
      try {
        final data = await _api.get(path, headers: headers);
        return _parseVenueList(data);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return const [];
  }

  Future<List<Venue>> searchVenues({
    required String query,
    double? latitude,
    double? longitude,
    int limit = 12,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final token = await SecureStorage.getAccessToken();
    final headers = token == null
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};

    final encodedQuery = Uri.encodeQueryComponent(q);

    // Build path — only include lat/lng when meaningful (non-zero) coordinates
    // are available. Without location the backend performs a text-only search.
    final hasLocation = latitude != null &&
        longitude != null &&
        !(latitude == 0 && longitude == 0);

    final locationPart = hasLocation
        ? '&latitude=$latitude&longitude=$longitude'
        : '';
    final path =
        '/venues/search?query=$encodedQuery$locationPart&limit=$limit';

    final data = await _api.get(path, headers: headers);
    return _parseVenueList(data);
  }

  Future<List<Venue>> getVenues() async {
    final data = await _api.get('/venues');
    return _parseVenueList(data);
  }

  List<Venue> _parseVenueList(dynamic data) {
    List<dynamic> list = const [];
    if (data is List) {
      list = data;
    } else if (data is Map<String, dynamic>) {
      final nested = data['items'] ?? data['venues'] ?? data['data'] ?? data['results'];
      if (nested is List) {
        list = nested;
      } else if (nested is Map<String, dynamic> && nested['items'] is List) {
        list = nested['items'] as List;
      }
    }

    return list
        .whereType<Map>()
        .map((e) => Venue.fromJson(Map<String, dynamic>.from(e)))
        .where((v) => v.name.isNotEmpty)
        .toList();
  }

  /// Google Place ID ile venue'yu DB'ye ekler veya varsa getirir.
  /// Backend: POST /venues/ensure-from-place  { placeId }
  /// Donus: { venue: { id, name, ... } }
  Future<String> ensureVenueDbId(String placeId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final result = await _api.post(
      '/venues/ensure-from-place',
      body: {'googlePlaceId': placeId},
      headers: {'Authorization': 'Bearer $token'},
    );
    final map = Map<String, dynamic>.from(result as Map);
    final venueMap = map['venue'] as Map?;
    final id = venueMap?['id']?.toString() ?? map['id']?.toString() ?? map['venueId']?.toString();
    if (id == null || id.isEmpty) throw Exception('Could not resolve venue ID');
    return id;
  }

  /// Kullanicinin mekan sahibi oldugunu iddia eder.
  /// Backend: POST /venues/claim  { venueId, ownerNote }
  Future<Map<String, dynamic>> claimVenue({
    required String venueId,
    required String ownerNote,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final result = await _api.post(
      '/venues/claim',
      body: {'venueId': venueId, 'ownerNote': ownerNote},
      headers: {'Authorization': 'Bearer $token'},
    );
    return Map<String, dynamic>.from(result as Map);
  }

  /// Backend'den venue ID ile tek venue getirir.
  /// Deep link gibi senaryolarda kullanılır.
  Future<Venue> getVenueById(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final headers = token == null
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};

    final data = await _api.get('/venues/$venueId', headers: headers);
    return Venue.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Test venue proximity push'unu tetikler (backend rate-limits to once/hour).
  /// Fire-and-forget: hatalar görmezden gelinir.
  Future<void> triggerTestVenueNotification() async {
    try {
      final token = await SecureStorage.getAccessToken();
      if (token == null) return;
      await _api.post(
        '/venues/test-venue-notification',
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      // Non-fatal — test notification is best-effort.
    }
  }
}
