import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../network/app_request_headers.dart';
import '../storage/secure_storage.dart';

/// Durable logout retries survive offline exit/restart. Only captured, old
/// session credentials are sent, including when another account has signed in.
class PushLogoutQueue {
  static Future<void>? _flight;

  static Future<void> retryPending({http.Client Function()? clientFactory}) =>
      _flight ??= _retry(clientFactory).whenComplete(() {
        _flight = null;
      });

  static Future<void> _retry(http.Client Function()? clientFactory) async {
    final pending = await SecureStorage.getPendingPushLogouts();
    for (final item in pending) {
      if (await revoke(item, client: clientFactory?.call())) {
        await SecureStorage.completePushLogout(item['refreshToken']!);
      }
    }
  }

  /// The captured credentials deliberately survive local logout/account change.
  static Future<bool> revoke(
    Map<String, String> item, {
    http.Client? client,
  }) async {
    final transport = client ?? http.Client();
    try {
      final response = await transport
          .post(
            Uri.parse('${item['apiOrigin']}/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              ...await AppRequestHeaders.appMetadata(),
              'x-kmstry-build-env': item['buildEnv']!,
            },
            body: jsonEncode({
              'refreshToken': item['refreshToken'],
              if (item['deviceToken']!.isNotEmpty)
                'deviceToken': item['deviceToken'],
            }),
          )
          .timeout(const Duration(seconds: 4));
      return response.statusCode == 401 ||
          (response.statusCode >= 200 &&
              response.statusCode < 300 &&
              (jsonDecode(response.body) as Map)['success'] == true);
    } catch (_) {
      // Keep the encrypted record for the next resume/startup. Do not log it.
      return false;
    } finally {
      transport.close();
    }
  }
}
