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

  Future<List<Venue>> searchVenues({
    required String query,
    required double latitude,
    required double longitude,
    int limit = 12,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final token = await SecureStorage.getAccessToken();
    final headers = token == null
        ? const <String, String>{}
        : <String, String>{'Authorization': 'Bearer $token'};

    final encodedQuery = Uri.encodeQueryComponent(q);
    final candidatePaths = <String>[
      '/venues/search?q=$encodedQuery&latitude=$latitude&longitude=$longitude&limit=$limit',
      '/venues/search?query=$encodedQuery&latitude=$latitude&longitude=$longitude&limit=$limit',
      '/venues/search?term=$encodedQuery&latitude=$latitude&longitude=$longitude&limit=$limit',
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
}
