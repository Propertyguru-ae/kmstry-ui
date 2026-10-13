import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/owner_photo_preview.dart';

void main() {
  late PendingPublicMediaService service;
  setUp(() {
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());
  void add({
    PendingPublicMediaState state = PendingPublicMediaState.preparing,
    PendingPublicMediaKind kind = PendingPublicMediaKind.personalAvatar,
    String? venueId,
    String? message = 'Text policy',
  }) {
    service.track(
      PendingPublicMedia(
        id: 'draft',
        kind: kind,
        venueId: venueId,
        localPath: '/tmp/owner-photo-test-preview.jpg',
        isVideo: false,
        createdAt: DateTime.now(),
        state: state,
        hasServerReceipt: false,
        message: message,
      ),
    );
  }

  Widget screen({
    PendingPublicMediaKind kind = PendingPublicMediaKind.personalAvatar,
    String? venueId,
    bool isActive = true,
    bool hasPreviousPhoto = true,
    bool overlay = false,
  }) => MaterialApp(
    home: Scaffold(
      body: Column(
        children: [
          OwnerPhotoPreview(
            kind: kind,
            venueId: venueId,
            width: 80,
            height: 80,
            service: service,
            isActive: isActive,
            child: Text(hasPreviousPhoto ? 'Approved photo' : 'Default avatar'),
          ),
          OwnerPhotoUploadStatus(
            kind: kind,
            hasPreviousPhoto: hasPreviousPhoto,
            venueId: venueId,
            service: service,
            isActive: isActive,
            overlay: overlay,
          ),
        ],
      ),
    ),
  );

  for (final state in [
    PendingPublicMediaState.rejected,
    PendingPublicMediaState.underReview,
  ]) {
    testWidgets('$state cover feedback has a translucent dark backdrop', (
      tester,
    ) async {
      add(state: state);
      await tester.pumpWidget(screen(overlay: true));
      final backdrop = find.byKey(
        const ValueKey('owner-photo-status-backdrop'),
      );
      final container = tester.widget<Container>(backdrop);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, Colors.black.withValues(alpha: .6));
      expect(decoration.borderRadius, BorderRadius.circular(16));
      expect(
        find.descendant(
          of: backdrop,
          matching: find.textContaining('Text policy'),
        ),
        findsOneWidget,
      );
      if (state == PendingPublicMediaState.rejected) {
        await tester.tap(find.text('Dismiss'));
        await tester.pump();
        expect(backdrop, findsNothing);
      }
      await tester.pumpWidget(screen());
      expect(backdrop, findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'new photo is full colour without a modal or a moderation spinner',
    (tester) async {
      add();
      await tester.pumpWidget(screen());
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(ColorFiltered), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Updating photo'), findsOneWidget);
    },
  );

  for (final state in [
    PendingPublicMediaState.rejected,
    PendingPublicMediaState.failed,
  ]) {
    testWidgets(
      '$state returns to canonical photo with an inline reason, never an uploads popup',
      (tester) async {
        add(state: state);
        await tester.pumpWidget(screen());
        expect(find.text('Approved photo'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        await tester.tap(find.byType(OwnerPhotoUploadStatus));
        await tester.pumpAndSettle();
        expect(find.text('Photo update'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.textContaining('stories'), findsNothing);
        expect(find.textContaining('Text policy'), findsOneWidget);
        expect(find.text('Dismiss'), findsOneWidget);
        await tester.tap(find.text('Dismiss'));
        await tester.pump();
        expect(service.items, isEmpty);
        expect(find.text('Approved photo'), findsOneWidget);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.textContaining('Text policy'), findsNothing);
      },
    );
  }

  for (final kind in [
    PendingPublicMediaKind.personalAvatar,
    PendingPublicMediaKind.venueAvatar,
  ]) {
    final venueId = kind == PendingPublicMediaKind.venueAvatar ? 'alpha' : null;
    for (final state in [
      PendingPublicMediaState.rejected,
      PendingPublicMediaState.failed,
      PendingPublicMediaState.underReview,
      PendingPublicMediaState.delayed,
    ]) {
      for (final hasPreviousPhoto in [false, true]) {
        testWidgets(
          '$kind $state only mentions a previous canonical photo when one exists: $hasPreviousPhoto',
          (tester) async {
            add(kind: kind, venueId: venueId, state: state);
            await tester.pumpWidget(
              screen(
                kind: kind,
                venueId: venueId,
                hasPreviousPhoto: hasPreviousPhoto,
              ),
            );
            expect(
              find.textContaining('Your previous photo is still in use.'),
              hasPreviousPhoto ? findsOneWidget : findsNothing,
            );
            final terminal =
                state == PendingPublicMediaState.rejected ||
                state == PendingPublicMediaState.failed;
            expect(
              find.text('Dismiss'),
              terminal ? findsOneWidget : findsNothing,
            );
            if (state != PendingPublicMediaState.delayed) {
              expect(find.textContaining('Text policy'), findsOneWidget);
            }
            if (terminal) {
              await tester.tap(find.text('Dismiss'));
              await tester.pump();
              expect(service.items, isEmpty);
              expect(service.wasPublished('draft'), isFalse);
              expect(
                find.text(
                  hasPreviousPhoto ? 'Approved photo' : 'Default avatar',
                ),
                findsOneWidget,
              );
              expect(find.textContaining('Text policy'), findsNothing);
            } else {
              expect(service.items.single.state, state);
            }
          },
        );
      }
    }
    testWidgets('$kind uses a short fallback when no rejection reason exists', (
      tester,
    ) async {
      add(
        kind: kind,
        venueId: venueId,
        state: PendingPublicMediaState.rejected,
        message: null,
      );
      await tester.pumpWidget(screen(kind: kind, venueId: venueId));
      expect(
        find.text(
          'Your photo wasn’t updated. Please choose a photo. Your previous photo is still in use.',
        ),
        findsOneWidget,
      );
      await tester.pumpWidget(
        screen(kind: kind, venueId: venueId, hasPreviousPhoto: false),
      );
      expect(
        find.text('Your photo wasn’t updated. Please choose a photo.'),
        findsOneWidget,
      );
      expect(find.textContaining('previous photo'), findsNothing);
    });
    testWidgets(
      '$kind refreshes old rejection wording without losing its reason',
      (tester) async {
        for (final advice in [
          'Please remove the flagged content or choose a different file.',
          'Please choose a different photo or video.',
          'Please try uploading again or choose another file.',
        ]) {
          add(
            kind: kind,
            venueId: venueId,
            state: PendingPublicMediaState.rejected,
            message:
                'Text was flagged for profanity. It was not shared. $advice',
          );
          await tester.pumpWidget(screen(kind: kind, venueId: venueId));
          expect(
            find.textContaining('remove the flagged content'),
            findsNothing,
          );
          expect(find.textContaining('photo or video'), findsNothing);
          expect(
            find.textContaining('Text was flagged for profanity.'),
            findsOneWidget,
          );
          expect(find.textContaining('Please choose a photo.'), findsOneWidget);
        }
      },
    );
  }

  testWidgets('obsolete cancellation is not shown as a photo update failure', (
    tester,
  ) async {
    add(state: PendingPublicMediaState.cancelled);
    await tester.pumpWidget(screen());
    expect(find.text('Approved photo'), findsOneWidget);
    expect(find.text('Update cancelled'), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('normal photo update has no legacy popup on tap', (tester) async {
    add();
    await tester.pumpWidget(screen());
    await tester.tap(find.text('Updating photo'));
    await tester.pump();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Your uploads'), findsNothing);
  });

  testWidgets(
    'unresolved venue or another venue never displays the private preview',
    (tester) async {
      add(kind: PendingPublicMediaKind.venueAvatar, venueId: 'alpha');
      for (final id in [null, '', 'beta']) {
        await tester.pumpWidget(
          screen(kind: PendingPublicMediaKind.venueAvatar, venueId: id),
        );
        expect(find.text('Approved photo'), findsOneWidget);
        expect(find.byType(Image), findsNothing);
        expect(find.text('Updating photo'), findsNothing);
      }
      await tester.pumpWidget(screen());
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets('personal candidate never becomes a venue preview', (
    tester,
  ) async {
    add();
    await tester.pumpWidget(
      screen(kind: PendingPublicMediaKind.venueAvatar, venueId: 'alpha'),
    );
    expect(find.text('Approved photo'), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets(
    'publication hides status during handover, logout clears preview',
    (tester) async {
      add(state: PendingPublicMediaState.published);
      await tester.pumpWidget(screen());
      expect(find.text('Photo updated'), findsNothing);
      service.clear();
      await tester.pump();
      expect(find.text('Approved photo'), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    },
  );

  testWidgets(
    'a lost connection explains uncertainty without a false failure or replay',
    (tester) async {
      add(state: PendingPublicMediaState.connectionIssue);
      await tester.pumpWidget(screen());
      await tester.tap(find.text('Check photo update'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Please do not upload it again.'),
        findsOneWidget,
      );
      expect(find.text('Try again'), findsNothing);
    },
  );

  testWidgets(
    'hidden photo surfaces defer upload ticks and read latest status on return',
    (tester) async {
      add();
      await tester.pumpWidget(screen(isActive: false));
      expect(find.text('Updating photo'), findsOneWidget);
      expect(find.byType(ValueListenableBuilder<int>), findsNothing);

      service.failPreparedUpload(
        'draft',
        expectedGeneration: service.sessionGeneration,
        message: 'Preparation failed',
      );
      await tester.pump();
      expect(find.text('Updating photo'), findsOneWidget);
      expect(find.text('Photo not updated'), findsNothing);

      await tester.pumpWidget(screen());
      expect(find.text('Updating photo'), findsNothing);
      expect(find.text('Photo not updated'), findsOneWidget);
      expect(find.text('Approved photo'), findsOneWidget);
      expect(find.byType(ValueListenableBuilder<int>), findsNWidgets(2));
    },
  );
}
