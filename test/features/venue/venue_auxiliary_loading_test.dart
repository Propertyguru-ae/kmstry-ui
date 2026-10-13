import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_analytics_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_follower_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_section.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_followers_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_owner_guests_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

class _Owner extends VenueOwnerRepository {
  Future<VenueAnalytics> Function(String, String)? analytics;
  Future<List<WeeklyReport>> Function(String)? reports;
  Future<List<VenueFollower>> Function(String)? followers;
  Future<VenueOwnerGuestsResponse> Function(String)? guests;
  final chartCalls = <String>[];
  final reportCalls = <String>[];
  final followerCalls = <String>[];
  final guestCalls = <String>[];
  @override
  Future<VenueAnalytics> getAnalytics(
    String venueId, {
    String range = '7d',
    String? from,
    String? to,
  }) {
    chartCalls.add('$venueId:$range');
    return analytics!(venueId, range);
  }

  @override
  Future<List<WeeklyReport>> getWeeklyReports(String venueId) {
    reportCalls.add(venueId);
    return reports!(venueId);
  }

  @override
  Future<List<VenueFollower>> getFollowers(
    String venueId, {
    String sort = 'latest',
  }) {
    followerCalls.add(venueId);
    return followers!(venueId);
  }

  @override
  Future<VenueOwnerGuestsResponse> getOwnerGuests(String venueId) {
    guestCalls.add(venueId);
    return guests!(venueId);
  }
}

class _Members extends VenueMemberRepository {
  Future<List<VenueMember>> Function(String)? members;
  Future<List<VenueRole>> Function(String)? roles;
  final memberCalls = <String>[];
  final roleCalls = <String>[];
  @override
  Future<List<VenueMember>> getMembers(String venueId) {
    memberCalls.add(venueId);
    return members!(venueId);
  }

  @override
  Future<List<VenueRole>> getRoles(String venueId) {
    roleCalls.add(venueId);
    return roles!(venueId);
  }
}

VenueAnalytics _chart(int total) => VenueAnalytics.fromJson({
  'totals': {'totalCheckins': total, 'uniqueVisitors': total},
  'privacy': {'repeatMetricsAvailable': false, 'demographicsAvailable': false},
});
VenueMember _member(
  String name, {
  VenueMemberStatus status = VenueMemberStatus.active,
}) => VenueMember(
  id: name,
  role: VenueMemberRole.staff,
  status: status,
  createdAt: '2026-10-06T10:00:00Z',
  user: VenueMemberUser(id: name, fullName: name),
);
VenueFollower _follower(String name) => VenueFollower.fromJson({
  'userId': name,
  'fullName': name,
  'followedAt': '2026-10-06T10:00:00Z',
});
VenueOwnerGuestsResponse _guests(String name, {int today = 17}) =>
    VenueOwnerGuestsResponse(
      activeGuests: [
        VenueActiveGuest(id: name, fullName: name, checkinId: 'checkin-$name'),
      ],
      maleNow: 1,
      femaleNow: 0,
      todayTotal: today,
    );

