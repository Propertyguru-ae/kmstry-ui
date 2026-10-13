import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/event_gallery_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PendingPublicMediaService service;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'TEST_NO_NETWORK'),
        );
    VenueSession.instance.clear();
    await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() {
    service.clear();
    VenueSession.instance.clear();
  });

  testWidgets(
    'tapping opens a swipeable viewer with a counter; pending pages show their status',
    (tester) async {
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.library == 'image resource service') return;
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      service.track(
        PendingPublicMedia(
          id: 'review',
          kind: PendingPublicMediaKind.eventPhoto,
          venueId: 'venue-a',
          eventId: 'event-a',
          localPath: 'assets/images/kmstrylogo.png',
          isVideo: false,
          createdAt: DateTime.now(),
          state: PendingPublicMediaState.underReview,
          hasServerReceipt: true,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: EventGalleryViewer(
            photos: const ['https://example.invalid/published.jpg'],
            venueId: 'venue-a',
            eventId: 'event-a',
            service: service,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MediaViewerCounterPill), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.text('Under review'), findsNothing);

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.text('Under review'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
