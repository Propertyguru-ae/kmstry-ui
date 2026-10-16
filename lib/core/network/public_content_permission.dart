import 'package:kmstry_frontend/core/storage/secure_storage.dart';

/// Shared by JSON and multipart writes. Private messages, reports, deletion,
/// account settings, login and read-only requests are deliberately excluded.
class PublicContentPermission {
  static Future<void> Function(Map<String, String> headers)? onRequired;
  static void Function()? onServerDenied;

  /// UI preflight before dismissing an editor/starting a background transfer.
  /// Uses the same configured guard as JSON and multipart requests. The server
  /// remains authoritative even if the UI guard is not installed.
  static Future<void> beforePublicSubmit() async {
    final guard = onRequired;
    if (guard == null) return;
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    await guard({'Authorization': 'Bearer $token'});
  }

  static bool requiresPermission(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) {
    if (!const {'POST', 'PATCH', 'PUT'}.contains(method.toUpperCase())) {
      return false;
    }
    final p = Uri.parse(path).path.replaceFirst(RegExp(r'/$'), '');
    if (method.toUpperCase() == 'POST' &&
        [
          r'^/users/me/photo$',
          r'^/checkins(?:/pending)?$',
          r'^/checkins/[^/]+/(?:photos|avatar|stories|media(?:/upload-url|/confirm)?)$',
          r'^/venues/[^/]+/(?:photo|gallery|venue-stories|offers/photo)$',
          r'^/venues/[^/]+/events/(?:recurring/)?[^/]+/photos$',
          r'^/users/me/personal-profile$',
          r'^/venues/claim$',
        ].any((pattern) => RegExp(pattern).hasMatch(p))) {
      return true;
    }
    if (p == '/users/me') {
      return const [
        'full_name',
        'bio',
        'photo_url',
        'photo_object_key',
      ].any((key) => body?[key] != null);
    }
    if (method.toUpperCase() == 'PATCH' &&
        RegExp(r'^/venues/[^/]+$').hasMatch(p)) {
      return const [
        'name',
        'description',
        'photo_url',
        'photo_object_key',
      ].any((key) => body?[key] != null);
    }
    return [
      r'^/checkins/[^/]+/vibe$',
      r'^/venues/[^/]+/(?:events|offers|staff|menu|partnerships)(?:/[^/]+)?$',
      r'^/venues/[^/]+/notify-nearby$',
      r'^/venues/[^/]+/events/[^/]+/(?:offer|partnerships)$',
    ].any((pattern) => RegExp(pattern).hasMatch(p));
  }

  static Future<void> beforeRequest(
    String method,
    String path,
    Map<String, String>? headers, [
    Map<String, dynamic>? body,
  ]) async {
    if (requiresPermission(method, path, body) && headers != null) {
      await onRequired?.call(headers);
    }
  }
}
