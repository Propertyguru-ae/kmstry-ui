import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/profile/data/profile_stats_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_ring_painter.dart';

class _Stories extends StoryRepository {
  List<StoryItem> stories = [];
  int reads = 0;
  @override
  Future<List<StoryItem>> getMyStories() async {
    reads++;
    return stories;
  }
}

class _Auth extends AuthRepository {
  final calls = <bool>[];
  Map<String, dynamic> current = _me('checkin-a');
  Completer<Map<String, dynamic>>? next;

  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async {
    calls.add(forceRefresh);
    return next == null ? current : next!.future;
  }
}

class _Checkins extends CheckinRepository {
  final moments = <String, Completer<CheckinProfile>>{};
  final histories = <Completer<List<CheckinVisitedPlace>>>[];
  final calls = <String>[];
  final deletion = Completer<bool>();
  @override
  Future<bool> deletePhoto(String photoId) => deletion.future;

  @override
  Future<CheckinProfile> getCheckinProfile(String checkinId) {
    calls.add(checkinId);
    return moments.putIfAbsent(checkinId, Completer<CheckinProfile>.new).future;
  }

  @override
  Future<List<CheckinVisitedPlace>> getMyProfileHistory() {
    final response = Completer<List<CheckinVisitedPlace>>();
    histories.add(response);
    return response.future;
  }
}

class _Stats extends ProfileStatsRepository {
  @override
  Future<ProfileStats> load() async =>
      const ProfileStats(friends: 45, venues: 7);
}

Map<String, dynamic> _me(String? checkin) => {
  'id': 'user-a',
  'fullName': 'Profile Test User',
  'hasPersonalProfile': true,
  if (checkin != null)
    'activeCheckin': {
      'id': checkin,
      'venueId': 'venue-$checkin',
      'venue': {'id': 'venue-$checkin', 'name': 'Test Venue'},
    },
};

CheckinProfile _profile(
  String checkin,
  String moment, {
  bool fallback = false,
}) => CheckinProfile.fromJson({
  'checkin': {'id': checkin, 'venueId': 'venue-$checkin'},
  'user': {'id': 'user-a'},
  'media': [
    {'id': moment, 'url': '', 'media_type': 'photo'},
  ],
  if (fallback)
    'visitedPlaces': [
      {
        'id': 'old-visit',
        'venueName': 'Old history',
        'checkedInAt': '2026-10-01',
      },
    ],
});

