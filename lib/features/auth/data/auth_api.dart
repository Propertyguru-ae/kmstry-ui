import 'dart:convert';

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
  }) async {
    final res = await _client.post(
      '/auth/register',
      body: {'email': email, 'password': password, 'otpProof': otpProof},
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
      return res as Map<String, dynamic>;
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
      final res = await _client.post(
        '/auth/register/request-otp',
        body: {'email': email},
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
  }) async {
    final res = await _client.post('/auth/google', body: {'idToken': idToken});

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
