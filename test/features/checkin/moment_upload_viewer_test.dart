import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/stories/presentation/owner_story_upload.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

class _Repo extends CheckinRepository {
  final response = Completer<CheckinProfile>();
  final calls = <String>[];
  final cancellations = <String>[];
  final cancelled = Completer<bool>();
  Future<bool> Function()? cancelResult;
  bool Function()? sessionGuard;
  @override
  Future<bool> cancelMomentUpload({
    required String mediaId,
    required String checkinId,
    required bool Function() isCurrentSession,
  }) {
    cancellations.add('$checkinId:$mediaId');
    sessionGuard = isCurrentSession;
    return cancelResult?.call() ?? cancelled.future;
  }

  @override
  Future<CheckinProfile> getCheckinProfile(String id) {
    calls.add(id);
    return response.future;
  }
}

PendingPublicMedia _item({
  PendingPublicMediaState state = PendingPublicMediaState.checking,
  bool receipt = false,
}) => PendingPublicMedia(
  id: 'moment',
  uploadId: 'local-moment',
  kind: PendingPublicMediaKind.checkinMoment,
  checkinId: 'checkin',
  venueId: 'venue',
  localPath: '',
  isVideo: false,
  createdAt: DateTime.now(),
  hasServerReceipt: receipt,
  state: state,
  message: state == PendingPublicMediaState.rejected
      ? 'Disallowed text in image.'
      : null,
);

PendingPublicMediaService _service({
  Completer<MediaModerationSnapshot>? decision,
}) => PendingPublicMediaService.forTest(
  publishedLookup: (_) async => true,
  moderationLookup: (_) =>
      decision?.future ?? Completer<MediaModerationSnapshot>().future,
  delay: (_) => Completer<void>().future,
);

CheckinProfile _profile() => CheckinProfile.fromJson({
  'checkin': {'id': 'checkin', 'venueId': 'venue'},
  'user': {'id': 'me'},
  'media': [
    {'id': 'other', 'url': '', 'media_type': 'photo'},
    {'id': 'moment', 'url': '', 'media_type': 'photo'},
  ],
});

