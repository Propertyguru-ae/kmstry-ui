import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/core/venue/venue_read_changes.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/owner_photo_preview.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_profile_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

class _Gallery extends VenueGalleryRepository {
  @override
  Future<List<VenueGalleryItem>> getGallery(String venueId) async => [];
}

class _Stories extends VenueStoryRepository {
  _Stories([this.read]);
  final Future<List<VenueStoryItem>> Function(String)? read;
  int calls = 0;
  int viewerCalls = 0;
  @override
  Future<List<Map<String, dynamic>>> getViewers(String venueId) async {
    viewerCalls++;
    return [
      {'story_id': 'story', 'view_count': 7, 'viewers': []},
    ];
  }

  @override
  Future<List<VenueStoryItem>> getVenueStories(String venueId) {
    calls++;
    return read?.call(venueId) ?? Future.value([]);
  }
}

class _StoryPermissions extends VenueMemberRepository {
  _StoryPermissions(this.allowed);
  final bool allowed;
  @override
  Future<MyVenueAccess> getMyPermissions(String id) async => MyVenueAccess(
    permissions: [
      VenuePermission.storyManage,
      if (allowed) VenuePermission.storyViewStats,
    ],
    plan: VenuePlan.free,
    planUntil: null,
    features: {},
  );
}

class _Partnerships extends ExternalPartnershipRepository {
  _Partnerships([this.read]);
  final Future<List<ExternalPartnershipModel>> Function(String)? read;
  int calls = 0;
  @override
  Future<List<ExternalPartnershipModel>> getActivePartnerships(String venueId) {
    calls++;
    return read?.call(venueId) ?? Future.value([]);
  }
}

class _Auth extends AuthRepository {
  _Auth(this.read);
  final Future<Map<String, dynamic>> Function() read;
  final calls = <bool>[];
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) {
    calls.add(forceRefresh);
    return read();
  }
}

class _Owner extends VenueOwnerRepository {
  _Owner(this.identity, this.events);
  final Future<VenueOwnerStatsVenue> Function(String) identity;
  final Future<List<VenueUpcomingEvent>> Function(String) events;
  final identities = <String>[];
  final weeks = <String>[];
  int legacy = 0;
  Future<VenueOwnerStatsVenue> Function(String, String?)? saveAbout;

  @override
  Future<VenueOwnerStatsVenue> updateVenue(
    String venueId, {
    String? name,
    String? description,
    String? photo,
    String? type,
  }) {
    return saveAbout!(venueId, description);
  }

  @override
  Future<VenueOwnerStatsVenue> getOwnerProfileIdentity(String id) {
    identities.add(id);
    return identity(id);
  }

  @override
  Future<List<VenueUpcomingEvent>> getOwnerProfileUpcomingEvents(
    String id, {
    DateTime? now,
  }) {
    weeks.add(id);
    return events(id);
  }

  @override
  Future<VenueOwnerStatsVenue> getOwnerProfile(String id) {
    legacy++;
    throw StateError('Profile must not wait for full history');
  }
}

Map<String, dynamic> _me({String status = 'ACTIVE'}) => {
  'username': 'owner',
  'hasPersonalProfile': true,
  'lastActiveContext': 'VENUE',
  'memberVenues': [
    for (final id in ['a', 'b'])
      {'id': id, 'name': 'Cafe $id', 'role': 'OWNER', 'status': status},
  ],
};
VenueOwnerStatsVenue _identity(String id, {String about = 'Full About'}) =>
    VenueOwnerStatsVenue(
      id: id,
      name: 'Cafe $id',
      description: about,
      address: 'Venue Address',
      type: 'CAFE',
      city: 'Dubai',
    );
VenueUpcomingEvent _event(String title) {
  final start = DateTime.now().add(const Duration(hours: 1));
  return VenueUpcomingEvent(
    id: title,
    title: title,
    description: 'Complete event',
    startAt: start,
    endAt: start.add(const Duration(hours: 1)),
    capacity: 60,
    rsvpCount: 12,
  );
}

