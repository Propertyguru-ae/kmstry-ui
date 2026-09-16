import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';

/// Security and app metadata headers shared by JSON and multipart API calls.
///
/// Storage-provider presigned uploads intentionally do not use these headers;
/// App Check is verified by the API when the signed URL is created/confirmed.
class AppRequestHeaders {
  AppRequestHeaders._();

  static Map<String, String>? _metadataCache;

  static Future<Map<String, String>> build({String? accessToken}) async {
    return {
      if (accessToken != null && accessToken.isNotEmpty)
        'Authorization': 'Bearer $accessToken',
      ...await appCheck(),
      ...await appMetadata(),
    };
  }

  static Future<Map<String, String>> appCheck({
    bool forceRefresh = false,
  }) async {
    try {
      var token = await FirebaseAppCheck.instance.getToken(forceRefresh);
      if (!forceRefresh && (token == null || token.isEmpty)) {
        token = await FirebaseAppCheck.instance.getToken(true);
      }
      if (token != null && token.isNotEmpty) {
        return {'X-Firebase-AppCheck': token};
      }
    } catch (_) {
      // Keep monitor/off environments usable during App Check warm-up. In
      // enforce mode the backend remains the source of truth and rejects calls
      // that cannot present a valid token.
    }
    return const {};
  }

  static Future<Map<String, String>> appMetadata() async {
    final cached = _metadataCache;
    if (cached != null) return cached;

    try {
      final info = await PackageInfo.fromPlatform();
      final headers = <String, String>{
        if (AppConfig.buildEnv.isNotEmpty)
          'x-kmstry-build-env': AppConfig.buildEnv,
        if (info.version.isNotEmpty) 'x-kmstry-app-version': info.version,
        if (info.buildNumber.isNotEmpty)
          'x-kmstry-build-number': info.buildNumber,
        'x-kmstry-platform': Platform.operatingSystem,
        'x-kmstry-os-version': Platform.operatingSystemVersion,
      };
      _metadataCache = headers;
      return headers;
    } catch (_) {
      return {
        if (AppConfig.buildEnv.isNotEmpty)
          'x-kmstry-build-env': AppConfig.buildEnv,
      };
    }
  }
}
