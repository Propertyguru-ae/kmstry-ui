import 'dart:async';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/request_session.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';

typedef AwsPermissionPrompt =
    Future<bool> Function(Map<String, dynamic> notice);

/// Memory is only a UX hint; the backend checks every transfer. Never persist
/// an account-agnostic boolean or reuse an old account's dialog/response.
class AwsSharingPermission {
  AwsSharingPermission({ApiClient? api, this.prompt})
    : _api = api ?? ApiClient();
  static final instance = AwsSharingPermission();
  final ApiClient _api;
  AwsPermissionPrompt? prompt;
  int? _grantedSession;
  Future<void>? _inFlight;
  int? _flightSession;
  int _choiceGeneration = 0;

  void invalidate() {
    _grantedSession = null;
    _choiceGeneration++;
  }

  void _checkChoice(int generation) {
    if (generation != _choiceGeneration) {
      throw ApiException(
        statusCode: 409,
        data: const {
          'errorCode': 'AWS_SHARING_CHOICE_CHANGED',
          'message': 'Your privacy choice changed. Please try again.',
        },
      );
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<Map<String, dynamic>> status() async {
    final generation = _choiceGeneration;
    final headers = await _headers();
    final session = RequestSession(headers);
    final result = await _api.get(
      '/privacy/aws-sharing-permission',
      headers: headers,
    );
    session.check();
    _checkChoice(generation);
    final data = Map<String, dynamic>.from(result as Map);
    _grantedSession = data['granted'] == true ? session.revision : null;
    return data;
  }

  Future<void> ensure(Map<String, String> headers) async {
    final session = RequestSession(headers);
    await session.currentToken();
    if (session.initialToken == null) throw StateError('Not authenticated');
    if (_grantedSession == session.revision) return;
    if (_inFlight != null && _flightSession == session.revision) {
      await _inFlight;
      session.check();
      return;
    }
    _flightSession = session.revision;
    final flight = _request(session, headers);
    _inFlight = flight;
    try {
      await flight;
    } finally {
      if (identical(_inFlight, flight)) {
        _inFlight = null;
        _flightSession = null;
      }
    }
  }

  Future<void> _request(
    RequestSession session,
    Map<String, String> headers,
  ) async {
    final generation = _choiceGeneration;
    final result = await _api.get(
      '/privacy/aws-sharing-permission',
      headers: headers,
    );
    await session.currentToken();
    _checkChoice(generation);
    if (result is! Map || result['notice'] is! Map) {
      throw const FormatException('Invalid safety-check information');
    }
    if (result['granted'] == true) {
      _grantedSession = session.revision;
      return;
    }
    final notice = Map<String, dynamic>.from(result['notice'] as Map);
    final allowed = await prompt?.call(notice) ?? false;
    final token = await session.currentToken();
    _checkChoice(generation);
    if (!allowed) {
      // Not now defers an ungranted choice; it is NOT a withdrawal. There is
      // nothing to persist or wait for. A delayed denial must never revoke a
      // later grant from this or another device. Explicit withdrawal lives in
      // Privacy choices and still waits for the authoritative backend write.
      invalidate();
      throw ApiException(
        statusCode: 403,
        data: const {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
      );
    }
    final response = await _api.put(
      '/privacy/aws-sharing-permission',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'granted': allowed,
        'noticeVersion': notice['version'],
        'noticeHash': notice['hash'],
        'expectedRevision': result['revision'],
      },
    );
    session.check();
    _checkChoice(generation);
    if (response is! Map || response['granted'] != true) {
      invalidate();
      throw const FormatException('Could not confirm safety-check permission');
    }
    _grantedSession = session.revision;
  }

  Future<void> allow() async {
    invalidate();
    await ensure(await _headers());
  }

  Future<void> ensureCurrentUser() async => ensure(await _headers());

  Future<void> withdraw() async {
    final headers = await _headers();
    final session = RequestSession(headers);
    invalidate();
    await _api.put(
      '/privacy/aws-sharing-permission',
      headers: headers,
      body: {'granted': false},
    );
    session.check();
  }
}
