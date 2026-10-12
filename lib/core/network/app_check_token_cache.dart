import 'dart:async';
import 'dart:convert';

/// Share SDK token work across uploads, JSON calls and socket handshakes.
/// A missing token never grants access: the backend still enforces App Check.
class AppCheckTokenCache {
  AppCheckTokenCache({
    required this.loadToken,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final Future<String?> Function(bool forceRefresh) loadToken;
  final DateTime Function() _now;
  final Duration timeout;
  final Duration retryDelay;
  String? _token;
  DateTime? _expiresAt;
  DateTime? _retryAt;
  Future<String?>? _inFlight;
  bool _forcing = false;
  int _generation = 0;

  Future<String?> getToken({bool forceRefresh = false}) {
    final now = _now();
    if (!forceRefresh &&
        _token != null &&
        _expiresAt != null &&
        now.add(const Duration(seconds: 60)).isBefore(_expiresAt!)) {
      return Future.value(_token);
    }
    if (_inFlight != null && (!forceRefresh || _forcing)) return _inFlight!;
    if (!forceRefresh && _retryAt != null && now.isBefore(_retryAt!)) {
      return Future.value(null);
    }
    // A backend rejection must not replay the same cached token. A forced
    // request also supersedes any older, slow SDK lookup.
    _token = null;
    _expiresAt = null;
    _forcing = forceRefresh;
    final generation = ++_generation;
    final request = _load(forceRefresh, generation);
    _inFlight = request;
    return request;
  }

  Future<String?> _load(bool forceRefresh, int generation) async {
    try {
      final token = await Future.sync(
        () => loadToken(forceRefresh),
      ).timeout(timeout);
      if (generation != _generation) return null;
      if (token == null || token.isEmpty) {
        _retryAt = _now().add(retryDelay);
        return null;
      }
      _retryAt = null;
      // Decode only to schedule refresh, never to trust or verify a token.
      // Unknown formats are passed to the server but not cached here.
      final expiry = jwtExpiry(token);
      if (expiry != null && !expiry.isAfter(_now())) {
        _retryAt = _now().add(retryDelay);
        return null;
      }
      _token = token;
      _expiresAt = expiry;
      return token;
    } catch (_) {
      if (generation == _generation) _retryAt = _now().add(retryDelay);
      return null;
    } finally {
      if (generation == _generation) {
        _inFlight = null;
        _forcing = false;
      }
    }
  }
}

/// Client-side refresh hint only; authentication always happens on the server.
DateTime? jwtExpiry(String token) {
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(token.split('.')[1]))),
    );
    final exp = payload is Map ? payload['exp'] : null;
    return exp is num
        ? DateTime.fromMillisecondsSinceEpoch((exp * 1000).toInt(), isUtc: true)
        : null;
  } catch (_) {
    return null;
  }
}
