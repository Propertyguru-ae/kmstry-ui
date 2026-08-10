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

  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');

    _log('🌐 [HTTP] POST $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');
    _log('🌐 [HTTP] body = ${_truncate(body)}');

    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

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

    _log('🌐 [HTTP] GET $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');

    try {
      final response = await _client
          .get(url, headers: {'Content-Type': 'application/json', ...?headers})
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

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

    _log('🌐 [HTTP] PATCH $url');
    _log('🌐 [HTTP] headers = ${_truncate(headers)}');
    _log('🌐 [HTTP] body = ${_truncate(body)}');

    try {
      final response = await _client
          .patch(
            url,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

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

    _log('🌐 [HTTP] DELETE $url');

    try {
      final response = await _client
          .delete(url, headers: {'Content-Type': 'application/json', ...?headers})
          .timeout(const Duration(seconds: 10));

      _log('🌐 [HTTP] statusCode = ${response.statusCode}');
      _log('🌐 [HTTP] raw response = ${_truncate(response.body)}');

      if (response.body.isEmpty) {
        return null;
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
      _log('❌ [HTTP] DELETE error: $e');
      rethrow;
    }
  }
}