ExternalPartnershipModel _deal(String id) => ExternalPartnershipModel(
  id: id,
  venueId: id,
  platform: ExternalPartnershipPlatform.OTHER,
  platformLabel: 'Deal $id',
  offerType: ExternalPartnershipOfferType.OTHER,
  offerLabel: 'Complete benefit',
  status: ExternalPartnershipStatus.ACTIVE,
  createdAt: DateTime.now(),
);

VenueStoryItem _story(String id) => VenueStoryItem(
  id: id,
  mediaUrl: 'https://example.test/$id.jpg',
  mediaType: 'photo',
  createdAt: DateTime.now(),
  expiresAt: DateTime.now().add(const Duration(hours: 24)),
);

Finder _storyRing() => find.byWidgetPredicate(
  (widget) =>
      widget is CustomPaint &&
      widget.painter?.runtimeType.toString() == '_SquareRingPainter',
);

Future<void> _pump(
  WidgetTester tester,
  _Auth auth,
  _Owner owner, {
  String id = 'a',
  VenueStoryRepository? stories,
  ExternalPartnershipRepository? partnerships,
  bool active = true,
  VenueSession? session,
}) => tester.pumpWidget(
  MaterialApp(
    home: VenueProfilePage(
      key: const ValueKey('profile'),
      venueId: id,
      authRepository: auth,
      repository: owner,
      galleryRepository: _Gallery(),
      storyRepository: stories ?? _Stories(),
      partnershipRepository: partnerships ?? _Partnerships(),
      venueSession: session,
      isActive: active,
    ),
  ),
);

