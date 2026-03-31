import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';

import '../../../core/network/api_client.dart';

class AuthApi {
  final ApiClient _client = ApiClient();

  Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String otpProof,
    required bool marketingEmailOptIn,
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    required String consentSource,
  }) async {
    final res = await _client.post(
      '/auth/register',
      body: {
        'email': email,
        'password': password,
        'otpProof': otpProof,
        'marketingEmailOptIn': marketingEmailOptIn,
        'consentGiven': consentGiven,
        'termsVersionId': termsVersionId,
        'privacyVersionId': privacyVersionId,
        'consentSource': consentSource,
      },
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getActiveLegalVersions() async {
    final res = await _client.get('/legal/active-versions');
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUsernameSuggestions({
    required String accessToken,
    required String base,
  }) async {
    final encodedBase = Uri.encodeQueryComponent(base);
    final res = await _client.get(
      '/users/me/username-suggestions?base=$encodedBase',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> requestRegisterOtp({
    required String email,
  }) async {
    try {
      final res = await _client.post(
        '/auth/register/otp/request',
        body: {'email': email},
      );
      debugPrint(
        '[requestRegisterOtp] response (primary): ${jsonEncode(res)}',
      );
      return res as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _client.post(
        '/auth/register/request-otp',
        body: {'email': email},
      );
      debugPrint(
        '[requestRegisterOtp] response (404 fallback): ${jsonEncode(res)}',
      );
      return res as Map<String, dynamic>;
    }
  }

  Future<Map<String, dynamic>> verifyRegisterOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final res = await _client.post(
        '/auth/register/otp/verify',
        body: {'email': email, 'otp': otp},
      );
      return res as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _client.post(
        '/auth/register/verify-otp',
        body: {'email': email, 'otp': otp},
      );
      return res as Map<String, dynamic>;
    }
  }

  Future<Map<String, dynamic>> forgotPassword({required String email}) async {
    final res = await _client.post(
      '/auth/forgot-password',
      body: {'email': email},
    );

    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    final res = await _client.post(
      '/auth/reset-password',
      body: {'token': token, 'newPassword': newPassword},
    );
    return res as Map<String, dynamic>;
  }

  /// Oturum açıkken şifre değiştirme. Backend: `POST /auth/change-password` + JWT.
  Future<Map<String, dynamic>> changePassword({
    required String accessToken,
    required String currentPassword,
    required String newPassword,
  }) async {
    final res = await _client.post(
      '/auth/change-password',
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
      headers: {'Authorization': 'Bearer $accessToken'},
    );
    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) async {
    final res = await _client.post(
      '/auth/login',
      body: {'email': email, 'password': password},
    );

    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> refresh({required String refreshToken}) async {
    final res = await _client.post(
      '/auth/refresh',
      body: {'refreshToken': refreshToken},
    );

    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> logout({required String refreshToken}) async {
    final res = await _client.post(
      '/auth/logout',
      body: {'refreshToken': refreshToken},
    );

    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> loginWithGoogle({
    required String idToken,
    bool? consentGiven,
    String? termsVersionId,
    String? privacyVersionId,
    String? consentSource,
  }) async {
    final body = <String, dynamic>{
      'idToken': idToken,
      if (consentGiven != null) 'consentGiven': consentGiven,
      if (termsVersionId != null) 'termsVersionId': termsVersionId,
      if (privacyVersionId != null) 'privacyVersionId': privacyVersionId,
      if (consentSource != null) 'consentSource': consentSource,
    };
    final res = await _client.post('/auth/google', body: body);

    return res as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> me({required String accessToken}) async {
    final res = await _client.get(
      '/auth/me',
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    return res as Map<String, dynamic>;
  }

  Future<void> resendVerifyEmail({required String accessToken}) async {
    await _client.post(
      '/auth/verify-email/resend',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }

  Future<Map<String, dynamic>> updateMe({
    required String accessToken,
    required Map<String, dynamic> data,
  }) async {
    final res = await _client.patch(
      '/users/me',
      body: data,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    return res as Map<String, dynamic>;
  }

  Future<void> deleteAccount({required String accessToken}) async {
    try {
      await _client.delete(
        '/users/me',
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _client.delete(
        '/auth/me',
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    }
  }

  /// Sadece kişisel context/profil silinir. Root kimlik korunur.
  Future<void> deletePersonalProfile({required String accessToken}) async {
    await _client.delete(
      '/users/me/personal-profile',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }

  /// Sadece ilgili venue üyeliği/contexti silinir. Root kimlik korunur.
  Future<void> removeOwnVenueMembership({
    required String accessToken,
    required String venueId,
  }) async {
    await _client.delete(
      '/venues/$venueId/membership',
      headers: {'Authorization': 'Bearer $accessToken'},
    );
  }

  /// Geçici hesap kapatma (kalıcı silme değil). Backend: POST /users/me/deactivate
  Future<void> deactivateAccount({required String accessToken}) async {
    try {
      await _client.post(
        '/users/me/deactivate',
        body: <String, dynamic>{},
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      await _client.post(
        '/auth/deactivate',
        body: <String, dynamic>{},
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    }
  }

  Future<Map<String, dynamic>> upsertPersonalProfile({
    required String accessToken,
    required Map<String, dynamic> data,
  }) async {
    try {
      final res = await _client.post(
        '/users/me/personal-profile',
        body: data,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      return res as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      // Backward compatibility for environments without personal-profile route.
      final fallback = await _client.patch(
        '/users/me',
        body: data,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      return fallback as Map<String, dynamic>;
    }
  }

  Future<Map<String, dynamic>> switchContext({
    required String accessToken,
    required String lastActiveContext,
    String? activeVenueId,
  }) async {
    Future<void> debugLog({
      required String hypothesisId,
      required String message,
      required Map<String, dynamic> data,
    }) async {
      // #region agent log
      try {
        final file = File(
          '/Users/denizkorukcu/kmstry_ui/.cursor/debug-1c5261.log',
        );
        final payload = <String, dynamic>{
          'sessionId': '1c5261',
          'runId': 'run1',
          'hypothesisId': hypothesisId,
          'location': 'auth_api.dart:switchContext',
          'message': message,
          'data': data,
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        await file.writeAsString(
          '${jsonEncode(payload)}\n',
          mode: FileMode.append,
        );
      } catch (_) {}
      // #endregion
    }

    await debugLog(
      hypothesisId: 'H1',
      message: 'switchContext entry',
      data: {
        'hasActiveVenueId': activeVenueId != null,
        'lastActiveContext': lastActiveContext,
      },
    );

    final body = <String, dynamic>{
      'lastActiveContext': lastActiveContext,
      if (activeVenueId != null) 'activeVenueId': activeVenueId,
    };
    await debugLog(
      hypothesisId: 'H2',
      message: 'switchContext request body keys',
      data: {'keys': body.keys.toList()},
    );

    try {
      final res = await _client.patch(
        '/users/me/context',
        body: body,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
      await debugLog(
        hypothesisId: 'H4',
        message: 'switchContext success',
        data: {'responseKeys': (res as Map<String, dynamic>).keys.toList()},
      );
      return res;
    } on ApiException catch (e) {
      await debugLog(
        hypothesisId: 'H3',
        message: 'switchContext api error',
        data: {'statusCode': e.statusCode, 'error': e.data},
      );
      rethrow;
    }
  }

  Future<void> updatePermissions({
    required String accessToken,
    required Map<String, dynamic> data,
  }) async {
    final response = await http.patch(
      Uri.parse('${AppConfig.baseUrl}/users/me/permissions'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(data),
    );

    if (response.statusCode >= 400) {
      throw ApiException(
        statusCode: response.statusCode,
        data: jsonDecode(response.body),
      );
    }
  }
}
