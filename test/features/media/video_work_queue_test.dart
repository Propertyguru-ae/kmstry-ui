import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/media/video_work_queue.dart';

void main() {
  test(
    'native encodes serialize while each future keeps its own result',
    () async {
      final queue = VideoWorkQueue(cleanup: () async {});
      final first = Completer<int>();
      final order = <int>[];
      final a = queue.run(() {
        order.add(1);
        return first.future;
      });
      final b = queue.run(() async {
        order.add(2);
        return 2;
      });
      await Future<void>.delayed(Duration.zero);
      expect(order, [1]);
      first.complete(1);
      expect(await a, 1);
      expect(await b, 2);
      expect(order, [1, 2]);
    },
  );

  test('one failed encode cannot poison the queue', () async {
    final queue = VideoWorkQueue(cleanup: () async {});
    final a = queue.run(() async => throw StateError('codec'));
    final b = queue.run(() async => 'ok');
    await expectLater(a, throwsStateError);
    expect(await b, 'ok');
  });

  test(
    'cleanup is deferred until every in-flight file lease is released',
    () async {
      var cleaned = 0;
      final queue = VideoWorkQueue(
        cleanup: () async {
          cleaned++;
        },
      );
      final releaseGallery = queue.retainFiles();
      final releaseStory = queue.retainFiles();
      await queue.cleanup();
      expect(cleaned, 0);
      releaseGallery();
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, 0);
      releaseGallery(); // Releasing twice cannot invalidate another upload.
      releaseStory();
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, 1);
    },
  );

  test('cleanup failure neither escapes nor prevents later work', () async {
    final queue = VideoWorkQueue(
      cleanup: () async => throw StateError('cache'),
    );
    await queue.cleanup();
    expect(await queue.run(() async => 42), 42);
  });
}
