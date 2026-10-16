import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'app_request_headers.dart';
import 'api_exception.dart';
import '../performance/performance_diagnostics.dart';
import '../storage/secure_storage.dart';
import 'request_session.dart';
import 'public_content_permission.dart';

class ApiClient {
  ApiClient({
    http.Client? client,
    Future<Map<String, String>> Function({bool forceRefresh})?
    appCheckHeaderProvider,
  }) : _client = client ?? http.Client(),
       _appCheckHeaderProvider =
           appCheckHeaderProvider ?? AppRequestHeaders.appCheck;

  final http.Client _client;
  final Future<Map<String, String>> Function({bool forceRefresh})
  _appCheckHeaderProvider;
  static const bool _enableVerboseHttpLogs = false;

  /// Firebase App Check token'ını header olarak döner (varsa). Backend'in
  /// App Check guard'ı bunu doğrulayıp bot/script isteklerini eler. Token
  /// alınamazsa boş döner — normal akışı bozmaz (backend `off`/`monitor`
  /// modunda zaten geçer; `enforce` modunda ise gerçek app zaten token üretir).
  Future<Map<String, String>> _appCheckHeader({bool forceRefresh = false}) =>
      _appCheckHeaderProvider(forceRefresh: forceRefresh);

  /// App/device metadata headers the backend's App Check guard records into the
  /// admin "User Logs" table (app version, build number, platform, OS version).
  /// Sent on EVERY request — not just login — so a user's current build shows up
  /// on their next app-open (`/auth/me`) after they update, without re-login.
  /// Resolved once and cached for the app's lifetime (build info can't change
  /// mid-session).
  Future<Map<String, String>> _appMetadataHeaders() async {
    final metadata = await AppRequestHeaders.appMetadata();
    PerformanceDiagnostics.headersReady();
    return metadata;
  }

  void _noteResponse(http.Response response) {
    if (!PerformanceDiagnostics.enabled) return;
    PerformanceDiagnostics.response(
      status: response.statusCode,
      bytes: response.bodyBytes.length,
      backendId: response.headers['x-kmstry-perf-id'],
    );
  }

  // ── Silent token refresh ──────────────────────────────────────────────────
  /// Registered once by AuthRepository.init().
  /// Returns a new access token, or null if refresh is impossible.
  static Future<String?> Function()? onRefreshToken;

  /// Called when refresh fails — should clear storage and navigate to login.
  static Future<void> Function()? onSessionExpired;

  /// Global forced-update navigation, registered once during app bootstrap.
  static Future<void> Function(Map<String, dynamic> payload)? onUpdateRequired;

  /// In-flight refresh future — prevents parallel refresh calls.
  static Future<String?>? _activeRefresh;
  static int? _activeRefreshRevision;

  /// Shared by HTTP and realtime, so rotating refresh tokens are never raced.
  static Future<String?> refreshSessionToken() {
    if (onRefreshToken == null) return Future.value(null);
    final revision = SecureStorage.sessionRevision;
    if (_activeRefresh == null || _activeRefreshRevision != revision) {
      _activeRefreshRevision = revision;
      late final Future<String?> flight;
      flight = onRefreshToken!()
          .then(
            (token) => revision == SecureStorage.sessionRevision ? token : null,
          )
          .whenComplete(() {
            if (identical(_activeRefresh, flight)) {
              _activeRefresh = null;
              _activeRefreshRevision = null;
            }
          });
      _activeRefresh = flight;
    }
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

  Future<Never> _throwApiException(int statusCode, dynamic data) async {
    final payload = data is Map
        ? Map<String, dynamic>.from(data)
        : <String, dynamic>{'message': data?.toString() ?? 'Request failed'};
    if (payload['errorCode']?.toString().startsWith('AWS_SHARING_') == true) {
      PublicContentPermission.onServerDenied?.call();
    }
    if (statusCode == 426 && payload['errorCode'] == 'APP_UPDATE_REQUIRED') {
      await onUpdateRequired?.call(payload);
    }
    throw ApiException(statusCode: statusCode, data: payload);
  }

  /// Replaces/adds Authorization header with the new token.
  static Map<String, String> _withNewToken(
    Map<String, String>? headers,
    String newToken,
  ) {
    return {
      'Content-Type': 'application/json',
      for (final entry in (headers ?? const <String, String>{}).entries)
        if (entry.key.toLowerCase() != 'authorization') entry.key: entry.value,
      'Authorization': 'Bearer $newToken',
    };
  }

  bool _isAppCheck401(http.Response response) {
    if (response.statusCode != 401) return false;
    if (response.headers['x-kmstry-app-check-retry'] == 'refresh') return true;
    final data = _tryDecode(response.body);
    return data is Map && data['errorCode'] == 'APP_CHECK_REQUIRED';
  }

  /// App Check rejection never expires a JWT session. Refresh its own token
  /// once and preserve Authorization/build metadata on the replayed request.
  Future<dynamic> _retryAppCheck401(
    http.Response first,
    Map<String, String> originalHeaders,
    Future<http.Response> Function(Map<String, String> newHeaders) retry,
    RequestSession session,
  ) async {
    final freshAppCheck = await _appCheckHeader(forceRefresh: true);
    session.check();
    if (freshAppCheck.isEmpty) {
      return _throwApiException(first.statusCode, _tryDecode(first.body));
    }
    final current = await session.currentToken();
    final replay = await retry({
      ...(current == null
          ? originalHeaders
          : _withNewToken(originalHeaders, current)),
      ...freshAppCheck,
    });
    _noteResponse(replay);
    final replayData = _tryDecode(replay.body);
    if (replay.statusCode >= 400) {
      return _throwApiException(replay.statusCode, replayData);
    }
    return replayData;
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
    RequestSession session,
  ) async {
    session.check();
    Future<http.Response> checkedRetry(Map<String, String> headers) async {
      await session.currentToken(candidate: RequestSession.bearer(headers));
      final response = await retry(headers);
      session.check();
      return response;
    }

    if (_isAppCheck401(first)) {
      return _retryAppCheck401(
        first,
        originalHeaders ?? const {},
        checkedRetry,
        session,
      );
    }

    // No Authorization header → this is a credential error (wrong password,
    // invalid OTP, etc.), not a session expiry. Let it propagate normally.
    final hasAuthHeader = session.initialToken != null;
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

    final currentToken = await session.currentToken();
    final newToken = currentToken != session.initialToken
        ? currentToken
        : await refreshSessionToken();
    await session.currentToken(candidate: newToken);
    if (newToken == null) {
      // Refresh failed — session is truly expired.
      await onSessionExpired?.call();
      throw ApiException(
        statusCode: first.statusCode,
        data: _tryDecode(first.body),
      );
    }

    // Retry the original request with the new token.
    final refreshedHeaders = _withNewToken(originalHeaders, newToken);
    final retryResp = await checkedRetry(refreshedHeaders);
    _noteResponse(retryResp);
    _log('🌐 [HTTP] retry statusCode = ${retryResp.statusCode}');

    if (_isAppCheck401(retryResp)) {
      return _retryAppCheck401(
        retryResp,
        refreshedHeaders,
        checkedRetry,
        session,
      );
    }

    final retryData = _tryDecode(retryResp.body);
    if (retryResp.statusCode >= 400) {
      if (retryResp.statusCode == 401) {
        await onSessionExpired?.call();
      }
      return _throwApiException(retryResp.statusCode, retryData);
    }
    return retryData;
  }

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => PerformanceDiagnostics.request(
    'POST',
    path,
    () => _post(path, body: body, headers: headers),
  );

  Future<dynamic> _post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final session = RequestSession(headers);
    await PublicContentPermission.beforeRequest('POST', path, headers, body);
    session.check();
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
      await session.currentToken();
      final response = await _client
          .post(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      session.check();
      _noteResponse(response);
      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          merged,
          (h) => _client
              .post(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
          session,
        );
      }

      final data = _tryDecode(response.body);
      if (response.statusCode >= 400) {
        return _throwApiException(response.statusCode, data);
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
    Duration timeout = const Duration(seconds: 10),
  }) => PerformanceDiagnostics.request(
    'GET',
    path,
    () => _get(path, headers: headers, timeout: timeout),
  );

