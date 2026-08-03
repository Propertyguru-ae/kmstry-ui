import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/checkin_photo_model.dart';
import 'package:kmstry_frontend/features/venue/data/ping_response.dart';
import 'venue_checkin_model.dart';
import 'attendee_filter.dart';

/// Cold start yenileme adayı: yakın zamanda süre dolan son check-in.
class RenewableCheckin {
  final String checkinId;
  final String venueId;
  final String? venueName;
  final double venueLatitude;
  final double venueLongitude;

  RenewableCheckin({
    required this.checkinId,
    required this.venueId,
    this.venueName,
    required this.venueLatitude,
    required this.venueLongitude,
  });

  factory RenewableCheckin.fromJson(Map<String, dynamic> json) {
    return RenewableCheckin(
      checkinId: (json['checkinId'] ?? json['id'] ?? '').toString(),
      venueId: (json['venueId'] ?? json['venue_id'] ?? '').toString(),
      venueName: json['venueName']?.toString(),
      venueLatitude: (json['venueLatitude'] as num?)?.toDouble() ?? 0,
      venueLongitude: (json['venueLongitude'] as num?)?.toDouble() ?? 0,
    );
  }
}

class VenueCheckinRepository {
  final ApiClient _api = ApiClient();

  Future<List<VenueCheckin>> getWhoIsHere(
    String venueId, {
    AttendeeFilter? filter,
  }) async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }

    try {
      final query = filter?.toQueryParameters() ?? const <String, String>{};
      final queryString = query.isEmpty
          ? ''
          : '?${Uri(queryParameters: query).query}';
      // ApiClient.get, plain http kullanan öncekinin aksine 401'de token'ı
      // sessizce yeniler ve isteği tekrar dener — check-in sonrası token'ın
      // henüz yenilenmemiş olması yüzünden oluşan yanlış "Unauthorized" hatasını önler.
      final decoded = await _api.get(
        '/venues/$venueId/checkins$queryString',
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (decoded == null) return [];
      if (decoded is! List) {
        throw Exception(
          'Invalid response format: Expected List, got ${decoded.runtimeType}',
        );
      }

      return decoded
          .map((e) => VenueCheckin.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      if (e is Exception) {
        rethrow;
      }
      throw Exception('Failed to load venue checkins: $e');
    }
  }

  Future<List<CheckinPhoto>> getProfilePhotos(String checkinId) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/profile-photos'),
      headers: {'Content-Type': 'application/json'},
    );

    if (res.statusCode >= 400) {
      throw Exception('Failed to load profile photos');
    }

    final List data = jsonDecode(res.body) as List;
    return data.map((e) => CheckinPhoto.fromJson(e)).toList();
  }

  Future<PingResponse> pingCheckin({
    required String checkinId,
    required double latitude,
    required double longitude,
  }) async {
    // Backend requires JwtAuthGuard on this endpoint; missing the header meant
    // every ping 401'd. Routed through ApiClient for the token-refresh/retry too.
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }

    final data = await _api.post(
      '/checkins/$checkinId/ping',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'latitude': latitude, 'longitude': longitude},
    );

    return PingResponse.fromJson(data as Map<String, dynamic>);
  }

  /// Cold start yenileme: aktif check-in yoksa, yakın zamanda süre dolan son
  /// check-in'i (venue koordinatlarıyla) döner. Yoksa null.
  Future<RenewableCheckin?> getRenewableCheckin() async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) return null;
    final data = await _api.get(
      '/checkins/me/renewable',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data == null) return null;
    return RenewableCheckin.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Süresi dolan check-in'i kullanıcı hâlâ mekandaysa yeniden aktifleştirir.
  /// Dönen map: { checkinId, venueId, expiresAt }.
  Future<Map<String, dynamic>> renewCheckin({
    required String checkinId,
    required double latitude,
    required double longitude,
  }) async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }
    final data = await _api.post(
      '/checkins/$checkinId/renew',
      headers: {'Authorization': 'Bearer $accessToken'},
      body: {'latitude': latitude, 'longitude': longitude},
    );
    return Map<String, dynamic>.from(data as Map);
  }

  /// Gets the current user's active check-in via the real backend endpoint
  /// (`GET /my-active` — CheckinsController has an empty @Controller() prefix,
  /// so the route is `/my-active`, NOT `/checkins/my-active`). Returns null if
  /// none is active.
  ///
  /// Previously this cascaded through three approaches — /auth/me, then two
  /// endpoints that don't exist in the backend at all — costing guaranteed-to-404
  /// round trips on every venue detail page load. Routed through ApiClient for
  /// the token-refresh/retry too.
  Future<ActiveCheckin?> getActiveCheckin() async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }

    final data = await _api.get(
      '/my-active',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    if (data == null) return null;
    return ActiveCheckin.fromJson(data as Map<String, dynamic>);
  }
}
