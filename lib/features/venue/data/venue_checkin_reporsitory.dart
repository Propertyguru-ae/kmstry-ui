import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/checkin_photo_model.dart';
import 'package:kmstry_frontend/features/venue/data/ping_response.dart';
import 'venue_checkin_model.dart';

class VenueCheckinRepository {
  Future<List<VenueCheckin>> getWhoIsHere(String venueId) async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }

    try {
      final res = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/venues/$venueId/checkins'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${accessToken}',
            },
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw Exception('Request timeout: Failed to load venue checkins');
            },
          );

      if (res.statusCode >= 400) {
        final errorBody = res.body.isNotEmpty
            ? res.body
            : 'No error details provided';
        throw Exception(
          'Failed to load venue checkins (${res.statusCode}): $errorBody',
        );
      }

      if (res.body.isEmpty) {
        return [];
      }
      debugPrint("✅ status=${res.statusCode}");
      debugPrint("✅ body=${res.body}");
      try {
        final decoded = jsonDecode(res.body);
        if (decoded is! List) {
          throw Exception(
            'Invalid response format: Expected List, got ${decoded.runtimeType}',
          );
        }

        final List data = decoded;
        debugPrint("✅ decoded runtime=${decoded.runtimeType}");
        debugPrint("✅ decoded length=${data.length}");
        return data
            .map((e) => VenueCheckin.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        throw Exception('Failed to parse venue checkins response: $e');
      }
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
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/ping'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'latitude': latitude, 'longitude': longitude}),
    );

    if (res.statusCode >= 400) {
      throw Exception('Failed to ping checkin');
    }

    return PingResponse.fromJson(jsonDecode(res.body));
  }

  /// Gets the current user's active check-in.
  /// Tries multiple approaches:
  /// 1. Checks /auth/me response for active_checkin field
  /// 2. Falls back to /checkins/active or /users/me/checkins/active endpoint
  /// Returns null if no active check-in exists.
  Future<ActiveCheckin?> getActiveCheckin() async {
    final accessToken = await SecureStorage.getAccessToken();
    if (accessToken == null) {
      throw Exception('UnAuth: No access token available');
    }

    Object? lastError;
    try {
      // Approach 1: Check /auth/me for active_checkin field
      try {
        final me = await AuthRepository().getMe();
        final rawActiveCheckin = me['activeCheckin'] ?? me['active_checkin'];
        debugPrint(
          '🔍 DEBUG getActiveCheckin: /auth/me response keys = ${me.keys}',
        );
        debugPrint(
          '🔍 DEBUG getActiveCheckin: me[activeCheckin] = $rawActiveCheckin',
        );

        if (rawActiveCheckin is Map) {
          final activeCheckinData = Map<String, dynamic>.from(rawActiveCheckin);
          debugPrint(
            '🔍 DEBUG getActiveCheckin: activeCheckinData = $activeCheckinData',
          );
          debugPrint(
            '🔍 DEBUG getActiveCheckin: activeCheckinData keys = ${activeCheckinData.keys}',
          );

          // Check if it's actually active (not expired)
          final checkin = ActiveCheckin.fromJson(activeCheckinData);
          debugPrint(
            '🔍 DEBUG getActiveCheckin: parsed checkin.venueId = ${checkin.venueId}',
          );
          debugPrint(
            '🔍 DEBUG getActiveCheckin: checkin.isActive = ${checkin.isActive}',
          );

          if (checkin.isActive) {
            debugPrint(
              '✅ DEBUG getActiveCheckin: Returning checkin from /auth/me',
            );
            return checkin;
          } else {
            debugPrint('⚠️ DEBUG getActiveCheckin: Check-in found but expired');
          }
        } else {
          debugPrint(
            '⚠️ DEBUG getActiveCheckin: /auth/me does not have active_checkin field',
          );
        }
      } catch (e) {
        // If /auth/me doesn't have active_checkin, continue to next approach
        debugPrint('⚠️ /auth/me does not include active_checkin: $e');
        lastError = e;
      }

      // Approach 2: Try dedicated endpoint /checkins/active
      try {
        final res = await http
            .get(
              Uri.parse('${AppConfig.baseUrl}/checkins/active'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${accessToken}',
              },
            )
            .timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Request timeout');
              },
            );

        if (res.statusCode == 404) {
          // No active check-in
          return null;
        }

        if (res.statusCode >= 400) {
          // Try alternative endpoint
          throw Exception(
            'Failed to get active checkin from /checkins/active (${res.statusCode})',
          );
        }

        if (res.body.isEmpty) {
          return null;
        }

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        debugPrint(
          '🔍 DEBUG getActiveCheckin: /checkins/active response = $data',
        );
        final checkin = ActiveCheckin.fromJson(data);
        debugPrint(
          '🔍 DEBUG getActiveCheckin: parsed checkin.venueId = ${checkin.venueId}',
        );
        return checkin.isActive ? checkin : null;
      } catch (e) {
        lastError = e;
        // Approach 3: Try /users/me/checkins/active
        try {
          final res = await http
              .get(
                Uri.parse('${AppConfig.baseUrl}/users/me/checkins/active'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${accessToken}',
                },
              )
              .timeout(
                const Duration(seconds: 10),
                onTimeout: () {
                  throw Exception('Request timeout');
                },
              );

          if (res.statusCode == 404) {
            return null;
          }

          if (res.statusCode >= 400) {
            throw Exception(
              'Failed to get active checkin from /users/me/checkins/active (${res.statusCode})',
            );
          }

          if (res.body.isEmpty) {
            return null;
          }

          final data = jsonDecode(res.body) as Map<String, dynamic>;
          debugPrint(
            '🔍 DEBUG getActiveCheckin: /users/me/checkins/active response = $data',
          );
          final checkin = ActiveCheckin.fromJson(data);
          debugPrint(
            '🔍 DEBUG getActiveCheckin: parsed checkin.venueId = ${checkin.venueId}',
          );
          return checkin.isActive ? checkin : null;
        } catch (e2) {
          lastError = e2;
          debugPrint(
            '⚠️ Could not fetch active check-in from any endpoint: $e2',
          );
          throw Exception('Could not determine active check-in state');
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error fetching active check-in: $e');
      if (lastError != null) {
        throw Exception('Failed to fetch active check-in: $lastError');
      }
      rethrow;
    }
  }
}