Widget _analytics(
  _Owner repo, {
  String venue = 'a',
  GlobalKey<VenueAnalyticsSectionState>? key,
}) => MaterialApp(
  home: Scaffold(
    body: SingleChildScrollView(
      child: VenueAnalyticsSection(key: key, venueId: venue, repository: repo),
    ),
  ),
);
Future<void> _refresh(WidgetTester tester) async {
  final widget = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
  unawaited(widget.onRefresh());
  await tester.pump();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  testWidgets(
    'analytics paints before reports and range changes do not refetch reports',
    (tester) async {
      final reports = Completer<List<WeeklyReport>>();
      final repo = _Owner();
      repo.analytics = (_, range) async => _chart(range == '7d' ? 12 : 30);
      repo.reports = (_) => reports.future;
      await tester.pumpWidget(_analytics(repo));
      await tester.pump();
      expect(
        find.text('12 people checked in 12 times in this period.'),
        findsOneWidget,
      );
      expect(repo.reportCalls, ['a']);
      await tester.tap(find.text('30d'));
      await tester.pump();
      expect(
        find.text('30 people checked in 30 times in this period.'),
        findsOneWidget,
      );
      expect(repo.chartCalls, ['a:7d', 'a:30d']);
      expect(repo.reportCalls, ['a']);
      reports.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('old analytics range cannot replace the latest selection', (
    tester,
  ) async {
    final old = Completer<VenueAnalytics>();
    final repo = _Owner();
    repo.analytics = (_, range) =>
        range == '7d' ? old.future : Future.value(_chart(30));
    repo.reports = (_) async => [];
    await tester.pumpWidget(_analytics(repo));
    await tester.tap(find.text('30d'));
    await tester.pumpAndSettle();
    old.complete(_chart(99));
    await tester.pumpAndSettle();
    expect(
      find.text('30 people checked in 30 times in this period.'),
      findsOneWidget,
    );
    expect(find.textContaining('99 people'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analytics ignores a late result after logout', (tester) async {
    final chart = Completer<VenueAnalytics>();
    final repo = _Owner();
    repo.analytics = (_, _) => chart.future;
    repo.reports = (_) async => [];
    await tester.pumpWidget(_analytics(repo));
    PendingPublicMediaService.instance.clear();
    chart.complete(_chart(99));
    await tester.pump();
    expect(find.textContaining('99 people'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'team members paint without waiting for roles; refresh keeps the existing list',
    (tester) async {
      final roles = Completer<List<VenueRole>>();
      final next = Completer<List<VenueMember>>();
      var count = 0;
      final repo = _Members();
      repo.members = (_) => ++count == 1
          ? Future.value([
              _member('Alex'),
              _member('Sam', status: VenueMemberStatus.pending),
            ])
          : next.future;
      repo.roles = (_) => roles.future;
      await tester.pumpWidget(
        MaterialApp(
          home: VenueTeamPage(
            venueId: 'a',
            callerRole: VenueMemberRole.owner,
            repository: repo,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Alex'), findsOneWidget);
      expect(find.text('Sam'), findsOneWidget);
      expect(repo.memberCalls, ['a']);
      expect(repo.roleCalls, ['a']);
      roles.complete([]);
      await tester.pumpAndSettle();
      await _refresh(tester);
      expect(find.text('Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      next.complete([_member('Alex'), _member('Jo')]);
      await tester.pumpAndSettle();
      expect(find.text('Jo'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('denied roles cannot be overridden by a late team response', (
    tester,
  ) async {
    final members = Completer<List<VenueMember>>();
    final repo = _Members();
    repo.members = (_) => members.future;
    repo.roles = (_) async => throw ApiException(statusCode: 403, data: {});
    await tester.pumpWidget(
      MaterialApp(
        home: VenueTeamPage(
          venueId: 'a',
          callerRole: VenueMemberRole.owner,
          repository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    members.complete([_member('Private person')]);
    await tester.pumpAndSettle();
    expect(find.text('Private person'), findsNothing);
    expect(find.text('Failed to load team.'), findsOneWidget);
  });

  testWidgets(
    'followers refresh in place and remove old data on access denial',
    (tester) async {
      final next = Completer<List<VenueFollower>>();
      var calls = 0;
      final repo = _Owner()
        ..followers = (_) => ++calls == 1
            ? Future.value([_follower('Follower Alex')])
            : next.future;
      await tester.pumpWidget(
        MaterialApp(
          home: VenueFollowersPage(venueId: 'a', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      await _refresh(tester);
      expect(find.text('Follower Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      next.completeError(ApiException(statusCode: 403, data: {}));
      await tester.pumpAndSettle();
      expect(find.text('Follower Alex'), findsNothing);
      expect(find.text('Could not load followers.'), findsOneWidget);
    },
  );

  testWidgets('followers ignore late former venue data', (tester) async {
    final old = Completer<List<VenueFollower>>();
    final repo = _Owner()
      ..followers = (id) => id == 'a'
          ? old.future
          : Future.value([_follower('New venue follower')]);
    await tester.pumpWidget(
      MaterialApp(
        home: VenueFollowersPage(venueId: 'a', repository: repo),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: VenueFollowersPage(venueId: 'b', repository: repo),
      ),
    );
    await tester.pumpAndSettle();
    old.complete([_follower('Old venue follower')]);
    await tester.pumpAndSettle();
    expect(find.text('New venue follower'), findsOneWidget);
    expect(find.text('Old venue follower'), findsNothing);
  });

  testWidgets(
    'guests refresh in place with all counts; denied access hides old identities',
    (tester) async {
      final next = Completer<VenueOwnerGuestsResponse>();
      var count = 0;
      final repo = _Owner()
        ..guests = (_) =>
            ++count == 1 ? Future.value(_guests('Guest Alex')) : next.future;
      await tester.pumpWidget(
        MaterialApp(
          home: VenueOwnerGuestsPage(venueId: 'a', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('17 today'), findsOneWidget);
      expect(find.text('1 here now'), findsOneWidget);
      await _refresh(tester);
      expect(find.text('Guest Alex'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      next.completeError(ApiException(statusCode: 403, data: {}));
      await tester.pumpAndSettle();
      expect(find.text('Guest Alex'), findsNothing);
      expect(find.text('Could not load guests. Tap to retry.'), findsOneWidget);
    },
  );

  testWidgets(
    'pending guest claim starts no read and a late old venue cannot replace the new venue',
    (tester) async {
      final old = Completer<VenueOwnerGuestsResponse>();
      final repo = _Owner()
        ..guests = (id) =>
            id == 'a' ? old.future : Future.value(_guests('Guest B'));
      await tester.pumpWidget(
        MaterialApp(
          home: VenueOwnerGuestsPage(
            venueId: 'a',
            isPendingClaim: true,
            repository: repo,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.guestCalls, isEmpty);
      await tester.pumpWidget(
        MaterialApp(
          home: VenueOwnerGuestsPage(venueId: 'a', repository: repo),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VenueOwnerGuestsPage(venueId: 'b', repository: repo),
        ),
      );
      await tester.pumpAndSettle();
      old.complete(_guests('Guest A'));
      await tester.pumpAndSettle();
      expect(find.text('Guest B'), findsOneWidget);
      expect(find.text('Guest A'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