  Future<dynamic> _get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final session = RequestSession(headers);
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
      await session.currentToken();
      final response = await _client.get(url, headers: merged).timeout(timeout);

      session.check();
      _noteResponse(response);
      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          merged,
          (h) => _client.get(url, headers: h).timeout(timeout),
          session,
        );
      }

      final data = _tryDecode(response.body);
      if (response.statusCode >= 400) {
        return _throwApiException(response.statusCode, data);
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
  }) => PerformanceDiagnostics.request(
    'PATCH',
    path,
    () => _patch(path, body: body, headers: headers),
  );

  Future<dynamic> _patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final session = RequestSession(headers);
    await PublicContentPermission.beforeRequest('PATCH', path, headers, body);
    session.check();
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
      await session.currentToken();
      final response = await _client
          .patch(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      session.check();
      _noteResponse(response);
      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          merged,
          (h) => _client
              .patch(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
          session,
        );
      }

      final data = _tryDecode(response.body);
      if (response.statusCode >= 400) {
        return _throwApiException(response.statusCode, data);
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
  }) => PerformanceDiagnostics.request(
    'PUT',
    path,
    () => _put(path, body: body, headers: headers),
  );

  Future<dynamic> _put(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final session = RequestSession(headers);
    await PublicContentPermission.beforeRequest('PUT', path, headers, body);
    session.check();
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
      await session.currentToken();
      final response = await _client
          .put(url, headers: merged, body: jsonEncode(body ?? {}))
          .timeout(const Duration(seconds: 10));

      session.check();
      _noteResponse(response);
      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          merged,
          (h) => _client
              .put(url, headers: h, body: jsonEncode(body ?? {}))
              .timeout(const Duration(seconds: 10)),
          session,
        );
      }

      final data = _tryDecode(response.body);
      if (response.statusCode >= 400) {
        return _throwApiException(response.statusCode, data);
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

  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      PerformanceDiagnostics.request(
        'DELETE',
        path,
        () => _delete(path, headers: headers),
      );

  Future<dynamic> _delete(String path, {Map<String, String>? headers}) async {
    final session = RequestSession(headers);
    final url = Uri.parse('${AppConfig.baseUrl}$path');
    final merged = {
      'Content-Type': 'application/json',
      ...?headers,
      ...(await _appCheckHeader()),
      ...(await _appMetadataHeaders()),
    };

    _log('🌐 [HTTP] DELETE $url');

    try {
      await session.currentToken();
      final response = await _client
          .delete(url, headers: merged)
          .timeout(const Duration(seconds: 10));

      session.check();
      _noteResponse(response);
      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.statusCode == 401) {
        return _handle401(
          response,
          path,
          merged,
          (h) => _client
              .delete(url, headers: h)
              .timeout(const Duration(seconds: 10)),
          session,
        );
      }

      final data = _tryDecode(response.body);
      if (response.statusCode >= 400) {
        return _throwApiException(response.statusCode, data);
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
