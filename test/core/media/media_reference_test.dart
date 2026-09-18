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

  group('MediaReference.profilePhoto', () {
    test('uses the backend profile-photo contract', () {
      final reference = MediaReference.profilePhoto({
        'id': 'user-1',
        'photo': 'https://legacy.example/profile.jpg',
        'photo_media_id': 'user-1:profile',
        'photo_temporary_url': 'https://signed.example/profile.jpg',
        'photo_refresh_path': '/users/user-1/photo-url',
        'photo_url_expires_at': '2026-09-17T12:00:00.000Z',
      });

      expect(reference.mediaId, 'user-1:profile');
      expect(reference.url, 'https://signed.example/profile.jpg');
      expect(reference.refreshPath, '/users/user-1/photo-url');
      expect(reference.expiresAt, DateTime.utc(2026, 9, 17, 12));
      expect(reference.canRefresh, isTrue);
    });

    test('synthesizes a stable id and refresh path for legacy responses', () {
      final reference = MediaReference.profilePhoto({
        'photo': 'https://legacy.example/profile.jpg',
      }, userId: 'legacy-user');

      expect(reference.mediaId, 'legacy-user:profile');
      expect(reference.url, 'https://legacy.example/profile.jpg');
      expect(reference.refreshPath, '/users/legacy-user/photo-url');
      expect(reference.canRefresh, isTrue);
    });

    test('does not invent refresh credentials without a user id', () {
      final reference = MediaReference.profilePhoto({
        'photo': 'https://legacy.example/profile.jpg',
      });

      expect(reference.mediaId, isEmpty);
      expect(reference.refreshPath, isNull);
      expect(reference.canRefresh, isFalse);
    });
  });

  group('MediaReference.venuePhoto', () {
    test('uses the signed venue cover contract', () {
      final reference = MediaReference.venuePhoto(
        {
          'photo': 'https://legacy.example/venue.jpg',
          'photo_media_id': 'venue-1:venue-photo',
          'photo_temporary_url': 'https://signed.example/venue.jpg',
          'photo_refresh_path': '/venues/venue-1/photo-url',
          'photo_url_expires_at': '2026-09-17T12:00:00.000Z',
        },
        venueId: 'venue-1',
        allowRefresh: true,
      );

      expect(reference.mediaId, 'venue-1:venue-photo');
      expect(reference.url, 'https://signed.example/venue.jpg');
      expect(reference.refreshPath, '/venues/venue-1/photo-url');
      expect(reference.canRefresh, isTrue);
    });

    test('does not invent a KMSTRY refresh path for Google-only venues', () {
      final reference = MediaReference.venuePhoto(
        {'photo': 'https://maps.googleapis.com/place/photo?ref=1'},
        venueId: 'google-place-1',
        allowRefresh: false,
      );

      expect(reference.mediaId, 'google-place-1:venue-photo');
      expect(reference.refreshPath, isNull);
      expect(reference.canRefresh, isFalse);
    });
  });
}
