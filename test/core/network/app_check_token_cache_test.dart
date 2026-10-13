import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/app_check_token_cache.dart';

String tokenUntil(DateTime expiry) =>
    'header.${base64Url.encode(utf8.encode(jsonEncode({'exp': expiry.millisecondsSinceEpoch ~/ 1000})))}.signature';

void main() {
  test(
    'parallel API/upload/socket calls share one SDK lookup and valid cache',
    () async {
      var now = DateTime.utc(2026, 10, 1);
      final sdk = Completer<String?>();
      var calls = 0;
      final cache = AppCheckTokenCache(
        now: () => now,
        loadToken: (_) {
          calls++;
          return sdk.future;
        },
      );
      final callsInFlight = List.generate(8, (_) => cache.getToken());
      final token = tokenUntil(now.add(const Duration(hours: 1)));
      sdk.complete(token);
      expect(await Future.wait(callsInFlight), List.filled(8, token));
      now = now.add(const Duration(minutes: 5));
      expect(await cache.getToken(), token);
      expect(calls, 1);
    },
  );

  test(
    'a stalled SDK is bounded and cooled down, never returns expired token',
    () async {
      var now = DateTime.utc(2026, 10, 1);
      var calls = 0;
      final sdk = Completer<String?>();
      final cache = AppCheckTokenCache(
        now: () => now,
        timeout: const Duration(milliseconds: 20),
        loadToken: (_) {
          calls++;
          return sdk.future;
        },
      );
      expect(await cache.getToken(), isNull);
      expect(await cache.getToken(), isNull);
      expect(calls, 1);
      sdk.complete(tokenUntil(now.subtract(const Duration(minutes: 1))));
      now = now.add(const Duration(seconds: 11));
      expect(await cache.getToken(), isNull);
      expect(calls, 2);
    },
  );

  test(
    'forced lookup bypasses cooldown and supersedes stale in-flight result',
    () async {
      final now = DateTime.utc(2026, 10, 1);
      final old = Completer<String?>();
      final fresh = Completer<String?>();
      final forced = <bool>[];
      final cache = AppCheckTokenCache(
        now: () => now,
        loadToken: (force) {
          forced.add(force);
          return force ? fresh.future : old.future;
        },
      );
      final first = cache.getToken();
      final refresh = cache.getToken(forceRefresh: true);
      final parallelRefresh = cache.getToken(forceRefresh: true);
      final newToken = tokenUntil(now.add(const Duration(hours: 2)));
      fresh.complete(newToken);
      expect(await refresh, newToken);
      expect(await parallelRefresh, newToken);
      old.complete(tokenUntil(now.add(const Duration(hours: 1))));
      expect(await first, isNull);
      expect(await cache.getToken(), newToken);
      expect(forced, [false, true]);
    },
  );

  test(
    'near-expiry token goes back to SDK and missing token is not trusted',
    () async {
      final now = DateTime.utc(2026, 10, 1);
      var calls = 0;
      final cache = AppCheckTokenCache(
        now: () => now,
        loadToken: (_) async {
          calls++;
          return calls == 1
              ? tokenUntil(now.add(const Duration(seconds: 20)))
              : null;
        },
      );
      expect(await cache.getToken(), isNotNull);
      expect(await cache.getToken(), isNull);
      expect(await cache.getToken(), isNull);
      expect(calls, 2);
    },
  );

  test(
    'backend rejection can force a fresh lookup despite SDK failure cooldown',
    () async {
      final now = DateTime.utc(2026, 10, 1);
      final token = tokenUntil(now.add(const Duration(hours: 1)));
      final cache = AppCheckTokenCache(
        now: () => now,
        loadToken: (force) async {
          if (!force) throw StateError('SDK warming up');
          return token;
        },
      );
      expect(await cache.getToken(), isNull);
      expect(await cache.getToken(forceRefresh: true), token);
    },
  );
}
