import 'dart:io';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import 'app_check_token_cache.dart';

/// Security and app metadata headers shared by JSON and multipart API calls.
///
/// Storage-provider presigned uploads intentionally do not use these headers;
/// App Check is verified by the API when the signed URL is created/confirmed.
class AppRequestHeaders {
  AppRequestHeaders._();

  static Map<String, String>? _metadataCache;
  static final _appCheckTokens = AppCheckTokenCache(
    loadToken: (forceRefresh) =>
        FirebaseAppCheck.instance.getToken(forceRefresh),
  );

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
    final token = await _appCheckTokens.getToken(forceRefresh: forceRefresh);
    if (token != null) return {'X-Firebase-AppCheck': token};
    // Bounded warm-up never disables the server's enforce policy. ApiClient
    // retries an App Check 401 with one forced lookup, without logging out.
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
