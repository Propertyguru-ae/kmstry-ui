import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/media/signed_media_resolver.dart';

void main() {
  const original = MediaReference(
    mediaId: 'media-1',
    url: 'https://signed.example/old',
    refreshPath: '/media/media-1/url',
  );

  test('refreshes and caches a temporary URL by stable media ID', () async {
    var calls = 0;
    final resolver = SignedMediaResolver(
      transport: (path) async {
        calls++;
        expect(path, original.refreshPath);
        return {
          'media_id': original.mediaId,
          'temporary_url': 'https://signed.example/new',
          'url_expires_at': '2099-01-01T00:00:00.000Z',
        };
      },
    );

    final refreshed = await resolver.refreshOnce(original);

    expect(calls, 1);
    expect(refreshed?.url, 'https://signed.example/new');
    expect(resolver.current(original).url, 'https://signed.example/new');
  });

  test('deduplicates concurrent refreshes for the same media ID', () async {
    var calls = 0;
    final response = Completer<Map<String, dynamic>>();
    final resolver = SignedMediaResolver(
      transport: (_) {
        calls++;
        return response.future;
      },
    );

    final first = resolver.refreshOnce(original);
    final second = resolver.refreshOnce(original);
    response.complete({
      'media_id': original.mediaId,
      'temporary_url': 'https://signed.example/shared',
    });

    final results = await Future.wait([first, second]);
    expect(calls, 1);
    expect(results.map((value) => value?.url), {
      'https://signed.example/shared',
    });
  });

  test('fails closed when refresh fails or returns no temporary URL', () async {
    final throwing = SignedMediaResolver(
      transport: (_) async => throw StateError('network failure'),
    );
    final empty = SignedMediaResolver(transport: (_) async => const {});

    expect(await throwing.refreshOnce(original), isNull);
    expect(await empty.refreshOnce(original), isNull);
    expect(throwing.current(original).url, original.url);
  });

  test('does not call the transport without a refresh path', () async {
    var called = false;
    final resolver = SignedMediaResolver(
      transport: (_) async {
        called = true;
        return const {};
      },
    );

    final result = await resolver.refreshOnce(
      const MediaReference(mediaId: 'legacy', url: 'https://legacy.example'),
    );

    expect(result, isNull);
    expect(called, isFalse);
  });
}
