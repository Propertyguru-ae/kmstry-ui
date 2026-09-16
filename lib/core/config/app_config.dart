import 'package:flutter/foundation.dart';

class AppConfig {
  static const String buildEnv = String.fromEnvironment('BUILD_ENV');
  static const String _definedApiUrl = String.fromEnvironment('API_URL');
  static const String _definedSiteUrl = String.fromEnvironment('SITE_URL');

  // Release identities stay the same across tracks. The environment is part of
  // the artifact, so reject a mismatched API/site pair at AOT compile time.
  // Production is deliberately absent until its final origins are approved.
  static const bool _releaseOriginsMatchEnvironment =
      (buildEnv == 'staging' &&
          _definedApiUrl == 'https://api.kmstry.net' &&
          _definedSiteUrl == 'https://staging.kmstry.net') ||
      (buildEnv == 'pre-prod' &&
          _definedApiUrl == 'https://pre-prod-api.kmstry.net' &&
          _definedSiteUrl == 'https://pre-prod.kmstry.net');

  static const String baseUrl = _definedApiUrl != ''
      ? _definedApiUrl
      : 'http://192.168.1.190:3000';

  /// Public marketing/legal site (privacy, terms, support, invite landing).
  /// Distinct from [baseUrl] which is the API host.
  static const String siteBaseUrl = _definedSiteUrl != ''
      ? _definedSiteUrl
      : 'https://staging.kmstry.net';

  // A constant-evaluation failure makes missing release defines stop the AOT
  // compilation before an IPA/AAB can be produced. Assertions cannot be used
  // here because Dart removes them from release builds.
  static const int _releaseApiUrlMustBeProvided =
      !kReleaseMode || _definedApiUrl != '' ? 1 : 1 ~/ 0;
  static const int _releaseSiteUrlMustBeProvided =
      !kReleaseMode || _definedSiteUrl != '' ? 1 : 1 ~/ 0;
  static const int _releaseBuildEnvMustBeProvided =
      !kReleaseMode || buildEnv != '' ? 1 : 1 ~/ 0;
  static const int _releaseOriginsMustMatchEnvironment =
      !kReleaseMode || _releaseOriginsMatchEnvironment ? 1 : 1 ~/ 0;

  static void validateForStartup() {
    // Force compile-time evaluation of the required-define constants above.
    if (_releaseApiUrlMustBeProvided +
            _releaseSiteUrlMustBeProvided +
            _releaseBuildEnvMustBeProvided +
            _releaseOriginsMustMatchEnvironment !=
        4) {
      throw StateError('Invalid release URL configuration.');
    }
    if (!kReleaseMode) return;
    _validateReleaseUrl(_definedApiUrl, 'API_URL');
    _validateReleaseUrl(_definedSiteUrl, 'SITE_URL');
  }

  static void _validateReleaseUrl(String value, String name) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        uri.hasQuery ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw StateError(
        '$name must be an HTTPS origin without credentials, query, fragment, or path.',
      );
    }

    final host = uri.host.toLowerCase();
    if (_isLocalOrPlaceholderHost(host)) {
      throw StateError(
        '$name cannot use a local, private, or placeholder host.',
      );
    }
  }

  static bool _isLocalOrPlaceholderHost(String host) {
    if (host == 'localhost' ||
        host == '0.0.0.0' ||
        host == '::1' ||
        host.endsWith('.local') ||
        host == 'example.com' ||
        host.endsWith('.example.com') ||
        host.contains('placeholder') ||
        host.contains('replace-me')) {
      return true;
    }

    final parts = host.split('.');
    if (parts.length != 4) return false;
    final octets = parts.map(int.tryParse).toList(growable: false);
    if (octets.any((part) => part == null || part < 0 || part > 255)) {
      return false;
    }
    final first = octets[0]!;
    final second = octets[1]!;
    return first == 10 ||
        first == 127 ||
        (first == 169 && second == 254) ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }
}
