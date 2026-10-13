import 'dart:async';

/// A page-local read gate, not a shared response or authorization cache.
/// Keeps visible data while refreshing, coalesces concurrent reads and defers
/// dirty hidden sections until they are visible again. No polling timer.
class VisibleVenueRead {
  VisibleVenueRead({
    required this.read,
    required this.isVisible,
    DateTime Function()? now,
    this.freshFor = const Duration(seconds: 10),
  }) : _now = now ?? DateTime.now;

  final Future<bool> Function() read;
  final bool Function() isVisible;
  final Duration freshFor;
  final DateTime Function() _now;
  DateTime? _lastSuccess;
  bool _dirty = true;
  bool _disposed = false;
  int _epoch = 0;
  Future<void>? _work;

  bool get needsRefresh =>
      _dirty ||
      _lastSuccess == null ||
      _now().difference(_lastSuccess!) >= freshFor;

  Future<void> activate() => _flush();

  void markDirty() => _dirty = true;

  Future<void> invalidate() {
    _dirty = true;
    return _flush();
  }

  Future<void> _flush() {
    if (_disposed || !isVisible()) return Future.value();
    if (_work != null) return _work!;
    if (!needsRefresh) return Future.value();
    final epoch = _epoch;
    final done = Completer<void>();
    _work = done.future;
    unawaited(() async {
      try {
        do {
          _dirty = false;
          bool success;
          try {
            success = await read();
          } catch (_) {
            success = false;
          }
          if (_disposed || epoch != _epoch) return;
          if (!success) {
            // Retry only on another activation/change/manual refresh. Never
            // spin on an AWS, network or authorization failure.
            _dirty = true;
            return;
          }
          _lastSuccess = _now();
        } while (_dirty && isVisible() && !_disposed);
      } finally {
        if (epoch == _epoch) _work = null;
        done.complete();
      }
    }());
    return done.future;
  }

  void reset() {
    _epoch++;
    _lastSuccess = null;
    _dirty = true;
    _work = null;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
