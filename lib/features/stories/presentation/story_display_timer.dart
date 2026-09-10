import 'dart:async';

/// Content lifetime, independent of Flutter tickers and platform animation
/// preferences. Pausing preserves the remaining viewing time.
class StoryDisplayTimer {
  StoryDisplayTimer({
    required this.duration,
    required this.onComplete,
    Duration Function()? elapsedClock,
  }) {
    final stopwatch = Stopwatch()..start();
    _now = elapsedClock ?? (() => stopwatch.elapsed);
  }

  final Duration duration;
  final void Function() onComplete;
  late final Duration Function() _now;
  Timer? _timer;
  Duration _remaining = Duration.zero;
  Duration? _startedAt;
  bool _started = false;
  bool _finished = false;
  bool _disposed = false;

  void resume() {
    if (_disposed || _finished || _timer != null) return;
    if (!_started) {
      _remaining = duration;
      _started = true;
    }
    _startedAt = _now();
    _timer = Timer(_remaining, () {
      _timer = null;
      if (_disposed || _finished) return;
      _finished = true;
      onComplete();
    });
  }

  void pause() {
    if (_timer == null || _disposed) return;
    _timer!.cancel();
    _timer = null;
    final remaining = _remaining - (_now() - _startedAt!);
    _remaining = remaining.isNegative ? Duration.zero : remaining;
    _startedAt = null;
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}
