import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/media/media_network_url.dart';

void main() {
  group('resolveMediaNetworkUrl', () {
    test('re-homes a KMSTRY Places proxy onto the active API origin', () {
      final result = resolveMediaNetworkUrl(
        'http://localhost:3000/venues/places/photo/opaque.token?maxWidth=256',
      );

      expect(
        result,
        '${AppConfig.baseUrl}/venues/places/photo/opaque.token?maxWidth=256',
      );
    });

    test('keeps Spaces and other external media URLs unchanged', () {
      const url =
          'https://kmstry-preprod-media.fra1.digitaloceanspaces.com/venue-photos/example.jpg';

      expect(resolveMediaNetworkUrl(url), url);
    });

    test('recognizes only the signed Google photo proxy route', () {
      expect(
        isGooglePlacePhotoProxyUrl(
          'https://api.kmstry.net/venues/places/photo/opaque.token',
        ),
        isTrue,
      );
      expect(
        isGooglePlacePhotoProxyUrl(
          'https://example.com/venue-photos/example.jpg',
        ),
        isFalse,
      );
    });
  });
}
