import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'api_exception.dart';

class ApiClient {
  final http.Client _client = http.Client();

   Future<dynamic>post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');

    print('🌐 [HTTP] POST $url');
    print('🌐 [HTTP] headers = $headers');
    print('🌐 [HTTP] body = $body');

    try {
      final response = await _client
          .post(
            url,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 10));

      print('🌐 [HTTP] statusCode = ${response.statusCode}');
      print('🌐 [HTTP] raw response = ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }

      return data;
    } on SocketException catch (e) {
      print('❌ [HTTP] SocketException: $e');
      rethrow;
    } on TimeoutException catch (e) {
      print('⏱️ [HTTP] TimeoutException: $e');
      rethrow;
    } catch (e) {
      print('❌ [HTTP] Unknown error: $e');
      rethrow;
    }
  }

  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');

    print('🌐 [HTTP] GET $url');
    print('🌐 [HTTP] headers = $headers');

    try {
      final response = await _client
          .get(url, headers: {'Content-Type': 'application/json', ...?headers})
          .timeout(const Duration(seconds: 10));

      print('🌐 [HTTP] statusCode = ${response.statusCode}');
      print('🌐 [HTTP] raw response = ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }

      return data;
    } catch (e) {
      print('❌ [HTTP] GET error: $e');
      rethrow;
    }
  }

   Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    final url = Uri.parse('${AppConfig.baseUrl}$path');

    print('🌐 [HTTP] PATCH $url');
    print('🌐 [HTTP] headers = $headers');
    print('🌐 [HTTP] body = $body');

    try {
      final response = await _client
          .patch(
            url,
            headers: {'Content-Type': 'application/json', ...?headers},
            body: jsonEncode(body ?? {}),
          )
          .timeout(const Duration(seconds: 10));

      print('🌐 [HTTP] statusCode = ${response.statusCode}');
      print('🌐 [HTTP] raw response = ${response.body}');

      final data = jsonDecode(response.body);

      if (response.statusCode >= 400) {
        throw ApiException(statusCode: response.statusCode, data: data);
      }

      return data;
    } on SocketException catch (e) {
      print('❌ [HTTP] SocketException: $e');
      rethrow;
    } on TimeoutException catch (e) {
      print('⏱️ [HTTP] TimeoutException: $e');
      rethrow;
    } catch (e) {
      print('❌ [HTTP] Unknown error: $e');
      rethrow;
    }
  }
}
