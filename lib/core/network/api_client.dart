import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  final http.Client _client = http.Client();
  static const bool _enableVerboseHttpLogs = false;

  // ── Silent token refresh ──────────────────────────────────────────────────
  /// Registered once by AuthRepository.init().
  /// Returns a new access token, or null if refresh is impossible.
  static Future<String?> Function()? onRefreshToken;

  /// Called when refresh fails — should clear storage and navigate to login.
  static Future<void> Function()? onSessionExpired;

  /// In-flight refresh future — prevents parallel refresh calls.
  static Future<String?>? _activeRefresh;

  Future<String?> _tryRefresh() {
    if (onRefreshToken == null) return Future.value(null);
    _activeRefresh ??=
        onRefreshToken!().whenComplete(() => _activeRefresh = null);
    return _activeRefresh!;
  }

  // ──────────────────────────────────────────────────────────────────────────

  void _log(String message) {
    if (kDebugMode && _enableVerboseHttpLogs) {
      debugPrint(message);
    }
  }

  String _truncate(dynamic value, {int max = 500}) {
    final text = value?.toString() ?? 'null';
    if (text.length <= max) return text;
    return '${text.substring(0, max)}... [truncated ${text.length - max} chars]';
  }

  dynamic _tryDecode(String body) {
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  /// Replaces/adds Authorization header with the new token.
  static Map<String, String> _withNewToken(
    Map<String, String>? headers,
    String newToken,
  ) {
    return {
      'Content-Type': 'application/json',
      ...?headers,
      'Authorization': 'Bearer $newToken',
    };
  }

  /// After a 401 response: try refresh, retry, or expire session.
  ///
  /// Only activates when the request carried an Authorization header — meaning
  /// it was an authenticated call whose token may have expired.
  /// Unauthenticated endpoints (login, register, OTP…) that return 401 for bad
  /// credentials are passed through immediately so the UI can show the error.
  Future<dynamic> _handle401(
    http.Response first,
    String path,
    Map<String, String>? originalHeaders,
    Future<http.Response> Function(Map<String, String> newHeaders) retry,
  ) async {
    // No Authorization header → this is a credential error (wrong password,
    // invalid OTP, etc.), not a session expiry. Let it propagate normally.
    final hasAuthHeader = originalHeaders?.containsKey('Authorization') ?? false;
    if (!hasAuthHeader) {
      throw ApiException(
        statusCode: first.statusCode,
        data: _tryDecode(first.body),
      );
    }

    // Don't recurse on the refresh/logout endpoints themselves.
    final isAuthEndpoint =
        path.contains('/auth/refresh') || path.contains('/auth/logout');
    if (isAuthEndpoint) {
      throw ApiException(
        statusCode: first.statusCode,
        data: _tryDecode(first.body),
      );
    }

    final newToken = await _tryRefresh();
    if (newToken == null) {
      // Refresh failed — session is truly expired.
      await onSessionExpired?.call();
      throw ApiException(
        statusCode: first.statusCode,
        data: _tryDecode(first.body),
      );
    }

    // Retry the original request with the new token.
    final retryResp = await retry(_withNewToken(originalHeaders, newToken));
    _log('🌐 [HTTP] retry statusCode = ${retryResp.statusCode}');

    final retryData = _tryDecode(retryResp.body);
    if (retryResp.statusCode >= 400) {
      if (retryResp.statusCode == 401) {
        await onSessionExpired?.call();
      }
      throw ApiException(statusCode: retryResp.statusCode, data: retryData);
    }
    return retryData;
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {'Content-Type': 'application/json', ...?headers};

    _log('🌐 [HTTP] POST $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');
    _log('🌐 [HTTP] body = ${_truncate(body)}');

    try {
      final response = await _client
          .post(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          headers,
          (h) => _client
              .post(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
        );
      }

      final data = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }
      return data;
    } on SocketException catch (e) {
      _log('❌ [HTTP] SocketException: $e');
      rethrow;
    } on TimeoutException catch (e) {
      _log('⏱️ [HTTP] TimeoutException: $e');
      rethrow;
    } catch (e) {
      _log('❌ [HTTP] Unknown error: $e');
      rethrow;
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {'Content-Type': 'application/json', ...?headers};

    _log('🌐 [HTTP] GET $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');

    try {
      final response = await _client
          .get(url, headers: merged)
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          headers,
          (h) => _client.get(url, headers: h).timeout(const Duration(seconds: 10)),
        );
      }

      final data = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }
      return data;
    } catch (e) {
      _log('❌ [HTTP] GET error: $e');
      rethrow;
    }
  }

  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {'Content-Type': 'application/json', ...?headers};

    _log('🌐 [HTTP] PATCH $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');
    _log('🌐 [HTTP] body = ${_truncate(body)}');

    try {
      final response = await _client
          .patch(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          headers,
          (h) => _client
              .patch(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
        );
      }

      final data = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }
      return data;
    } on SocketException catch (e) {
      _log('❌ [HTTP] SocketException: $e');
      rethrow;
    } on TimeoutException catch (e) {
      _log('⏱️ [HTTP] TimeoutException: $e');
      rethrow;
    } catch (e) {
      _log('❌ [HTTP] Unknown error: $e');
      rethrow;
    }
  }

  Future<dynamic> delete(
    String path, {
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {'Content-Type': 'application/json', ...?headers};

    _log('🌐 [HTTP] DELETE $url');

    try {
      final response = await _client
          .delete(url, headers: merged)
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          headers,
          (h) =>
              _client.delete(url, headers: h).timeout(const Duration(seconds: 10)),
        );
      }

      if (response.body.isEmpty) return null;
      final data = jsonDecode(response.body);
      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }
      return data;
    } on SocketException catch (e) {
      _log('❌ [HTTP] SocketException: $e');
      rethrow;
    } on TimeoutException catch (e) {
      _log('⏱️ [HTTP] TimeoutException: $e');
      rethrow;
    } catch (e) {
      _log('❌ [HTTP] DELETE error: $e');
      rethrow;
    }
  }
}
