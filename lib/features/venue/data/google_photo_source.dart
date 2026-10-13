import 'package:kmstry_frontend/core/media/media_network_url.dart';

Uri? safeGooglePhotoLink(Object? value, {bool avatar = false}) {
  if (value is! String || value.length > 8192) return null;
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.userInfo.isNotEmpty ||
      (uri.hasPort && uri.port != 443)) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (RegExp(
    r'^/(?:url|imgres)(?:/|$)',
    caseSensitive: false,
  ).hasMatch(uri.path)) {
    return null;
  }
  final allowed = avatar
      ? host == 'googleusercontent.com' ||
            host.endsWith('.googleusercontent.com')
      : host == 'google.com' ||
            host.endsWith('.google.com') ||
            host == 'maps.app.goo.gl';
  return allowed ? uri : null;
}

class GooglePhotoAuthor {
  const GooglePhotoAuthor({required this.name, this.profileUrl, this.photoUrl});
  final String name;
  final Uri? profileUrl;
  final Uri? photoUrl;

  factory GooglePhotoAuthor.fromJson(Map<String, dynamic> json) =>
      GooglePhotoAuthor(
        name: (json['name'] as String?)?.trim() ?? 'Photo contributor',
        profileUrl: safeGooglePhotoLink(json['profileUrl']),
        photoUrl: safeGooglePhotoLink(json['photoUrl'], avatar: true),
      );
}

class GooglePhotoSource {
  const GooglePhotoSource({
    required this.photoUrl,
    required this.authors,
    required this.sourceUrl,
    required this.reportUrl,
    required this.reportIsDirect,
  });

  final String photoUrl;
  final List<GooglePhotoAuthor> authors;
  final Uri sourceUrl;
  final Uri reportUrl;
  final bool reportIsDirect;

  factory GooglePhotoSource.fromJson(Map<String, dynamic> json) {
    final photo = (json['photoUrl'] as String?) ?? '';
    final source = safeGooglePhotoLink(json['sourceUrl']);
    final report = safeGooglePhotoLink(json['reportUrl']);
    if (json['provider'] != 'GOOGLE_MAPS' ||
        !isGooglePlacePhotoProxyUrl(photo) ||
        source == null ||
        report == null) {
      throw const FormatException('Invalid Google photo source');
    }
    return GooglePhotoSource(
      photoUrl: resolveMediaNetworkUrl(photo),
      authors: (json['authors'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (entry) =>
                GooglePhotoAuthor.fromJson(Map<String, dynamic>.from(entry)),
          )
          .toList(growable: false),
      sourceUrl: source,
      reportUrl: report,
      reportIsDirect: json['reportIsDirect'] == true,
    );
  }
}

String googlePhotoSourcePath(String photoUrl) {
  final uri = Uri.tryParse(photoUrl.trim());
  final segments = uri?.pathSegments;
  if (segments == null ||
      segments.length != 4 ||
      segments[0] != 'venues' ||
      segments[1] != 'places' ||
      segments[2] != 'photo' ||
      !RegExp(r'^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$').hasMatch(segments[3])) {
    throw const FormatException('Invalid Google photo URL');
  }
  // Always use this build's API, never issue a request to a URL from the photo.
  return '/venues/places/photo/${Uri.encodeComponent(segments[3])}/source';
}
