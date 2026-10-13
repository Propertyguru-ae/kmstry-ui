import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/event_photo_uploads.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PendingPublicMediaService service;
  setUp(() async {
    // Venue context is local; do not access a real backend for permission setup.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'TEST_NO_NETWORK'),
        );
    VenueSession.instance.clear();
    await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() {
    service.clear();
    VenueSession.instance.clear();
  });
  void add(
    String id, {
    String? eventId = 'event-a',
    String? ruleId,
    PendingPublicMediaState state = PendingPublicMediaState.preparing,
    bool receipt = false,
  }) {
    service.track(
      PendingPublicMedia(
        id: id,
        kind: PendingPublicMediaKind.eventPhoto,
        venueId: 'venue-a',
        eventId: eventId,
        recurringRuleId: ruleId,
        localPath: 'assets/images/kmstrylogo.png',
        isVideo: false,
        createdAt: DateTime.now(),
        state: state,
        hasServerReceipt: receipt,
        message: 'This photo did not meet our content policy.',
      ),
    );
  }

  Widget screen({
    String eventId = 'event-a',
    String? ruleId,
    bool compact = false,
    bool published = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          SizedBox(
            width: 300,
            height: 180,
            child: EventPhotoUploadCover(
              venueId: 'venue-a',
              eventId: eventId,
              recurringRuleId: ruleId,
              hasPublishedPhoto: published,
              service: service,
              child: const Text('Canonical cover'),
            ),
          ),
          EventPhotoUploads(
            venueId: 'venue-a',
            eventId: eventId,
            recurringRuleId: ruleId,
            compact: compact,
            service: service,
          ),
        ],
      ),
    ),
  );

  testWidgets(
    'owner sees a colourful preview and small Sharing spinner, not an automatic popup',
    (tester) async {
      add('one');
      await tester.pumpWidget(screen());
      expect(find.byType(PendingPublicMediaPreview), findsNWidgets(2));
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('preview follows a recurring series but not another event', (
    tester,
  ) async {
    add('series', eventId: null, ruleId: 'series-a');
    await tester.pumpWidget(
      screen(eventId: 'occurrence-a', ruleId: 'series-a'),
    );
    expect(find.text('Sharing'), findsOneWidget);
    await tester.pumpWidget(screen(eventId: 'event-other'));
    expect(find.text('Sharing'), findsNothing);
    expect(find.text('Canonical cover'), findsOneWidget);
  });
  testWidgets(
    'switching venue context or clearing login hides owner previews immediately',
    (tester) async {
      add('one');
      await tester.pumpWidget(screen());
      expect(find.text('Sharing'), findsOneWidget);
      await VenueSession.instance.load('venue-other', VenueMemberRole.owner);
      await tester.pump();
      expect(find.text('Sharing'), findsNothing);
      await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
      await tester.pump();
      expect(find.text('Sharing'), findsOneWidget);
      service.clear();
      await tester.pump();
      expect(find.text('Sharing'), findsNothing);
    },
  );
  testWidgets(
    'rejection hides pixels, leaves the approved cover and explains why on tap',
    (tester) async {
      add('one', state: PendingPublicMediaState.rejected);
      await tester.pumpWidget(screen(published: true));
      expect(find.text('Canonical cover'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      expect(find.text('Not shared'), findsOneWidget);
      await tester.tap(find.text('Not shared'));
      await tester.pumpAndSettle();
      expect(find.text('Event photos'), findsOneWidget);
      expect(
        find.text('This photo did not meet our content policy.'),
        findsOneWidget,
      );
      expect(find.byType(Image), findsNothing);
    },
  );
  testWidgets(
    'compact list indicator is stable during review and has no infinite spinner',
    (tester) async {
      add('one', state: PendingPublicMediaState.underReview);
      await tester.pumpWidget(screen(compact: true));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Under review'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  for (final state in [
    PendingPublicMediaState.underReview,
    PendingPublicMediaState.rejected,
  ]) {
    testWidgets(
      '$state offers confirmed photo removal for all series occurrences',
      (tester) async {
        var removals = 0;
        service.clear();
        service = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
          delay: (_) => Completer<void>().future,
          removeEventPhoto: (_, _) async => removals++,
        );
        add(
          'series',
          eventId: null,
          ruleId: 'series-a',
          state: state,
          receipt: true,
        );
        await tester.pumpWidget(
          screen(eventId: 'occurrence-a', ruleId: 'series-a', compact: true),
        );
        await tester.tap(
          find.text(
            state == PendingPublicMediaState.underReview
                ? 'Under review'
                : 'Not shared',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Remove photo'), findsOneWidget);
        expect(find.text('Dismiss'), findsNothing);
        await tester.ensureVisible(find.text('Remove photo'));
        await tester.tap(find.text('Remove photo'));
        await tester.pumpAndSettle();
        expect(find.text('Remove photo from all events?'), findsOneWidget);
        expect(
          find.textContaining('every event in this recurring series'),
          findsOneWidget,
        );
        expect(removals, 0);
        await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
        await tester.pumpAndSettle();
        expect(removals, 1);
        expect(service.items, isEmpty);
        expect(find.text('No pending event photo uploads.'), findsOneWidget);
      },
    );
  }

  testWidgets(
    'cancelling the removal confirmation keeps the photo under review',
    (tester) async {
      var removals = 0;
      service.clear();
      service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        removeEventPhoto: (_, _) async => removals++,
      );
      add('one', state: PendingPublicMediaState.underReview, receipt: true);
      await tester.pumpWidget(screen(compact: true));
      await tester.tap(find.text('Under review'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove photo'));
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(find.text('Remove photo?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(removals, 0);
      expect(service.items, hasLength(1));
    },
  );

  testWidgets(
    'failed removal shows a useful inline error and retains the review',
    (tester) async {
      service.clear();
      service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        removeEventPhoto: (_, _) async => throw StateError('offline'),
      );
      add('one', state: PendingPublicMediaState.underReview, receipt: true);
      await tester.pumpWidget(screen(compact: true));
      await tester.tap(find.text('Under review'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Remove photo'));
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove photo'));
      await tester.pumpAndSettle();
      expect(
        find.text('Could not remove this photo. Please try again.'),
        findsOneWidget,
      );
      expect(service.items, hasLength(1));
    },
  );
}
