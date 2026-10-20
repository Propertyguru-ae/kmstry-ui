import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

PendingPublicMedia item(String id, {bool receipt = true}) => PendingPublicMedia(
  id: id,
  uploadId: 'upload-$id',
  kind: PendingPublicMediaKind.checkinMoment,
  venueId: 'venue',
  checkinId: 'checkin',
  localPath: '',
  isVideo: false,
  createdAt: DateTime.now(),
  state: PendingPublicMediaState.underReview,
  hasServerReceipt: receipt,
);

void main() {
  late PendingPublicMediaService uploads;
  late Completer<MediaModerationSnapshot> decision;
  late Completer<bool> deletion;
  setUp(() {
    decision = Completer<MediaModerationSnapshot>();
    deletion = Completer<bool>();
    uploads = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => true,
      moderationLookup: (_) => decision.future,
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => uploads.clear());

  Future<bool> cancel(PendingPublicMedia pending) => uploads.cancelMoment(
    pending,
    expectedGeneration: uploads.sessionGeneration,
    cancel: (_) => deletion.future,
  );

  test(
    'late moderation approval cannot publish an upload being cancelled',
    () async {
      final pending = item('second');
      uploads.track(pending);
      uploads.track(item('unrelated', receipt: false));
      final result = cancel(pending);
      decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await Future<void>.delayed(Duration.zero);
      expect(uploads.wasPublished('second'), false);
      expect(uploads.byId('second'), isNotNull);
      deletion.complete(false);
      expect(await result, false);
      expect(uploads.byId('second'), isNull);
      expect(uploads.byId('unrelated'), isNotNull);
      expect(uploads.wasPublished('upload-second'), false);
    },
  );
  test('failed cancellation keeps the receipt and permits retry', () async {
    final pending = item('second');
    uploads.track(pending);
    final result = cancel(pending);
    final assertion = expectLater(result, throwsStateError);
    deletion.completeError(StateError('offline'));
    await assertion;
    expect(uploads.byId('second'), isNotNull);
    deletion = Completer<bool>()..complete(false);
    expect(await cancel(pending), false);
    expect(uploads.byId('second'), isNull);
  });
  test('double cancellation never sends a second DELETE', () async {
    final pending = item('second');
    uploads.track(pending);
    final result = cancel(pending);
    var duplicateCalls = 0;
    await expectLater(
      uploads.cancelMoment(
        pending,
        expectedGeneration: uploads.sessionGeneration,
        cancel: (_) async {
          duplicateCalls++;
          return false;
        },
      ),
      throwsStateError,
    );
    expect(duplicateCalls, 0);
    deletion.complete(false);
    await result;
  });
  test(
    'stale cancellation leaves a new session with the same receipt ID alone',
    () async {
      final pending = item('second');
      uploads.track(pending);
      final result = cancel(pending);
      final assertion = expectLater(result, throwsStateError);
      uploads.clear();
      uploads.track(pending);
      deletion.complete(false);
      await assertion;
      expect(uploads.byId('second'), isNotNull);
      deletion = Completer<bool>()..complete(false);
      expect(await cancel(pending), false);
    },
  );
  test(
    'a local draft cannot be silently dismissed as a server cancellation',
    () async {
      final pending = item('second', receipt: false);
      uploads.track(pending);
      await expectLater(cancel(pending), throwsStateError);
      expect(uploads.byId('second'), isNotNull);
    },
  );
}
