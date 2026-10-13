import '../config/app_config.dart';

const String _googlePlacePhotoProxyPath = '/venues/places/photo/';

/// Resolves KMSTRY-owned API proxy URLs against the API origin baked into the
/// current app build. This deliberately applies only to the signed Google
/// Places photo route; Spaces/CDN and all other external URLs remain untouched.
///
/// Local development can expose the backend to a physical device through a
/// LAN address while the server itself advertises `localhost`. Re-homing this
/// opaque, HMAC-signed proxy path prevents that server-side origin detail from
/// breaking map pins and venue cards. It also keeps staging and pre-prod media
/// requests on their own API origin.
String resolveMediaNetworkUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.path.startsWith(_googlePlacePhotoProxyPath)) {
    return trimmed;
  }

  final apiOrigin = Uri.tryParse(AppConfig.baseUrl);
  if (apiOrigin == null || !apiOrigin.hasScheme || apiOrigin.host.isEmpty) {
    return trimmed;
  }

  return apiOrigin
      .replace(
        path: uri.path,
        query: uri.hasQuery ? uri.query : null,
        fragment: null,
      )
      .toString();
}

bool isGooglePlacePhotoProxyUrl(String rawUrl) {
  final uri = Uri.tryParse(rawUrl.trim());
  return uri != null && uri.path.startsWith(_googlePlacePhotoProxyPath);
}
