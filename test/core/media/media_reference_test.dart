import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';

void main() {
  group('MediaReference.fromJson', () {
    test('prefers signed media fields over a legacy URL', () {
      final reference = MediaReference.fromJson(
        {
          'media_id': 'media-1',
          'temporary_url': 'https://signed.example/media-1',
          'refresh_path': '/media/media-1/url',
          'url_expires_at': '2026-09-08T12:00:00.000Z',
          'url': 'https://legacy.example/media-1',
        },
        fallbackId: 'fallback',
        legacyUrlKeys: const ['url'],
      );

      expect(reference.mediaId, 'media-1');
      expect(reference.url, 'https://signed.example/media-1');
      expect(reference.refreshPath, '/media/media-1/url');
      expect(reference.expiresAt, DateTime.utc(2026, 9, 8, 12));
      expect(reference.canRefresh, isTrue);
    });

    test('keeps old API responses working through the legacy URL', () {
      final reference = MediaReference.fromJson(
        {'image_url': 'https://legacy.example/image.jpg'},
        fallbackId: 'message-1:image',
        legacyUrlKeys: const ['image_url'],
        idKey: 'image_media_id',
        temporaryUrlKey: 'image_temporary_url',
        refreshPathKey: 'image_refresh_path',
        expiresAtKey: 'image_url_expires_at',
      );

      expect(reference.mediaId, 'message-1:image');
      expect(reference.url, 'https://legacy.example/image.jpg');
      expect(reference.refreshPath, isNull);
      expect(reference.expiresAt, isNull);
      expect(reference.canRefresh, isFalse);
    });

    test(
      'treats blank refresh paths and malformed expiry values as absent',
      () {
        final reference = MediaReference.fromJson(
          {
            'media_id': 'media-2',
            'temporary_url': 'https://signed.example/media-2',
            'refresh_path': '   ',
            'url_expires_at': 'not-a-date',
          },
          fallbackId: 'fallback',
          legacyUrlKeys: const ['url'],
        );

        expect(reference.refreshPath, isNull);
        expect(reference.expiresAt, isNull);
        expect(reference.canRefresh, isFalse);
      },
    );
  });
}
