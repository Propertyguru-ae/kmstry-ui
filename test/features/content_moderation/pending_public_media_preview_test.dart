import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';

void main() {
  for (final kind in PendingPublicMediaKind.values) {
    for (final state in [
      PendingPublicMediaState.underReview,
      PendingPublicMediaState.rejected,
    ]) {
      testWidgets('$kind $state shows the specific server explanation', (
        tester,
      ) async {
        final service = PendingPublicMediaService.forTest(
          publishedLookup: (_) => Completer<bool>().future,
          moderationLookup: (_) async => MediaModerationSnapshot(
            status: state == PendingPublicMediaState.underReview
                ? 'NEEDS_REVIEW'
                : 'REJECTED',
            message: 'Text in this upload was flagged for contact information.',
          ),
          delay: (_) => Completer<void>().future,
        );
        addTearDown(service.clear);
        final item = PendingPublicMedia(
          id: 'test-upload',
          kind: kind,
          venueId: 'venue-1',
          localPath: '',
          isVideo: true,
          createdAt: DateTime(2026, 10, 5),
          state: state,
          message: 'Text in this upload was flagged for contact information.',
        );
        service.track(item);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PublicMediaUploadDetails(item: item, service: service),
            ),
          ),
        );
        expect(
          find.textContaining(
            'Text in this upload was flagged for contact information.',
          ),
          findsOneWidget,
        );
        if (item.isAvatar) {
          expect(
            find.text(
              'Text in this upload was flagged for contact information.',
            ),
            findsOneWidget,
          );
          // Generic upload details have no canonical-photo context. Never
          // claim a previous photo exists; owner surfaces supply that context.
          expect(find.textContaining('previous photo'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('rejected media never displays its local image', (tester) async {
    final rejected = PendingPublicMedia(
      id: 'rejected-1',
      kind: PendingPublicMediaKind.venueGallery,
      venueId: 'venue-1',
      localPath: '/tmp/rejected-image.jpg',
      isVideo: false,
      createdAt: DateTime(2026, 9, 30),
      state: PendingPublicMediaState.rejected,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 100,
            height: 100,
            child: PendingPublicMediaPreview(item: rejected),
          ),
        ),
      ),
    );

    expect(find.byType(Image), findsNothing);
    expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
  });
}
