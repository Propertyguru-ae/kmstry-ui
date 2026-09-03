import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  final http.Client _client = http.Client();
  static const bool _enableVerboseHttpLogs = false;

  /// Firebase App Check token'ını header olarak döner (varsa). Backend'in
  /// App Check guard'ı bunu doğrulayıp bot/script isteklerini eler. Token
  /// alınamazsa boş döner — normal akışı bozmaz (backend `off`/`monitor`
  /// modunda zaten geçer; `enforce` modunda ise gerçek app zaten token üretir).
  Future<Map<String, String>> _appCheckHeader() async {
    try {
      // Önce cache'teki token; yoksa (henüz üretilmediyse) bir kez zorla çek.
      var token = await FirebaseAppCheck.instance.getToken();
      if (token == null || token.isEmpty) {
        token = await FirebaseAppCheck.instance.getToken(true);
      }
      if (token != null && token.isNotEmpty) {
        return {'X-Firebase-AppCheck': token};
      }
    } catch (_) {}
    return const {};
  }

  /// App/device metadata headers the backend's App Check guard records into the
  /// admin "User Logs" table (app version, build number, platform, OS version).
  /// Sent on EVERY request — not just login — so a user's current build shows up
  /// on their next app-open (`/auth/me`) after they update, without re-login.
  /// Resolved once and cached for the app's lifetime (build info can't change
  /// mid-session).
  static Map<String, String>? _metadataCache;

  Future<Map<String, String>> _appMetadataHeaders() async {
    final cached = _metadataCache;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final headers = <String, String>{
        if (info.version.isNotEmpty) 'x-kmstry-app-version': info.version,
        if (info.buildNumber.isNotEmpty)
          'x-kmstry-build-number': info.buildNumber,
        'x-kmstry-platform': Platform.operatingSystem,
        'x-kmstry-os-version': Platform.operatingSystemVersion,
      };
      _metadataCache = headers;
      return headers;
    } catch (_) {
      return const {};
    }
  }

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
    _activeRefresh ??= onRefreshToken!().whenComplete(
      () => _activeRefresh = null,
    );
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
    final hasAuthHeader =
        originalHeaders?.containsKey('Authorization') ?? false;
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
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

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

      final data = _tryDecode(response.body);
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

  Future<dynamic> get(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

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
          (h) =>
              _client.get(url, headers: h).timeout(const Duration(seconds: 10)),
        );
      }

      final data = _tryDecode(response.body);
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
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

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

      final data = _tryDecode(response.body);
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

  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

    _log('🌐 [HTTP] PUT $url');
    _log('🌐 [HTTP] body = ${_truncate(body)}');

    try {
      final response = await _client
          .put(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          headers,
          (h) => _client
              .put(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
        );
      }

      final data = _tryDecode(response.body);
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
      _log('❌ [HTTP] PUT error: $e');
      rethrow;
    }
  }

  Future<dynamic> delete(String path, {Map<String, String>? headers}) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

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
          (h) => _client
              .delete(url, headers: h)
              .timeout(const Duration(seconds: 10)),
        );
      }

      final data = _tryDecode(response.body);
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
