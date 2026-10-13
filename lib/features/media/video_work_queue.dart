import 'dart:async';

/// The native encoder handles one job at a time. File leases prevent global
/// cache cleanup from deleting another route's in-flight video upload.
class VideoWorkQueue {
  VideoWorkQueue({required Future<void> Function() cleanup})
    : _cleanup = cleanup;
  final Future<void> Function() _cleanup;
  Future<void> _tail = Future.value();
  int _fileUsers = 0;
  bool _cleanupRequested = false;

  Future<T> run<T>(Future<T> Function() work) {
    final result = _tail.then((_) => work());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void Function() retainFiles() {
    _fileUsers++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _fileUsers--;
      if (_fileUsers == 0 && _cleanupRequested) unawaited(cleanup());
    };
  }

  Future<void> cleanup() {
    _cleanupRequested = true;
    return run(() async {
      if (_fileUsers > 0 || !_cleanupRequested) return;
      _cleanupRequested = false;
      // Cleanup is best effort, never an upload failure or unhandled future.
      try {
        await _cleanup();
      } catch (_) {}
    });
  }
}
