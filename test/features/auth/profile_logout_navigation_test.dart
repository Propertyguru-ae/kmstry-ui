import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/layout/retained_home_body.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/logout_flow.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/profile/data/profile_stats_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
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
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthRepository {
  _Auth({required this.venue, this.failLogout = false});

  final bool venue;
  final bool failLogout;
  final completion = Completer<void>();
  int logoutCalls = 0;

  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => {
    'id': 'logout-user',
    'username': 'logout_user',
    'fullName': 'Logout User',
    'hasPersonalProfile': true,
    'lastActiveContext': venue ? 'VENUE' : 'PERSONAL',
    'memberVenues': [
      {
        'id': 'logout-venue',
        'name': 'Logout Cafe',
        'role': 'OWNER',
        'status': 'ACTIVE',
      },
    ],
  };

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (failLogout) throw StateError('Session cleanup failed');
    // Real AuthRepository.logout invalidates the retained profile synchronously
    // before awaiting remote logout, Google sign-out and secure storage cleanup.
    PendingPublicMediaService.instance.clear();
    await completion.future;
  }
}

class _Checkins extends CheckinRepository {
  @override
  Future<List<CheckinVisitedPlace>> getMyProfileHistory() async => [];
}

class _Stats extends ProfileStatsRepository {
  @override
  Future<ProfileStats> load() async =>
      const ProfileStats(friends: 0, venues: 1);
}

class _Owner extends VenueOwnerRepository {
  @override
  Future<VenueOwnerStatsVenue> getOwnerProfileIdentity(String id) async =>
      VenueOwnerStatsVenue(id: id, name: 'Logout Cafe', type: 'CAFE');

  @override
  Future<List<VenueUpcomingEvent>> getOwnerProfileUpcomingEvents(
    String id, {
    DateTime? now,
  }) async => [];
}

class _Gallery extends VenueGalleryRepository {
  @override
  Future<List<VenueGalleryItem>> getGallery(String venueId) async => [];
}

class _Stories extends VenueStoryRepository {
  @override
  Future<List<VenueStoryItem>> getVenueStories(String venueId) async => [];
}

class _Partnerships extends ExternalPartnershipRepository {
  @override
  Future<List<ExternalPartnershipModel>> getActivePartnerships(
    String venueId,
  ) async => [];
}

Widget _retainedProfile(_Auth auth, {bool freezeDuringLogout = false}) {
  final generation = PendingPublicMediaService.instance.sessionGeneration;
  return ValueListenableBuilder<int>(
    valueListenable: PendingPublicMediaService.instance.changes,
    builder: (context, value, child) => RetainedHomeBody(
      // Match AppShell: session changes discard the retained Home/Profile state.
      key: ValueKey(
        freezeDuringLogout && LogoutFlow.busy.value
            ? generation
            : PendingPublicMediaService.instance.sessionGeneration,
      ),
      isHome: false,
      isProfile: true,
      home: const SizedBox.shrink(),
      destination: const SizedBox.shrink(),
      profile: auth.venue
          ? VenueProfilePage(
              venueId: 'logout-venue',
              authRepository: auth,
              repository: _Owner(),
              galleryRepository: _Gallery(),
              storyRepository: _Stories(),
              partnershipRepository: _Partnerships(),
            )
          : ProfilePage(
              authRepository: auth,
              checkinRepository: _Checkins(),
              statsRepository: _Stats(),
            ),
    ),
  );
}

Future<GlobalKey<NavigatorState>> _mount(
  WidgetTester tester,
  _Auth auth, {
  bool nestedNavigator = false,
  bool freezeDuringLogout = false,
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final root = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      builder: (_, child) => LogoutGuard(child: child!),
      navigatorKey: root,
      home: const Scaffold(body: Text('Previous authenticated route')),
      routes: {
        AuthRoutes.login: (_) =>
            const Scaffold(body: Text('Login destination')),
        '/test-profile': (_) => nestedNavigator
            ? Navigator(
                onGenerateRoute: (_) => MaterialPageRoute<void>(
                  builder: (_) => _retainedProfile(auth),
                ),
              )
            : _retainedProfile(auth, freezeDuringLogout: freezeDuringLogout),
      },
    ),
  );
  root.currentState!.pushNamed('/test-profile');
  await tester.pumpAndSettle();
  return root;
}

Future<void> _tapLogout(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded).first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Log out'));
  await tester.pump();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    ActiveCheckinService().clear();
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });

  for (final venue in [false, true]) {
    final account = venue ? 'venue' : 'personal';

    for (final nestedNavigator in [false, true]) {
      testWidgets('$account logout reaches root Login after profile disposal '
          '(nested navigator: $nestedNavigator)', (tester) async {
        final auth = _Auth(venue: venue);
        final root = await _mount(
          tester,
          auth,
          nestedNavigator: nestedNavigator,
        );
        final profile = tester.state(
          find.byType(venue ? VenueProfilePage : ProfilePage),
        );

        await _tapLogout(tester);
        expect(auth.logoutCalls, 1);
        expect(profile.mounted, isFalse);
        expect(find.text('Login destination'), findsNothing);

        auth.completion.complete();
        await tester.pumpAndSettle();

        expect(find.text('Login destination'), findsOneWidget);
        expect(find.byType(ProfilePage), findsNothing);
        expect(find.byType(VenueProfilePage), findsNothing);
        expect(root.currentState!.canPop(), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('$account does not navigate on failed session cleanup', (
      tester,
    ) async {
      final auth = _Auth(venue: venue, failLogout: true);
      await _mount(tester, auth);
      await _tapLogout(tester);
      await tester.pumpAndSettle();

      expect(auth.logoutCalls, 1);
      expect(find.text('Login destination'), findsNothing);
      expect(
        find.byType(venue ? VenueProfilePage : ProfilePage),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      expect(
        find.text('Could not finish signing out. Please try again.'),
        findsOneWidget,
      );
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(LogoutFlow.busy.value, isFalse);
    });

    testWidgets(
      '$account keeps profile and menu stable, prevents double logout and back',
      (tester) async {
        final auth = _Auth(venue: venue);
        final root = await _mount(tester, auth, freezeDuringLogout: true);
        final profile = tester.state(
          find.byType(venue ? VenueProfilePage : ProfilePage),
        );
        await _tapLogout(tester);
        await tester.pump(const Duration(milliseconds: 350));
        expect(profile.mounted, isTrue);
        expect(find.text('Log out'), findsOneWidget);
        expect(find.byType(LogoutProgress), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        await tester.tap(find.text('Log out'), warnIfMissed: false);
        await root.currentState!.maybePop();
        await tester.pump();
        expect(auth.logoutCalls, 1);
        expect(find.text('Log out'), findsOneWidget);
        auth.completion.complete();
        await tester.pumpAndSettle();
        expect(find.text('Login destination'), findsOneWidget);
        expect(root.currentState!.canPop(), isFalse);
        expect(LogoutFlow.busy.value, isFalse);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
