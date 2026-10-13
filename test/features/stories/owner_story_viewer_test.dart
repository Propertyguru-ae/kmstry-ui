import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_viewed_cache.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/stories/presentation/owner_story_upload.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';

PendingPublicMedia item(
  PendingPublicMediaState state, {
  bool venue = false,
  bool video = false,
  String id = 'draft',
  String venueId = 'venue',
  DateTime? createdAt,
}) => PendingPublicMedia(
  id: id,
  kind: venue
      ? PendingPublicMediaKind.venueStory
      : PendingPublicMediaKind.personalStory,
  venueId: venueId,
  localPath: '',
  isVideo: video,
  createdAt: createdAt ?? DateTime(2026),
  state: state,
  hasServerReceipt: false,
  message: state == PendingPublicMediaState.rejected
      ? 'Disallowed text in image.'
      : null,
  progress: state == PendingPublicMediaState.uploading ? .42 : null,
);

PendingPublicMediaService service({StoryUploadCanceller? cancelStory}) =>
    PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
      cancelStory: cancelStory,
    );

Future<void> openOwnerStories(
  WidgetTester tester,
  PendingPublicMediaService uploads, {
  bool venue = false,
  int initialIndex = 0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Profile'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => StoryViewerPage(
                  groups: const [
                    StoryGroup(
                      user: StoryUser(id: 'owner'),
                      stories: [],
                      isCurrentUserOwner: true,
                    ),
                  ],
                  ownerUploadKind: venue
                      ? PendingPublicMediaKind.venueStory
                      : PendingPublicMediaKind.personalStory,
                  ownerUploads: uploads,
                  venueId: venue ? 'venue' : null,
                  initialStoryIndex: initialIndex,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Profile'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final venue in [false, true]) {
    testWidgets(
      'background rejection waits until actually shown: venue=$venue',
      (tester) async {
        final decision = Completer<MediaModerationSnapshot>();
        final uploads = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) => decision.future,
          delay: (_) => Completer<void>().future,
        );
        uploads.track(
          item(
            PendingPublicMediaState.checking,
            venue: venue,
          ).withReceipt('server-story'),
        );
        await openOwnerStories(tester, uploads, venue: venue);
        final navigator = tester.state<NavigatorState>(find.byType(Navigator));
        unawaited(
          navigator.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('Other screen')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        decision.complete(
          const MediaModerationSnapshot(
            status: 'REJECTED',
            message: 'Disallowed text in image.',
          ),
        );
        await tester.pump();
        await tester.pump();
        // Leave without ever rendering the rejected Story in the foreground.
        navigator.pop();
        navigator.pop();
        await tester.pumpAndSettle();
        expect(find.text('Profile'), findsOneWidget);
        expect(
          uploads.byId('server-story')?.state,
          PendingPublicMediaState.rejected,
        );
        await tester.tap(find.text('Profile'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Disallowed text in image.'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(uploads.byId('server-story'), isNull);
        expect(find.byType(SnackBar), findsNothing);
        expect(tester.takeException(), isNull);
        uploads.clear();
      },
    );

    for (final exit in ['close', 'down', 'system back']) {
      testWidgets('viewed rejection leaves bubble on $exit: venue=$venue', (
        tester,
      ) async {
        var cancellations = 0;
        final uploads = service(cancelStory: (_) async => cancellations++);
        uploads.track(item(PendingPublicMediaState.rejected, venue: venue));
        await openOwnerStories(tester, uploads, venue: venue);
        await tester.pump(const Duration(seconds: 2));
        expect(find.text('Story not shared'), findsOneWidget);
        expect(find.text('Disallowed text in image.'), findsOneWidget);
        expect(find.text('Dismiss'), findsNothing);
        expect(find.byType(SnackBar), findsNothing);
        expect(uploads.byId('draft'), isNotNull);
        switch (exit) {
          case 'close':
            await tester.tap(find.byTooltip('Close'));
          case 'down':
            await tester.dragFrom(const Offset(400, 250), const Offset(0, 150));
          case 'system back':
            tester.state<NavigatorState>(find.byType(Navigator)).pop();
        }
        await tester.pumpAndSettle();
        expect(find.text('Profile'), findsOneWidget);
        expect(
          uploads.latest(
            venue
                ? PendingPublicMediaKind.venueStory
                : PendingPublicMediaKind.personalStory,
            venueId: venue ? 'venue' : null,
          ),
          isNull,
        );
        expect(cancellations, 0); // Only local presentation is acknowledged.
        expect(tester.takeException(), isNull);
        uploads.clear();
      });
    }

    testWidgets('next story clears only the viewed rejection: venue=$venue', (
      tester,
    ) async {
      final uploads = service();
      uploads.track(item(PendingPublicMediaState.rejected, venue: venue));
      uploads.track(
        item(
          PendingPublicMediaState.checking,
          venue: venue,
          id: 'new-story',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );
      // Creating a new story must not silently erase an unread rejection.
      expect(uploads.byId('draft'), isNotNull);
      await openOwnerStories(tester, uploads, venue: venue);
      expect(find.text('Story not shared'), findsOneWidget);
      await tester.tapAt(const Offset(650, 300));
      await tester.pump();
      expect(find.text('Sharing'), findsOneWidget);
      expect(uploads.byId('draft'), isNull);
      expect(uploads.byId('new-story'), isNotNull);
      await tester.tapAt(const Offset(50, 300));
      await tester.pump();
      expect(find.text('Story not shared'), findsNothing);
      expect(find.text('Sharing'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(uploads.byId('new-story'), isNotNull);
      uploads.clear();
    });

    testWidgets('going back clears a viewed rejection: venue=$venue', (
      tester,
    ) async {
      final uploads = service();
      uploads.track(item(PendingPublicMediaState.checking, venue: venue));
      uploads.track(
        item(
          PendingPublicMediaState.rejected,
          venue: venue,
          id: 'rejected-new',
          createdAt: DateTime(2026, 1, 1, 0, 0, 1),
        ),
      );
      await openOwnerStories(tester, uploads, venue: venue, initialIndex: 1);
      expect(find.text('Story not shared'), findsOneWidget);
      await tester.tapAt(const Offset(50, 300));
      await tester.pump();
      expect(find.text('Sharing'), findsOneWidget);
      expect(uploads.byId('rejected-new'), isNull);
      expect(uploads.byId('draft'), isNotNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      uploads.clear();
    });

    testWidgets(
      'closing another story preserves unread rejection: venue=$venue',
      (tester) async {
        final uploads = service();
        uploads.track(item(PendingPublicMediaState.checking, venue: venue));
        uploads.track(
          item(
            PendingPublicMediaState.rejected,
            venue: venue,
            id: 'unread-rejection',
            createdAt: DateTime(2026, 1, 1, 0, 0, 1),
          ),
        );
        await openOwnerStories(tester, uploads, venue: venue);
        expect(find.text('Sharing'), findsOneWidget);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(uploads.byId('unread-rejection'), isNotNull);
        expect(uploads.byId('draft'), isNotNull);
        expect(tester.takeException(), isNull);
        uploads.clear();
      },
    );
  }

  testWidgets(
    'approval while cancellation confirmation is open cannot advance or prevent cancellation',
    (tester) async {
      final decision = Completer<MediaModerationSnapshot>();
      var cancellations = 0;
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) => decision.future,
        delay: (_) => Completer<void>().future,
        cancelStory: (_) async {
          cancellations++;
        },
      );
      uploads.track(
        PendingPublicMedia(
          id: 'server-story',
          uploadId: 'upload-1-1',
          kind: PendingPublicMediaKind.personalStory,
          venueId: 'venue',
          checkinId: 'checkin',
          localPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Home'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerPage(
                      groups: const [
                        StoryGroup(
                          user: StoryUser(id: 'owner'),
                          stories: [],
                          isCurrentUserOwner: true,
                        ),
                      ],
                      ownerUploadKind: PendingPublicMediaKind.personalStory,
                      ownerUploads: uploads,
                      loadOwnerStories: () async => [
                        StoryItem(
                          id: 'server-story',
                          mediaUrl: '',
                          mediaType: 'photo',
                          createdAt: DateTime.now(),
                          expiresAt: DateTime.now().add(
                            const Duration(hours: 1),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('Cancel this upload?'), findsOneWidget);
      expect(find.byType(StoryViewerPage, skipOffstage: false), findsOneWidget);
      await tester.tap(find.text('Cancel upload'));
      await tester.pumpAndSettle();
      expect(cancellations, 1);
      expect(uploads.wasPublished('server-story'), false);
      expect(find.text('Home'), findsOneWidget);
      expect(find.byType(StoryViewerPage), findsNothing);
      expect(tester.takeException(), isNull);
      uploads.clear();
    },
  );

  for (final venue in [false, true]) {
    for (final state in [
      PendingPublicMediaState.failed,
      PendingPublicMediaState.rejected,
    ]) {
      testWidgets(
        'not-shared video clears automatically: $state / venue=$venue',
        (tester) async {
          final uploads = service();
          final draft = item(state, venue: venue, video: true);
          uploads.track(draft);
          await openOwnerStories(tester, uploads, venue: venue);
          expect(find.text('Story not shared'), findsOneWidget);
          expect(find.text('Dismiss'), findsNothing);
          await tester.pump(ownerStoryFeedbackDuration(draft));
          await tester.pumpAndSettle();
          expect(find.text('Profile'), findsOneWidget);
          expect(uploads.byId(draft.id), isNull);
          expect(tester.takeException(), isNull);
          uploads.clear();
        },
      );
    }

    testWidgets(
      'automatic feedback advances without losing the next upload: venue=$venue',
      (tester) async {
        final uploads = service();
        final rejected = item(
          PendingPublicMediaState.failed,
          venue: venue,
          video: true,
        );
        uploads.track(rejected);
        uploads.track(
          item(
            PendingPublicMediaState.checking,
            venue: venue,
            id: 'next-upload',
            createdAt: DateTime(2026, 1, 1, 0, 0, 1),
          ),
        );
        await openOwnerStories(tester, uploads, venue: venue);
        await tester.pump(ownerStoryFeedbackDuration(rejected));
        await tester.pump();
        expect(find.text('Sharing'), findsOneWidget);
        expect(uploads.byId('draft'), isNull);
        expect(uploads.byId('next-upload'), isNotNull);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        uploads.clear();
      },
    );

    testWidgets(
      'owner can cancel a pending story from its delete icon: venue=$venue',
      (tester) async {
        final confirmation = Completer<void>();
        PendingPublicMedia? cancelled;
        final uploads = service(
          cancelStory: (upload) {
            cancelled = upload;
            return confirmation.future;
          },
        );
        uploads.track(item(PendingPublicMediaState.uploading, venue: venue));
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  child: const Text('Home'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => StoryViewerPage(
                        groups: const [
                          StoryGroup(
                            user: StoryUser(id: 'owner'),
                            stories: [],
                            isCurrentUserOwner: true,
                          ),
                        ],
                        ownerUploadKind: venue
                            ? PendingPublicMediaKind.venueStory
                            : PendingPublicMediaKind.personalStory,
                        ownerUploads: uploads,
                        venueId: venue ? 'venue' : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Home'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.tap(find.byTooltip('Cancel upload'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Cancel this upload?'), findsOneWidget);
        await tester.tap(find.text('Cancel upload'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          cancelled?.kind,
          venue
              ? PendingPublicMediaKind.venueStory
              : PendingPublicMediaKind.personalStory,
        );
        expect(
          uploads.items,
          isNotEmpty,
        ); // Do not claim cancellation before acknowledgement.
        confirmation.complete();
        await tester.pumpAndSettle();
        expect(uploads.items, isEmpty);
        expect(find.text('Home'), findsOneWidget);
        expect(find.byType(StoryViewerPage), findsNothing);
        expect(tester.takeException(), isNull);
        uploads.clear();
      },
    );

    testWidgets(
      'owner story is full screen, private, no public actions: venue=$venue',
      (tester) async {
        final uploads = service();
        uploads.track(item(PendingPublicMediaState.checking, venue: venue));
        await tester.pumpWidget(
          MaterialApp(
            home: StoryViewerPage(
              groups: const [
                StoryGroup(
                  user: StoryUser(id: 'owner', fullName: 'You'),
                  stories: [],
                  isCurrentUserOwner: true,
                ),
              ],
              ownerUploadKind: venue
                  ? PendingPublicMediaKind.venueStory
                  : PendingPublicMediaKind.personalStory,
              ownerUploads: uploads,
              venueId: venue ? 'venue' : null,
              showViewers: true,
              canDelete: true,
              onCreateStory: () {},
            ),
          ),
        );
        await tester.pump();
        expect(find.text('Sharing'), findsOneWidget);
        expect(find.text('Your uploads'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byTooltip('Report'), findsNothing);
        expect(find.byTooltip('Delete'), findsNothing);
        expect(find.byTooltip('Cancel upload'), findsOneWidget);
        expect(find.byIcon(Icons.remove_red_eye_outlined), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.textContaining('Only you'), findsNothing);
        expect(await StoryViewedCache.loadAll(), isEmpty);
        await tester.pump(const Duration(minutes: 2));
        expect(find.text('Sharing'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        uploads.clear();
      },
    );
  }

  for (final state in [
    PendingPublicMediaState.rejected,
    PendingPublicMediaState.delayed,
    PendingPublicMediaState.underReview,
    PendingPublicMediaState.connectionIssue,
    PendingPublicMediaState.uploading,
  ]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('status fits narrow phone at $scale / $state', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(390, 844),
                textScaler: TextScaler.linear(scale),
              ),
              child: Scaffold(
                backgroundColor: Colors.black,
                body: Align(
                  alignment: Alignment.bottomCenter,
                  child: OwnerStoryUploadStatus(
                    item: item(state),
                    onCreateStory: () {},
                    onDismiss: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(
          find.byType(CircularProgressIndicator),
          state == PendingPublicMediaState.uploading
              ? findsOneWidget
              : findsNothing,
        );
        if (state == PendingPublicMediaState.rejected) {
          expect(find.text('Create new story'), findsOneWidget);
          expect(find.text('Disallowed text in image.'), findsOneWidget);
          expect(find.text('Try again'), findsNothing);
        }
        if (state == PendingPublicMediaState.uploading) {
          expect(
            tester
                .widget<LinearProgressIndicator>(
                  find.byType(LinearProgressIndicator),
                )
                .value,
            .42,
          );
        } else {
          expect(find.byType(LinearProgressIndicator), findsNothing);
        }
      });
    }
  }

  testWidgets(
    'rejection removes preview; closing returns to originating screen',
    (tester) async {
      final uploads = service();
      uploads.track(item(PendingPublicMediaState.rejected));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerPage(
                      groups: const [
                        StoryGroup(
                          user: StoryUser(id: 'owner'),
                          stories: [],
                          isCurrentUserOwner: true,
                        ),
                      ],
                      ownerUploadKind: PendingPublicMediaKind.personalStory,
                      ownerUploads: uploads,
                      onCreateStory: () {},
                    ),
                  ),
                ),
                child: const Text('Profile'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Profile'));
      // A rejected story now auto-advances once its explanation has been
      // readable. Inspect it before that timer completes, then close manually.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(PendingPublicMediaPreview), findsNothing);
      expect(find.text('Story not shared'), findsOneWidget);
      expect(find.text('Dismiss'), findsNothing);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(uploads.items, isEmpty);
      expect(tester.takeException(), isNull);
      uploads.clear();
    },
  );

  testWidgets('published story stays first, pending is the next story', (
    tester,
  ) async {
    final uploads = service();
    uploads.track(item(PendingPublicMediaState.checking));
    await tester.pumpWidget(
      MaterialApp(
        home: StoryViewerPage(
          groups: [
            StoryGroup(
              user: const StoryUser(id: 'owner'),
              isCurrentUserOwner: true,
              stories: [
                StoryItem(
                  id: 'public',
                  mediaUrl: '',
                  mediaType: 'photo',
                  createdAt: DateTime(2026),
                  expiresAt: DateTime(2030),
                ),
              ],
            ),
          ],
          ownerUploadKind: PendingPublicMediaKind.personalStory,
          ownerUploads: uploads,
        ),
      ),
    );
    expect(find.text('Sharing'), findsNothing);
    await tester.tapAt(const Offset(650, 300));
    await tester.pump();
    expect(find.text('Sharing'), findsOneWidget);
    await tester.tapAt(const Offset(50, 300));
    await tester.pump();
    expect(find.text('Sharing'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    uploads.clear();
  });

  testWidgets(
    'publication quietly replaces the current upload, not another story',
    (tester) async {
      final decision = Completer<MediaModerationSnapshot>();
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => true,
        moderationLookup: (_) => decision.future,
        delay: (_) => Completer<void>().future,
      );
      final canonical = Completer<List<StoryItem>>();
      StoryItem public(String id) => StoryItem(
        id: id,
        mediaUrl: '',
        mediaType: 'photo',
        createdAt: DateTime(2026),
        expiresAt: DateTime(2030),
        textOverlay: MediaTextOverlay(
          text: id,
          colorValue: 0xFFFFFFFF,
          fontSizeNorm: .07,
        ),
      );
      uploads.track(
        PendingPublicMedia(
          id: 'new',
          uploadId: 'local-new',
          kind: PendingPublicMediaKind.personalStory,
          venueId: null,
          localPath: '',
          isVideo: false,
          createdAt: DateTime(2026),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StoryViewerPage(
            groups: [
              StoryGroup(
                user: const StoryUser(id: 'me'),
                stories: [public('old')],
                isCurrentUserOwner: true,
              ),
            ],
            initialStoryIndex: 1,
            ownerUploadKind: PendingPublicMediaKind.personalStory,
            ownerUploads: uploads,
            loadOwnerStories: () => canonical.future,
          ),
        ),
      );
      expect(find.text('Sharing'), findsOneWidget);
      decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await tester.pump();
      expect(find.text('Sharing'), findsNothing);
      expect(find.byType(OwnerStoryUploadMedia), findsOneWidget);
      canonical.complete([public('old'), public('new')]);
      await tester.pump();
      await tester.pump(); // Render the frame scheduled by the async fetch.
      expect(find.byType(OwnerStoryUploadMedia), findsNothing);
      expect(find.text('new'), findsOneWidget);
      expect(find.text('old'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  testWidgets(
    'an open upload updates to rejection and new story starts after closing',
    (tester) async {
      final decision = Completer<MediaModerationSnapshot>();
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => decision.future,
        delay: (_) => Completer<void>().future,
      );
      uploads.track(
        PendingPublicMedia(
          id: 'new',
          kind: PendingPublicMediaKind.personalStory,
          venueId: null,
          localPath: '',
          isVideo: false,
          createdAt: DateTime(2026),
        ),
      );
      var createCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Profile'),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => StoryViewerPage(
                      groups: const [
                        StoryGroup(
                          user: StoryUser(id: 'me'),
                          stories: [],
                          isCurrentUserOwner: true,
                        ),
                      ],
                      ownerUploadKind: PendingPublicMediaKind.personalStory,
                      ownerUploads: uploads,
                      onCreateStory: () {
                        createCalls++;
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Profile'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Sharing'), findsOneWidget);
      decision.complete(
        const MediaModerationSnapshot(
          status: 'REJECTED',
          message: 'Disallowed text.',
        ),
      );
      await tester.pump();
      await tester
          .pump(); // Render the frame scheduled by the decision watcher.
      expect(find.byType(PendingPublicMediaPreview), findsNothing);
      expect(find.text('Disallowed text.'), findsOneWidget);
      await tester.tap(find.text('Create new story'));
      expect(createCalls, 0);
      await tester.pumpAndSettle();
      expect(createCalls, 1);
      expect(find.text('Profile'), findsOneWidget);
      expect(uploads.items, isEmpty);
      uploads.clear();
    },
  );

  testWidgets('logout closes an open owner preview immediately', (
    tester,
  ) async {
    final uploads = service();
    uploads.track(item(PendingPublicMediaState.checking));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              child: const Text('Home'),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StoryViewerPage(
                    groups: const [
                      StoryGroup(
                        user: StoryUser(id: 'me'),
                        stories: [],
                        isCurrentUserOwner: true,
                      ),
                    ],
                    ownerUploadKind: PendingPublicMediaKind.personalStory,
                    ownerUploads: uploads,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Home'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    uploads.clear();
    await tester.pump();
    expect(find.byType(OwnerStoryUploadMedia), findsNothing);
    await tester.pumpAndSettle();
    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
