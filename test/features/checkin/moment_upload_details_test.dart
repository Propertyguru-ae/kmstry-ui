import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';

void main() {
  late PendingPublicMediaService service;
  setUp(
    () => service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    ),
  );
  tearDown(() => service.clear());
  PendingPublicMedia item(
    String id,
    String checkin, {
    PendingPublicMediaState state = PendingPublicMediaState.checking,
  }) => PendingPublicMedia(
    id: id,
    kind: PendingPublicMediaKind.checkinMoment,
    venueId: 'alpha',
    checkinId: checkin,
    localPath: '/tmp/moment-test.jpg',
    isVideo: false,
    createdAt: DateTime.now(),
    state: state,
    hasServerReceipt: false,
    message: 'reason-$id',
  );
  testWidgets('Moment preview is full colour with a quiet Sharing label', (
    tester,
  ) async {
    final pending = item('m', 'c');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 132,
            height: 176,
            child: Stack(
              children: [
                Positioned.fill(
                  child: PendingPublicMediaPreview(item: pending),
                ),
                PublicMediaUploadStatus(item: pending),
              ],
            ),
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Sharing'), findsOneWidget);
    expect(find.byType(ColoredBox), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
  testWidgets(
    'details explain long waits and isolate another check-in at same venue',
    (tester) async {
      final pending = item(
        'current',
        'c',
        state: PendingPublicMediaState.delayed,
      );
      service.track(pending);
      service.track(
        item('old', 'old-c', state: PendingPublicMediaState.rejected),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PublicMediaUploadDetails(item: pending, service: service),
          ),
        ),
      );
      expect(find.text('Your Moments'), findsOneWidget);
      expect(find.textContaining('not visible to others yet'), findsOneWidget);
      expect(find.text('reason-old'), findsNothing);
      expect(find.textContaining('stories'), findsNothing);
    },
  );
  testWidgets('rejected Moment loses image but retains safe reason and retry', (
    tester,
  ) async {
    final pending = item(
      'rejected',
      'c',
      state: PendingPublicMediaState.rejected,
    );
    service.track(pending);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PublicMediaUploadDetails(
            item: pending,
            service: service,
            onRetake: () {},
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('reason-rejected'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
