import 'dart:convert';

import 'package:http/http.dart' as http;

import '../storage/secure_storage.dart';
import 'api_client.dart';
import 'app_request_headers.dart';
import 'multipart_upload.dart';
import 'upload_session_identity.dart';

typedef MultipartRequestFactory =
    Future<http.MultipartRequest> Function(Map<String, String> headers);
typedef MultipartRequestSender =
    Future<http.StreamedResponse> Function(
      http.MultipartRequest request, {
      required Duration timeout,
      MultipartUploadCancellation? cancellation,
    });

/// API uploads only, never storage-provider signed URLs. Rebuild the request
/// and file stream once after a definite 401; never replay uncertain outcomes.
class AuthenticatedMultipartUpload {
  AuthenticatedMultipartUpload({
    Future<String?> Function()? readToken,
    Future<String?> Function()? refreshToken,
    Future<Map<String, String>> Function({String? accessToken})? headers,
    Future<Map<String, String>> Function({bool forceRefresh})? appCheckHeaders,
    MultipartRequestSender? sender,
  }) : _readToken = readToken ?? SecureStorage.getAccessToken,
       _refreshToken = refreshToken ?? ApiClient.refreshSessionToken,
       _headers = headers ?? AppRequestHeaders.build,
       _appCheckHeaders = appCheckHeaders ?? AppRequestHeaders.appCheck,
       _sender = sender ?? sendMultipartRequest;

  final Future<String?> Function() _readToken;
  final Future<String?> Function() _refreshToken;
  final Future<Map<String, String>> Function({String? accessToken}) _headers;
  final Future<Map<String, String>> Function({bool forceRefresh})
  _appCheckHeaders;
  final MultipartRequestSender _sender;

  Future<http.Response> send({
    required String initialToken,
    required bool Function() isCurrentSession,
    required MultipartRequestFactory createRequest,
    Duration timeout = defaultMultipartUploadTimeout,
    MultipartUploadCancellation? cancellation,
  }) async {
    void ensureSession() {
      cancellation?.throwIfCancelled();
      if (!isCurrentSession()) throw StateError('UPLOAD_SESSION_CHANGED');
    }

    Future<String> currentToken() async {
      ensureSession();
      final token = await _readToken();
      ensureSession();
      if (!sameUploadOwner(initialToken, token)) {
        throw StateError('UPLOAD_SESSION_CHANGED');
      }
      return token!;
    }

    Future<http.Response> attempt(
      String token, {
      Map<String, String> extraHeaders = const {},
    }) async {
      ensureSession();
      final headers = {...await _headers(accessToken: token), ...extraHeaders};
      await currentToken();
      final request = await createRequest(headers);
      await currentToken();
      final response = await _sender(
        request,
        timeout: timeout,
        cancellation: cancellation,
      );
      final buffered = await http.Response.fromStream(response);
      await currentToken();
      return buffered;
    }

    final sentToken = await currentToken();
    final first = await attempt(sentToken);
    if (first.statusCode != 401) return first;

    if (_isAppCheckRejection(first)) {
      final refreshed = await _appCheckHeaders(forceRefresh: true);
      final current = await currentToken();
      if (refreshed['X-Firebase-AppCheck']?.isNotEmpty != true) return first;
      return attempt(current, extraHeaders: refreshed);
    }

    // JSON/realtime calls may already have rotated this same user's token.
    // Reuse it without racing the rotating refresh-token endpoint again.
    final current = await currentToken();
    if (current != sentToken) return attempt(current);

    final refreshed = await _refreshToken();
    await currentToken();
    if (refreshed == null) return first;
    if (!sameUploadOwner(initialToken, refreshed)) {
      throw StateError('UPLOAD_SESSION_CHANGED');
    }
    return attempt(refreshed);
  }

  static bool _isAppCheckRejection(http.Response response) {
    if (response.headers['x-kmstry-app-check-retry'] == 'refresh') return true;
    try {
      final data = jsonDecode(response.body);
      return data is Map && data['errorCode'] == 'APP_CHECK_REQUIRED';
    } on FormatException {
      return false;
    }
  }
}