void main() {
  testWidgets(
    'Add Personal from venue profile paints existing account defaults immediately',
    (tester) async {
      tester.view.physicalSize = const Size(390, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final pending = Completer<Map<String, dynamic>>();
      var reads = 0;
      final account = {
        ..._me(),
        'hasPersonalProfile': false,
        'fullName': null,
        'registrationName': 'Invited Member',
        'birthdate': '1990-01-02T00:00:00Z',
      };
      final auth = _Auth(
        () => ++reads == 1 ? Future.value(account) : pending.future,
      );
      await _pump(
        tester,
        auth,
        _Owner((id) async => _identity(id), (_) async => []),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(AppBar), matching: find.text('Cafe a')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Personal Account'));
      await tester.pumpAndSettle();
      expect(pending.isCompleted, false);
      expect(find.text('Invited Member'), findsOneWidget);
      expect(find.text('01/02/1990'), findsOneWidget);
      pending.complete(account);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final allowed in [false, true]) {
    testWidgets(
      'profile avatar tap and long press respect statistics permission: $allowed',
      (tester) async {
        addTearDown(() async {
          await tester.pumpWidget(const SizedBox());
          await tester.pump();
        });
        final session = VenueSession.forTest(
          repository: _StoryPermissions(allowed),
        );
        final stories = _Stories(
          (_) async => [
            VenueStoryItem(
              id: 'story',
              mediaUrl: '',
              mediaType: 'photo',
              createdAt: DateTime(2026),
              expiresAt: DateTime(2030),
              viewCount: 7,
              canViewStats: true,
            ),
          ],
        );
        await _pump(
          tester,
          _Auth(() async => _me()),
          _Owner((id) async => _identity(id), (_) async => []),
          stories: stories,
          session: session,
        );
        await tester.pumpAndSettle();
        final avatar = find.byKey(const ValueKey('venue-story-avatar'));
        expect(avatar, findsOneWidget);
        await tester.longPress(avatar);
        await tester.pumpAndSettle();
        expect(
          find.text('Story Viewers'),
          allowed ? findsOneWidget : findsNothing,
        );
        expect(stories.viewerCalls, allowed ? 1 : 0);
        if (allowed) {
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();
        }
        await tester.tap(avatar);
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(find.byType(StoryViewerPage), findsOneWidget);
        expect(
          find.byIcon(Icons.remove_red_eye_outlined),
          allowed ? findsOneWidget : findsNothing,
        );
        expect(stories.viewerCalls, allowed ? 2 : 0);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final width in [360.0, 430.0]) {
    for (final state in [
      PendingPublicMediaState.rejected,
      PendingPublicMediaState.underReview,
    ]) {
      testWidgets(
        'cover status $state is centred horizontally and vertically at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final uploads = PendingPublicMediaService.instance;
          uploads.track(
            PendingPublicMedia(
              id: 'cover-review',
              kind: PendingPublicMediaKind.venueAvatar,
              venueId: 'a',
              localPath: '',
              isVideo: false,
              createdAt: DateTime.now(),
              state: state,
              hasServerReceipt: false,
              message: 'The photo needs a content review.',
            ),
          );
          await _pump(
            tester,
            _Auth(() async => _me()),
            _Owner((id) async => _identity(id), (_) async => []),
          );
          await tester.pumpAndSettle();
          final cover = tester.getRect(
            find.byKey(const ValueKey('venue-profile-cover')),
          );
          final status = tester.getRect(find.byType(OwnerPhotoUploadStatus));
          expect(status.center.dx, closeTo(cover.center.dx, 0.1));
          expect(status.center.dy, closeTo(cover.center.dy, 0.1));
          expect(cover.contains(status.topLeft), true);
          expect(cover.contains(status.bottomRight), true);
          expect(
            find.text(
              state == PendingPublicMediaState.rejected
                  ? 'Photo not updated'
                  : 'Under review',
            ),
            findsOneWidget,
          );
          expect(uploads.byId('cover-review')?.state, state);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'long cover explanations remain within the centred scrollable area',
    (tester) async {
      PendingPublicMediaService.instance.track(
        PendingPublicMedia(
          id: 'long-cover-review',
          kind: PendingPublicMediaKind.venueAvatar,
          venueId: 'a',
          localPath: '',
          isVideo: false,
          createdAt: DateTime.now(),
          state: PendingPublicMediaState.rejected,
          hasServerReceipt: false,
          message: List.filled(
            12,
            'The photo needs a content review.',
          ).join(' '),
        ),
      );
      await _pump(
        tester,
        _Auth(() async => _me()),
        _Owner((id) async => _identity(id), (_) async => []),
      );
      await tester.pumpAndSettle();
      final cover = tester.getRect(
        find.byKey(const ValueKey('venue-profile-cover')),
      );
      final viewport = tester.getRect(
        find.byKey(const ValueKey('venue-cover-upload-status')),
      );
      expect(viewport.center, cover.center);
      expect(viewport.height, lessThanOrEqualTo(cover.height - 24));
      expect(tester.takeException(), isNull);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets(
      'About ${unavailable ? 'AWS outage' : 'policy rejection'} preserves the editor and unsaved draft',
      (tester) async {
        final owner = _Owner((id) async => _identity(id), (_) async => []);
        var saves = 0;
        owner.saveAbout = (id, description) async {
          saves++;
          expect(id, 'a');
          expect(description, 'test description');
          throw ApiException(
            statusCode: unavailable ? 503 : 400,
            data: {
              'errorCode': unavailable
                  ? 'PUBLIC_TEXT_CHECK_UNAVAILABLE'
                  : 'PUBLIC_TEXT_NOT_ALLOWED',
              if (!unavailable) 'textPolicyCategories': ['CONTENT_INSULTS'],
            },
          );
        };
        await _pump(tester, _Auth(() async => _me()), owner);
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Edit').first);
        await tester.tap(find.text('Edit').first);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'test description');
        await tester.tap(find.text('Save'));
        await tester.pumpAndSettle();

        expect(saves, 1);
        expect(find.text('Something went wrong'), findsNothing);
        expect(find.text('Full About'), findsOneWidget);
        if (unavailable) {
          expect(find.textContaining("haven't been saved"), findsOneWidget);
        } else {
          expect(find.text(publicTextRejectionMessage), findsOneWidget);
        }
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('Full About'), findsOneWidget);
        expect(find.text('test description'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('About saves allowed text normally', (tester) async {
    final owner = _Owner((id) async => _identity(id), (_) async => []);
    owner.saveAbout = (id, description) async =>
        _identity(id, about: description!);
    await _pump(tester, _Auth(() async => _me()), owner);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Edit').first);
    await tester.tap(find.text('Edit').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Coffee and live music');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Coffee and live music'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'venue Not now keeps About open; Review permission saves the same draft',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
      var allow = false;
      var saves = 0;
      PublicContentPermission.onRequired = (_) async {
        if (!allow)
          throw ApiException(
            statusCode: 403,
            data: const {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
          );
      };
      final owner = _Owner((id) async => _identity(id), (_) async => []);
      owner.saveAbout = (id, description) async {
        saves++;
        return _identity(id, about: description!);
      };
      await _pump(tester, _Auth(() async => _me()), owner);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Edit').first);
      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'Unsaved venue description',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saves, 0);
      expect(find.text('Unsaved venue description'), findsOneWidget);
      expect(find.text('Review permission'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      allow = true;
      await tester.tap(find.text('Review permission'));
      await tester.pumpAndSettle();
      expect(saves, 1);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Unsaved venue description'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'fresh return has no identity/event/story/benefit reads; hidden changes refresh only their sections',
    (tester) async {
      final auth = _Auth(() async => _me());
      final owner = _Owner(
        (id) async => _identity(id),
        (_) async => [_event('Keep this event')],
      );
      final stories = _Stories();
      final partnerships = _Partnerships();
      Future<void> pump(bool active) => _pump(
        tester,
        auth,
        owner,
        active: active,
        stories: stories,
        partnerships: partnerships,
      );
      await pump(true);
      await tester.pumpAndSettle();
      await pump(false);
      await pump(true);
      await tester.pumpAndSettle();
      expect(owner.identities, ['a']);
      expect(owner.weeks, ['a']);
      expect(stories.calls, 1);
      expect(partnerships.calls, 1);
      await pump(false);
      final session = PendingPublicMediaService.instance.sessionGeneration;
      VenueReadChanges.committed('b', {VenueReadSection.identity}, session);
      VenueReadChanges.committed('a', {VenueReadSection.events}, session);
      VenueReadChanges.committed('a', {VenueReadSection.events}, session);
      VenueStoryRepository.changes.value++;
      VenueStoryRepository.changes.value++;
      await tester.pumpAndSettle();
      expect(owner.weeks, ['a']);
      expect(stories.calls, 1);
      await pump(true);
      await tester.pumpAndSettle();
      expect(owner.identities, ['a']);
      expect(owner.weeks, ['a', 'a']);
      expect(stories.calls, 2);
      expect(partnerships.calls, 1);
      expect(find.text('Keep this event'), findsOneWidget);
      VenueReadChanges.committed('a', {VenueReadSection.partnerships}, session);
      await tester.pumpAndSettle();
      expect(partnerships.calls, 2);
      expect(owner.identities, ['a']);
      expect(owner.weeks, ['a', 'a']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'identity metadata refresh preserves profile and does not reload fresh independent sections',
    (tester) async {
      var about = 'Original About';
      final auth = _Auth(() async => _me());
      final owner = _Owner(
        (id) async => _identity(id, about: about),
        (_) async => [],
      );
      final stories = _Stories();
      final partnerships = _Partnerships();
      await _pump(
        tester,
        auth,
        owner,
        stories: stories,
        partnerships: partnerships,
      );
      await tester.pumpAndSettle();
      about = 'New About';
      VenueReadChanges.committed('a', {
        VenueReadSection.identity,
      }, PendingPublicMediaService.instance.sessionGeneration);
      await tester.pumpAndSettle();
      expect(find.text('New About'), findsOneWidget);
      expect(owner.identities, ['a', 'a']);
      expect(owner.weeks, ['a']);
      expect(stories.calls, 1);
      expect(partnerships.calls, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'retained profile never keeps venue media after backend revokes profile access',
    (tester) async {
      var denied = false;
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async {
        if (denied) throw ApiException(statusCode: 403, data: {});
        return _identity(id);
      }, (_) async => [_event('Private event')]);
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      denied = true;
      VenueReadChanges.committed('a', {
        VenueReadSection.identity,
      }, PendingPublicMediaService.instance.sessionGeneration);
      await tester.pumpAndSettle();
      expect(find.text('Full About'), findsNothing);
      expect(find.text('Private event'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });
  tearDown(() {
    PublicContentPermission.onRequired = null;
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });

  testWidgets(
    'identity/account overlap; full profile paints while weekly events remain pending, then existing event cards appear',
    (tester) async {
      final account = Completer<Map<String, dynamic>>();
      final identity = Completer<VenueOwnerStatsVenue>();
      final events = Completer<List<VenueUpcomingEvent>>();
      final auth = _Auth(() => account.future);
      final owner = _Owner((_) => identity.future, (_) => events.future);
      await _pump(tester, auth, owner);
      expect(auth.calls, [false]);
      expect(owner.identities, ['a']);
      expect(owner.weeks, isEmpty);
      identity.complete(_identity('a'));
      await tester.pump();
      expect(find.text('Full About'), findsNothing);
      account.complete(_me());
      await tester.pumpAndSettle();
      expect(find.text('Full About'), findsOneWidget);
      expect(find.text('Venue Address'), findsOneWidget);
      expect(find.text('Cafe a'), findsWidgets);
      expect(owner.weeks, ['a']);
      expect(events.isCompleted, false);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      events.complete([_event('Upcoming Bicycle')]);
      await tester.pumpAndSettle();
      expect(find.text('Upcoming Bicycle'), findsOneWidget);
      expect(find.text('Full About'), findsOneWidget);
      expect(owner.legacy, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final status in ['PENDING', 'REJECTED']) {
    testWidgets(
      '$status claim keeps locked profile without awaiting identity or requesting week',
      (tester) async {
        final identity = Completer<VenueOwnerStatsVenue>();
        final auth = _Auth(() async => _me(status: status));
        final owner = _Owner(
          (_) => identity.future,
          (_) async => [_event('Must not show')],
        );
        await _pump(tester, auth, owner);
        await tester.pumpAndSettle();
        expect(
          find.text('You can add a photo after your venue is approved.'),
          findsOneWidget,
        );
        expect(owner.weeks, isEmpty);
        expect(find.text('Full About'), findsNothing);
        identity.completeError(StateError('VIEW_STATS denied'));
        await tester.pumpAndSettle();
        expect(owner.weeks, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'same page venue switch clears old sections and rejects late former-venue event data',
    (tester) async {
      final first = Completer<List<VenueUpcomingEvent>>();
      final second = Completer<List<VenueUpcomingEvent>>();
      final auth = _Auth(() async => _me());
      final owner = _Owner(
        (id) async => _identity(id, about: 'About $id'),
        (id) => id == 'a' ? first.future : second.future,
      );
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      expect(find.text('About a'), findsOneWidget);
      await _pump(tester, auth, owner, id: 'b');
      await tester.pumpAndSettle();
      expect(find.text('About b'), findsOneWidget);
      expect(find.text('About a'), findsNothing);
      first.complete([_event('Old venue event')]);
      second.complete([_event('New venue event')]);
      await tester.pumpAndSettle();
      expect(find.text('Old venue event'), findsNothing);
      expect(find.text('New venue event'), findsOneWidget);
      expect(owner.weeks, ['a', 'b']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'refresh preserves current identity and week while loading, then replaces complete event list',
    (tester) async {
      var refreshed = false;
      final identity = Completer<VenueOwnerStatsVenue>();
      final events = Completer<List<VenueUpcomingEvent>>();
      final auth = _Auth(() async => _me());
      final owner = _Owner(
        (id) => refreshed ? identity.future : Future.value(_identity(id)),
        (_) =>
            refreshed ? events.future : Future.value([_event('Before update')]),
      );
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      refreshed = true;
      final refresh = tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pump();
      expect(find.text('Full About'), findsOneWidget);
      expect(find.text('Before update'), findsOneWidget);
      identity.complete(_identity('a', about: 'Updated About'));
      await tester.pumpAndSettle();
      expect(find.text('Updated About'), findsOneWidget);
      expect(find.text('Before update'), findsOneWidget);
      events.complete([_event('After update')]);
      await tester.pumpAndSettle();
      await refresh;
      expect(find.text('Before update'), findsNothing);
      expect(find.text('After update'), findsOneWidget);
      expect(auth.calls, [false, true]);
      expect(owner.legacy, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'week failure keeps complete existing events and never blocks profile; publication refresh only reads week',
    (tester) async {
      var fail = false;
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async => _identity(id), (_) async {
        if (fail) throw StateError('temporary error');
        return [_event('Keep this event')];
      });
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      fail = true;
      PendingPublicMediaService.instance.eventPublicationChanges.value++;
      await tester.pumpAndSettle();
      expect(find.text('Keep this event'), findsOneWidget);
      expect(find.text('Full About'), findsOneWidget);
      expect(owner.identities, ['a']);
      expect(auth.calls, [false]);
      expect(owner.weeks, ['a', 'a']);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'slow stories and benefits never delay identity; late former-venue sections cannot replace current data',
    (tester) async {
      final oldStories = Completer<List<VenueStoryItem>>();
      final oldBenefits = Completer<List<ExternalPartnershipModel>>();
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async => _identity(id), (_) async => []);
      final stories = _Stories(
        (id) => id == 'a' ? oldStories.future : Future.value([]),
      );
      final benefits = _Partnerships(
        (id) => id == 'a' ? oldBenefits.future : Future.value([_deal('b')]),
      );
      await _pump(
        tester,
        auth,
        owner,
        stories: stories,
        partnerships: benefits,
      );
      await tester.pumpAndSettle();
      expect(find.text('Full About'), findsOneWidget);
      expect(oldStories.isCompleted, false);
      expect(oldBenefits.isCompleted, false);
      await _pump(
        tester,
        auth,
        owner,
        id: 'b',
        stories: stories,
        partnerships: benefits,
      );
      await tester.pumpAndSettle();
      expect(find.text('Deal b'), findsOneWidget);
      expect(_storyRing(), findsNothing);
      oldStories.complete([_story('a')]);
      oldBenefits.complete([_deal('a')]);
      await tester.pumpAndSettle();
      expect(find.text('Deal a'), findsNothing);
      expect(find.text('Deal b'), findsOneWidget);
      expect(_storyRing(), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'current approved story and all benefits independently arrive after profile paints',
    (tester) async {
      final stories = Completer<List<VenueStoryItem>>();
      final benefits = Completer<List<ExternalPartnershipModel>>();
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async => _identity(id), (_) async => []);
      await _pump(
        tester,
        auth,
        owner,
        stories: _Stories((_) => stories.future),
        partnerships: _Partnerships((_) => benefits.future),
      );
      await tester.pumpAndSettle();
      expect(find.text('Full About'), findsOneWidget);
      expect(_storyRing(), findsNothing);
      stories.complete([_story('a')]);
      benefits.complete([_deal('a'), _deal('b')]);
      await tester.pumpAndSettle();
      expect(_storyRing(), findsOneWidget);
      expect(find.text('Deal a'), findsOneWidget);
      expect(find.text('Deal b'), findsOneWidget);
      expect(find.text('Full About'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'logout and leaving the page suppress late weekly results and never call setState after dispose',
    (tester) async {
      final events = Completer<List<VenueUpcomingEvent>>();
      final auth = _Auth(() async => _me());
      final owner = _Owner((id) async => _identity(id), (_) => events.future);
      await _pump(tester, auth, owner);
      await tester.pumpAndSettle();
      PendingPublicMediaService.instance.clear();
      events.complete([_event('Late private event')]);
      await tester.pumpAndSettle();
      expect(find.text('Late private event'), findsNothing);
      expect(tester.takeException(), isNull);
      final later = Completer<List<VenueUpcomingEvent>>();
      final other = _Owner((id) async => _identity(id), (_) => later.future);
      await tester.pumpWidget(const SizedBox());
      await _pump(tester, auth, other);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      later.complete([_event('Disposed')]);
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
}
