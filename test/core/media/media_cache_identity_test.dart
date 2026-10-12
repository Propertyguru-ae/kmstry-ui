import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/media/media_cache_identity.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/media/signed_media_resolver.dart';

void main() {
  test(
    'signature rotation keeps the same avatar bytes cache, new photo does not',
    () {
      for (final id in ['user:profile', 'venue:venue-photo']) {
        final first = mediaCacheIdentity(
          'https://media.example/one.jpg?X-Amz-Signature=1',
          mediaId: id,
        );
        expect(
          mediaCacheIdentity(
            'https://media.example/one.jpg?X-Amz-Signature=2',
            mediaId: id,
          ),
          first,
        );
        expect(
          mediaCacheIdentity(
            'https://media.example/two.jpg?X-Amz-Signature=2',
            mediaId: id,
          ),
          isNot(first),
        );
      }
    },
  );
  test('ordinary immutable media IDs keep their existing cache contract', () {
    expect(
      mediaCacheIdentity('https://media.example/file', mediaId: 'story-1'),
      'story-1',
    );
    expect(mediaCacheIdentity('https://media.example/file'), isNull);
  });
  test(
    'refreshed old photo cannot override a newly published object',
    () async {
      final resolver = SignedMediaResolver(
        transport: (_) async => {
          'media_id': 'u:profile',
          'temporary_url': 'https://media.example/old.jpg?sig=2',
        },
      );
      const old = MediaReference(
        mediaId: 'u:profile',
        url: 'https://media.example/old.jpg?sig=1',
        refreshPath: '/users/u/photo-url',
      );
      await resolver.refreshOnce(old);
      expect(resolver.current(old).url, 'https://media.example/old.jpg?sig=2');
      const next = MediaReference(
        mediaId: 'u:profile',
        url: 'https://media.example/new.jpg?sig=3',
      );
      expect(resolver.current(next).url, next.url);
    },
  );
}