Future<void> _open(
  WidgetTester tester,
  PendingPublicMediaService service,
  _Repo repo, {
  String checkinId = 'checkin',
  VoidCallback? create,
  List<CheckinProfileMedia> media = const [],
  String? pendingId = 'local-moment',
  int initialIndex = 0,
  bool allowFeature = true,
  void Function(String, bool)? onDeleted,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Profile'),
            onPressed: () => Navigator.push(
              context,
              momentsViewerRoute(
                builder: (_) => MomentsViewerPage(
                  media: media,
                  initialIndex: initialIndex,
                  allowFeature: allowFeature,
                  checkinId: checkinId,
                  pendingUploadId: pendingId,
                  uploads: service,
                  repository: repo,
                  onCreateMoment: create,
                  onDeleted: onDeleted,
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
  setUp(() => ActiveCheckinService().clear());
  tearDown(() => ActiveCheckinService().clear());

  Future<void> confirmCancellation(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Cancel upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel upload'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  for (final openPending in [true, false]) {
    testWidgets(
      'cancel second Moment from ${openPending ? 'profile pending card' : 'existing check-in Moments'} preserves first and check-in',
      (tester) async {
        final uploads = _service();
        final repo = _Repo();
        final deleted = <String>[];
        uploads.track(
          _item(receipt: true, state: PendingPublicMediaState.underReview),
        );
        ActiveCheckinService().setActiveCheckin('checkin');
        final published = _profile().media
            .where((m) => m.id == 'other')
            .toList();
        await _open(
          tester,
          uploads,
          repo,
          media: published,
          pendingId: openPending ? 'local-moment' : null,
          onDeleted: (id, inactive) => deleted.add('$id:$inactive'),
        );
        if (!openPending) {
          await tester.drag(find.byType(PageView), const Offset(-700, 0));
          await tester.pumpAndSettle();
        }
        final cancel = find.byTooltip('Cancel upload');
        final close = find.byTooltip('Close');
        expect(
          tester.getCenter(cancel).dx,
          lessThan(tester.getCenter(close).dx),
        );
        expect(tester.getCenter(cancel).dy, tester.getCenter(close).dy);
        expect(find.byIcon(Icons.star_border_rounded), findsNothing);
        await confirmCancellation(tester);
        expect(repo.cancellations, ['checkin:moment']);
        expect(uploads.byId('moment'), isNotNull);
        expect(deleted, isEmpty);
        // Repeated taps cannot send another DELETE.
        await tester.tap(find.byTooltip('Cancel upload'));
        await tester.pump();
        expect(repo.cancellations, hasLength(1));
        repo.cancelled.complete(false);
        await tester.pumpAndSettle();
        expect(uploads.byId('moment'), isNull);
        expect(deleted, ['moment:false']);
        expect(ActiveCheckinService().activeCheckinId, 'checkin');
        expect(find.text('1 / 1'), findsOneWidget);
        expect(find.byTooltip('Cancel upload'), findsNothing);
        expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
        expect(find.byType(OwnerStoryUploadMedia), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        uploads.clear();
      },
    );
  }

  testWidgets('Keep sharing and X do not cancel a reviewed Moment', (
    tester,
  ) async {
    final uploads = _service();
    final repo = _Repo();
    uploads.track(
      _item(receipt: true, state: PendingPublicMediaState.underReview),
    );
    await _open(tester, uploads, repo);
    await tester.tap(find.byTooltip('Cancel upload'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep sharing'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(repo.cancellations, isEmpty);
    expect(uploads.byId('moment'), isNotNull);
    uploads.clear();
  });

  testWidgets(
    'logout during cancel confirmation closes the private viewer without DELETE',
    (tester) async {
      final uploads = _service();
      final repo = _Repo();
      uploads.track(
        _item(receipt: true, state: PendingPublicMediaState.underReview),
      );
      await _open(tester, uploads, repo);
      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pumpAndSettle();
      uploads.clear();
      await tester.pumpAndSettle();
      expect(find.byType(MomentsViewerPage), findsNothing);
      expect(find.text('Cancel this upload?'), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(repo.cancellations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed cancellation keeps the preview and can be retried', (
    tester,
  ) async {
    final uploads = _service();
    final repo = _Repo()
      ..cancelResult = () async => throw StateError('offline');
    uploads.track(
      _item(receipt: true, state: PendingPublicMediaState.underReview),
    );
    await _open(tester, uploads, repo);
    await confirmCancellation(tester);
    await tester.pumpAndSettle();
    expect(find.text('Could not cancel upload'), findsOneWidget);
    expect(uploads.byId('moment'), isNotNull);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    repo.cancelResult = () async => true;
    await confirmCancellation(tester);
    await tester.pumpAndSettle();
    expect(repo.cancellations, hasLength(2));
    expect(uploads.byId('moment'), isNull);
    expect(find.text('Profile'), findsOneWidget);
    uploads.clear();
  });

  testWidgets(
    'approval during confirmation cannot escape exact Moment cancellation',
    (tester) async {
      final decision = Completer<MediaModerationSnapshot>();
      final uploads = _service(decision: decision);
      final repo = _Repo();
      final deleted = <String>[];
      uploads.track(
        _item(receipt: true, state: PendingPublicMediaState.underReview),
      );
      await _open(
        tester,
        uploads,
        repo,
        media: _profile().media.where((m) => m.id == 'other').toList(),
        onDeleted: (id, _) => deleted.add(id),
      );
      await tester.tap(find.byTooltip('Cancel upload'));
      await tester.pumpAndSettle();
      decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, ['checkin']);
      await tester.tap(find.text('Cancel upload'));
      await tester.pump();
      repo.cancelled.complete(false);
      await tester.pumpAndSettle();
      // A fetch started by approval returns the old pre-deletion snapshot.
      repo.response.complete(_profile());
      await tester.pumpAndSettle();
      expect(deleted, ['moment']);
      expect(uploads.wasPublished('moment'), false);
      expect(uploads.wasPublished('local-moment'), false);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.byType(OwnerStoryUploadMedia), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  for (final changeSession in [false, true]) {
    testWidgets(
      'pending cancellation after closing viewer; session changed=$changeSession',
      (tester) async {
        final uploads = _service();
        final repo = _Repo();
        final deleted = <String>[];
        uploads.track(
          _item(receipt: true, state: PendingPublicMediaState.underReview),
        );
        ActiveCheckinService().setActiveCheckin('checkin');
        await _open(
          tester,
          uploads,
          repo,
          onDeleted: (id, _) => deleted.add(id),
        );
        await confirmCancellation(tester);
        await tester.tap(find.byTooltip('Close'));
        await tester.pumpAndSettle();
        if (changeSession) {
          uploads.clear();
          uploads.track(
            _item(receipt: true, state: PendingPublicMediaState.underReview),
          );
          ActiveCheckinService().setActiveCheckin('new-checkin');
        }
        repo.cancelled.complete(true);
        await tester.pumpAndSettle();
        expect(deleted, changeSession ? isEmpty : ['moment']);
        expect(repo.sessionGuard!(), !changeSession);
        expect(uploads.byId('moment') != null, changeSession);
        expect(
          ActiveCheckinService().activeCheckinId,
          changeSession ? 'new-checkin' : null,
        );
        expect(tester.takeException(), isNull);
        uploads.clear();
      },
    );
  }

  testWidgets('Close button sits on the same line as the "1 / N" counter '
      'below a notch, with no story-style progress bars', (tester) async {
    // iPhone gibi çentikli ekran: üstte 59px güvenli alan.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    tester.view.padding = const FakeViewPadding(top: 59);
    addTearDown(tester.view.reset);

    final uploads = _service();
    await _open(
      tester,
      uploads,
      _Repo(),
      media: _profile().media,
      pendingId: null,
    );

    final title = find.byType(MediaViewerCounterPill);
    final close = find.byTooltip('Close');
    expect(title, findsOneWidget);
    expect(find.textContaining('Your Moment'), findsNothing);
    expect(close, findsOneWidget);
    expect(
      tester.getCenter(close).dy,
      closeTo(tester.getCenter(title).dy, 1),
      reason: 'X must be vertically aligned with the counter',
    );
    // Çentiğin altında kalmalı.
    expect(tester.getTopLeft(close).dy, greaterThanOrEqualTo(59));
    // Story görüntüleyicisiyle aynı ortak buton ve aynı konum: güvenli
    // alanın 38px altında, sağdan 12px.
    final closeButton = find.byType(MediaViewerCloseButton);
    expect(closeButton, findsOneWidget);
    expect(tester.getTopLeft(closeButton).dy, closeTo(59 + 38, 0.5));
    expect(390 - tester.getTopRight(closeButton).dx, closeTo(12, 0.5));
    uploads.clear();
  });

  testWidgets('Moment visibly follows a downward drag before being released', (
    tester,
  ) async {
    final uploads = _service();
    await _open(
      tester,
      uploads,
      _Repo(),
      media: _profile().media,
      pendingId: null,
    );
    final route = ModalRoute.of(
      tester.element(find.byType(MomentsViewerPage)),
    )!;
    expect(route.opaque, false);
    final surface = find.byKey(const ValueKey('moment-drag-surface'));
    final content = find.byType(PageView);
    final origin = tester.getTopLeft(content);
    final gesture = await tester.startGesture(tester.getCenter(surface));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 120));
    await tester.pump();
    expect(tester.getTopLeft(content).dy, greaterThan(origin.dy + 90));
    expect(find.byType(MomentsViewerPage), findsOneWidget);
    final backdrop = tester.widget<ColoredBox>(
      find.byKey(const ValueKey('moment-dismiss-background')),
    );
    expect(backdrop.color.a, lessThan(1));
    // Crossing the threshold must not remove the page until release.
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MomentsViewerPage), findsOneWidget);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MomentsViewerPage), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
    uploads.clear();
  });

  testWidgets(
    'an incomplete drag smoothly returns the Moment to its position',
    (tester) async {
      final uploads = _service();
      await _open(
        tester,
        uploads,
        _Repo(),
        media: _profile().media,
        pendingId: null,
      );
      final surface = find.byKey(const ValueKey('moment-drag-surface'));
      final content = find.byType(PageView);
      final origin = tester.getTopLeft(content);
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump(const Duration(milliseconds: 200));
      await gesture.moveBy(const Offset(0, 30));
      await tester.pump(const Duration(milliseconds: 200));
      final draggedY = tester.getTopLeft(content).dy;
      expect(draggedY, greaterThan(origin.dy));
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.getTopLeft(content).dy, lessThan(draggedY));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(content).dy, origin.dy);
      expect(find.byType(MomentsViewerPage), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      uploads.clear();
    },
  );

  testWidgets(
    'cancelling a drag restores the Moment without cancelling upload',
    (tester) async {
      final uploads = _service();
      uploads.track(_item());
      await _open(tester, uploads, _Repo());
      final surface = find.byKey(const ValueKey('moment-drag-surface'));
      final content = find.byType(PageView);
      final origin = tester.getTopLeft(content);
      final gesture = await tester.startGesture(tester.getCenter(surface));
      await gesture.moveBy(const Offset(0, 70));
      await tester.pump();
      await gesture.cancel();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(tester.getTopLeft(content).dy, origin.dy);
      expect(uploads.byId('local-moment'), isNotNull);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      uploads.clear();
    },
  );

  for (final owner in [true, false]) {
    testWidgets('dragging an approved Moment down closes it (owner: $owner)', (
      tester,
    ) async {
      final uploads = _service();
      await _open(
        tester,
        uploads,
        _Repo(),
        media: _profile().media,
        pendingId: null,
        allowFeature: owner,
      );
      await tester.drag(find.byType(PageView), const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(find.byType(MomentsViewerPage), findsNothing);
      expect(find.text('Profile'), findsOneWidget);
      expect(tester.takeException(), isNull);
      uploads.clear();
    });
  }

  testWidgets('dragging a pending Moment down does not cancel its upload', (
    tester,
  ) async {
    final uploads = _service();
    final repo = _Repo();
    uploads.track(_item());
    await _open(tester, uploads, repo);
    await tester.drag(find.byType(PageView), const Offset(0, 150));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsViewerPage), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    expect(uploads.byId('local-moment'), isNotNull);
    expect(repo.calls, isEmpty);
    uploads.clear();
  });

  testWidgets('a short downward flick closes the Moment viewer', (
    tester,
  ) async {
    final uploads = _service();
    await _open(
      tester,
      uploads,
      _Repo(),
      media: _profile().media,
      pendingId: null,
    );
    await tester.fling(find.byType(PageView), const Offset(0, 60), 1000);
    await tester.pumpAndSettle();
    expect(find.byType(MomentsViewerPage), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    uploads.clear();
  });

  testWidgets('small downward movement and upward dragging do not close it', (
    tester,
  ) async {
    final uploads = _service();
    await _open(
      tester,
      uploads,
      _Repo(),
      media: _profile().media,
      pendingId: null,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.moveBy(const Offset(0, 25));
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(MomentsViewerPage), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(0, -200));
    await tester.pumpAndSettle();
    expect(find.byType(MomentsViewerPage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    uploads.clear();
  });

  testWidgets(
    'pending Moment opens full screen without a modal or public actions',
    (tester) async {
      final uploads = _service();
      final repo = _Repo();
      uploads.track(_item());
      await _open(tester, uploads, repo);
      expect(find.text('1 / 1'), findsOneWidget);
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      expect(find.byIcon(Icons.star_border_rounded), findsNothing);
      expect(find.byIcon(Icons.flag_outlined), findsNothing);
      expect(repo.calls, isEmpty);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Profile'), findsOneWidget);
      expect(
        uploads.byId('local-moment'),
        isNotNull,
      ); // Navigation cannot cancel uploading.
      uploads.clear();
    },
  );

  testWidgets(
    'only exact approved public Moment enables regular viewer actions',
    (tester) async {
      final decision = Completer<MediaModerationSnapshot>();
      final uploads = _service(decision: decision);
      final repo = _Repo();
      uploads.track(_item(receipt: true));
      await _open(tester, uploads, repo);
      expect(repo.calls, isEmpty);
      decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
      await tester.pump();
      await tester.pump();
      expect(repo.calls, ['checkin']);
      expect(find.text('Sharing'), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      repo.response.complete(_profile());
      await tester.pump();
      await tester.pump();
      expect(find.byType(OwnerStoryUploadMedia), findsNothing);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.star_border_rounded), findsOneWidget);
      final page = tester.widget<PageView>(find.byType(PageView));
      expect(page.controller!.page, 1);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  testWidgets(
    'pending Moment and approved Moments share one swipeable viewer',
    (tester) async {
      final uploads = _service();
      final repo = _Repo();
      uploads.track(_item());
      final published = _profile().media
          .where((item) => item.id != 'moment')
          .toList();
      await _open(tester, uploads, repo, media: published);
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sharing'), findsNothing);
      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sharing'), findsOneWidget);
      expect(uploads.wasPublished('moment'), false);
      expect(repo.calls, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  testWidgets(
    'opening an approved Moment also includes this check-in pending uploads',
    (tester) async {
      final uploads = _service();
      final repo = _Repo();
      uploads.track(_item());
      uploads.track(
        PendingPublicMedia(
          id: 'foreign',
          kind: PendingPublicMediaKind.checkinMoment,
          venueId: 'venue',
          checkinId: 'another-checkin',
          localPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
          hasServerReceipt: false,
        ),
      );
      final published = _profile().media
          .where((item) => item.id != 'moment')
          .toList();
      await _open(tester, uploads, repo, media: published, pendingId: null);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(-700, 0));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  testWidgets(
    'rejected Moment hides media and offers new capture without a popup',
    (tester) async {
      final uploads = _service();
      final repo = _Repo();
      var captures = 0;
      uploads.track(_item(state: PendingPublicMediaState.rejected));
      await _open(tester, uploads, repo, create: () => captures++);
      expect(find.text('Moment not shared'), findsOneWidget);
      expect(find.text('Disallowed text in image.'), findsOneWidget);
      expect(find.byType(PendingPublicMediaPreview), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      await tester.tap(find.text('Create new Moment'));
      expect(captures, 0);
      await tester.pumpAndSettle();
      expect(captures, 1);
      expect(uploads.items, isEmpty);
      expect(repo.calls, isEmpty);
      expect(find.text('Profile'), findsOneWidget);
      uploads.clear();
    },
  );

  for (final state in [
    PendingPublicMediaState.delayed,
    PendingPublicMediaState.underReview,
    PendingPublicMediaState.connectionIssue,
  ]) {
    testWidgets('$state has explanation instead of an endless spinner', (
      tester,
    ) async {
      final uploads = _service();
      final repo = _Repo();
      uploads.track(_item(state: state));
      await _open(tester, uploads, repo);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(
        find.textContaining(
          state == PendingPublicMediaState.underReview
              ? 'closer look'
              : 'visible to others',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('story'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    });
  }

  testWidgets('another check-in cannot open the private Moment', (
    tester,
  ) async {
    final uploads = _service();
    final repo = _Repo();
    uploads.track(_item());
    await _open(tester, uploads, repo, checkinId: 'other-checkin');
    await tester.pumpAndSettle();
    expect(find.byType(OwnerStoryUploadMedia), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    expect(repo.calls, isEmpty);
    uploads.clear();
  });

  testWidgets('logout removes private preview and ignores late public fetch', (
    tester,
  ) async {
    final decision = Completer<MediaModerationSnapshot>();
    final uploads = _service(decision: decision);
    final repo = _Repo();
    uploads.track(_item(receipt: true));
    await _open(tester, uploads, repo);
    decision.complete(const MediaModerationSnapshot(status: 'APPROVED'));
    await tester.pump();
    await tester.pump();
    uploads.clear();
    await tester.pumpAndSettle();
    repo.response.complete(_profile());
    await tester.pump();
    expect(find.byType(OwnerStoryUploadMedia), findsNothing);
    expect(find.byType(MomentsViewerPage), findsNothing);
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