Future<void> _mount(
  WidgetTester tester,
  _Auth auth,
  _Checkins checkins, {
  _Stories? stories,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      home: ProfilePage(
        authRepository: auth,
        checkinRepository: checkins,
        statsRepository: _Stats(),
        storyRepository: stories,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ActiveCheckinService().clear();
    PendingPublicMediaService.instance.clear();
  });

  testWidgets(
    'admin story approval adds the profile story ring without pulling to refresh',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      final stories = _Stories();
      await _mount(tester, auth, checkins, stories: stories);
      checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();
      final ring = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is RoundedStoryRingPainter,
      );
      expect(ring, findsNothing);
      final reads = stories.reads;
      stories.stories = [
        StoryItem(
          id: 'approved-story',
          mediaUrl: '',
          mediaType: 'photo',
          expiresAt: DateTime.now().add(const Duration(hours: 1)),
          createdAt: DateTime.now(),
        ),
      ];
      PendingPublicMediaService.instance.handleModerationUpdate({
        'userId': 'user-a',
        'itemId': 'review-1',
        'targetType': 'PERSONAL_STORY',
        'targetId': 'approved-story',
      }, currentUserId: 'user-a');
      await tester.pumpAndSettle();
      expect(stories.reads, reads + 1);
      expect(ring, findsOneWidget);
      expect(find.text('Profile Test User'), findsWidgets);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'avatar publication quietly refreshes the canonical profile photo',
    (tester) async {
      final auth = _Auth()..current = _me(null);
      auth.current['photo'] = 'https://media.invalid/old-avatar.jpg';
      final checkins = _Checkins();
      AuthRepository.init(navigatorKey: GlobalKey<NavigatorState>());
      await _mount(tester, auth, checkins);
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();

      auth.current['photo'] = 'https://media.invalid/new-avatar.jpg';
      PendingPublicMediaService.instance.avatarPublicationChanges.value++;
      await tester.pump();
      checkins.histories.last.complete([]);
      await tester.pumpAndSettle();

      expect(auth.calls.last, true);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedImage &&
              widget.url == 'https://media.invalid/new-avatar.jpg',
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedImage &&
              widget.url == 'https://media.invalid/old-avatar.jpg',
        ),
        findsNothing,
      );
      expect(find.byType(BottomSheet), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'featured Moment updates profile avatar while profile refresh is blocked',
    (tester) async {
      final auth = _Auth();
      final active = auth.current['activeCheckin'] as Map;
      active['featuredPhoto'] = 'https://media.invalid/old.jpg';
      active['avatarPhoto'] = 'https://media.invalid/old-crop.jpg';
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();
      auth.next = Completer<Map<String, dynamic>>();
      ActiveCheckinService().featuredPhotoChanged(
        checkinId: 'checkin-a',
        mediaId: 'second',
        url: 'https://media.invalid/new.jpg',
      );
      ActiveCheckinService().notifyMediaUpdated();
      await tester.pump();
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is CachedImage &&
              widget.url == 'https://media.invalid/new.jpg',
        ),
        findsOneWidget,
      );
      expect(auth.next!.isCompleted, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      auth.next!.complete(auth.current);
    },
  );

  testWidgets(
    'profile upload stays inline and a tap opens the full-screen Moment, not a popup',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();
      final uploads = PendingPublicMediaService.instance;
      uploads.track(
        PendingPublicMedia(
          id: 'pending-profile-moment',
          kind: PendingPublicMediaKind.checkinMoment,
          checkinId: 'checkin-a',
          venueId: 'venue-checkin-a',
          localPath: '',
          previewPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
          hasServerReceipt: false,
        ),
      );
      await tester.pump();
      expect(find.text('Sharing'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MomentsViewerPage), findsNothing);
      await tester.tap(
        find.byKey(
          const ValueKey('profile-pending-moment-pending-profile-moment'),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(MomentsViewerPage), findsOneWidget);
      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('Your Moments'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      uploads.clear();
    },
  );

  testWidgets(
    'initial profile uses quiet placeholders and lightweight counts',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      expect(find.text('45'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.text('—'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(checkins.moments['checkin-a']!.isCompleted, false);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'confirmed Moment deletion disappears before profile refresh and cannot resurrect',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      final profile = _profile('checkin-a', 'first');
      profile.media.add(
        CheckinProfileMedia(
          id: 'second',
          url: '',
          mediaType: MediaType.photo,
          isFeatured: false,
        ),
      );
      checkins.moments['checkin-a']!.complete(profile);
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('profile-moment-first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-moment-first'), skipOffstage: false),
        findsOneWidget,
      );
      auth.next = Completer<Map<String, dynamic>>();
      checkins.deletion.complete(false);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-moment-first'), skipOffstage: false),
        findsNothing,
      );
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop(true);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-moment-second')),
        findsOneWidget,
      );
      // Even an older response that still contains the deleted ID cannot re-add it.
      auth.next!.complete(_me('checkin-a'));
      await tester.pump();
      checkins.histories.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('profile-moment-first')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('identity renders before parallel Moments and history finish', (
    tester,
  ) async {
    final auth = _Auth();
    final checkins = _Checkins();
    await _mount(tester, auth, checkins);
    expect(find.text('Profile Test User'), findsWidgets);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(
      find.byKey(const ValueKey('profile-moments-loading')),
      findsOneWidget,
    );
    expect(checkins.calls, ['checkin-a']);
    expect(checkins.histories, hasLength(1));
    expect(auth.calls, [false]); // No redundant force-refresh after self-sync.

    checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'moment-a'));
    await tester.pumpAndSettle();
    expect(checkins.histories.single.isCompleted, false);
    expect(
      find.byKey(const ValueKey('profile-moment-moment-a')),
      findsOneWidget,
    );
    await tester.tap(find.text('Visited Places'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('profile-history-loading')),
      findsOneWidget,
    );
    checkins.histories.single.complete([]);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('profile-history-loading')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'refresh and publication keep identity and existing Moments visible',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
      checkins.histories.single.complete([]);
      await tester.pumpAndSettle();
      final nextMe = Completer<Map<String, dynamic>>();
      auth.next = nextMe;
      checkins.moments['checkin-a'] = Completer<CheckinProfile>();
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.text('Profile Test User'), findsWidgets);
      expect(
        find.byKey(const ValueKey('profile-moment-first')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      nextMe.complete(_me('checkin-a'));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-moment-first')),
        findsOneWidget,
      );
      checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'second'));
      checkins.histories.last.complete([]);
      await refresh;
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-moment-second')),
        findsOneWidget,
      );

      auth.next = null;
      checkins.moments['checkin-a'] = Completer<CheckinProfile>();
      PendingPublicMediaService.instance.handleModerationUpdate({
        'userId': 'user-a',
        'itemId': 'review-1',
        'targetType': 'CHECKIN_MEDIA',
        'targetId': 'published',
      }, currentUserId: 'user-a');
      await tester.pump();
      checkins.moments['checkin-a']!.complete(
        _profile('checkin-a', 'published'),
      );
      checkins.histories.last.complete([]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-moment-published')),
        findsOneWidget,
      );
      expect(auth.calls, [false, true, true]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late responses from previous check-in cannot replace current data',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      auth.current = _me('checkin-b');
      ActiveCheckinService().setActiveCheckin(
        'checkin-b',
        venueId: 'venue-checkin-b',
      );
      await tester.pump();
      checkins.moments['checkin-b']!.complete(_profile('checkin-b', 'current'));
      checkins.histories.last.complete([]);
      await tester.pumpAndSettle();
      checkins.moments['checkin-a']!.complete(
        _profile('checkin-a', 'obsolete'),
      );
      checkins.histories.first.complete([]);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('profile-moment-current')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-moment-obsolete')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('successful empty history is not overwritten by late fallback', (
    tester,
  ) async {
    final auth = _Auth();
    final checkins = _Checkins();
    await _mount(tester, auth, checkins);
    checkins.histories.single.complete([]);
    await tester.pump();
    checkins.moments['checkin-a']!.complete(
      _profile('checkin-a', 'moment', fallback: true),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Visited Places'));
    await tester.pumpAndSettle();
    expect(find.text('Old history'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('checkout removes Moments without waiting for history', (
    tester,
  ) async {
    final auth = _Auth();
    final checkins = _Checkins();
    await _mount(tester, auth, checkins);
    checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
    checkins.histories.single.complete([]);
    await tester.pumpAndSettle();
    auth.current = _me(null);
    ActiveCheckinService().clear();
    await tester.pump();
    expect(find.text('No active check-in'), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-moment-first')), findsNothing);
    expect(find.text('Quick check-in'), findsOneWidget);
    expect(checkins.histories.last.isCompleted, false);
    checkins.histories.last.complete([]);
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('failed refresh keeps loaded content with a retry explanation', (
    tester,
  ) async {
    final auth = _Auth();
    final checkins = _Checkins();
    await _mount(tester, auth, checkins);
    checkins.moments['checkin-a']!.complete(_profile('checkin-a', 'first'));
    checkins.histories.single.complete([]);
    await tester.pumpAndSettle();
    auth.next = Completer<Map<String, dynamic>>();
    final refresh = tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    auth.next!.completeError(StateError('offline'));
    await refresh;
    await tester.pumpAndSettle();
    expect(find.text('Profile Test User'), findsWidgets);
    expect(find.byKey(const ValueKey('profile-moment-first')), findsOneWidget);
    expect(
      find.text('Profile data could not be loaded. Please retry.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'ending session clears retained identity and ignores late responses',
    (tester) async {
      final auth = _Auth();
      final checkins = _Checkins();
      await _mount(tester, auth, checkins);
      PendingPublicMediaService.instance.clear();
      await tester.pump();
      expect(find.text('Profile Test User'), findsNothing);
      checkins.moments['checkin-a']!.complete(
        _profile('checkin-a', 'obsolete'),
      );
      checkins.histories.single.complete([]);
      await tester.pump();
      expect(
        find.byKey(const ValueKey('profile-moment-obsolete')),
        findsNothing,
      );
      expect(find.text('Profile Test User'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
