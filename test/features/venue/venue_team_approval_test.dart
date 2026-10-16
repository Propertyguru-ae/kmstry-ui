import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

class _Members extends VenueMemberRepository {
  String? code = 'VENUE_APPROVAL_REQUIRED';
  Future<List<VenueMember>> Function(String)? readMembers;
  Future<List<VenueRole>> Function(String)? readRoles;

  @override
  Future<List<VenueMember>> getMembers(String venueId) async {
    if (readMembers != null) return readMembers!(venueId);
    if (code != null)
      throw ApiException(statusCode: 403, data: {'errorCode': code});
    return [_member];
  }

  @override
  Future<List<VenueRole>> getRoles(String venueId) async {
    if (readRoles != null) return readRoles!(venueId);
    if (code != null)
      throw ApiException(statusCode: 403, data: {'errorCode': code});
    return [];
  }
}

class _Invites extends VenueInviteRepository {
  @override
  Future<List<CreatedInvite>> listInvites(String venueId) async => [];
}

final _member = VenueMember(
  id: 'owner',
  role: VenueMemberRole.owner,
  status: VenueMemberStatus.active,
  createdAt: '2026-10-16T08:00:00Z',
  user: VenueMemberUser(id: 'owner', fullName: 'Active Owner'),
  isSelf: true,
);

Widget _app(_Members repo, {String venue = 'venue-a'}) => MaterialApp(
  theme: AppTheme.darkTheme,
  home: VenueTeamPage(
    venueId: venue,
    callerRole: VenueMemberRole.owner,
    repository: repo,
    inviteRepository: _Invites(),
  ),
);

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  for (final entry in {
    'VENUE_APPROVAL_REQUIRED': 'Venue approval pending',
    'VENUE_CLAIM_REJECTED': 'Venue request not approved',
  }.entries) {
    testWidgets('${entry.key} is a locked notice, not a team load error', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = _Members()..code = entry.key;
      await tester.pumpWidget(_app(repo));
      await tester.pumpAndSettle();
      expect(find.text(entry.value), findsOneWidget);
      expect(find.text('Check status'), findsOneWidget);
      expect(find.text('Failed to load team.'), findsNothing);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Add Member'), findsNothing);
      expect(find.text('Upgrade to add staff'), findsNothing);
      expect(find.text('Active Owner'), findsNothing);
      expect(find.byTooltip('Member options'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('check status opens the normal team only after approval', (
    tester,
  ) async {
    final repo = _Members();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    repo.code = null;
    await tester.tap(find.text('Check status'));
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsNothing);
    expect(find.text('Active Owner'), findsOneWidget);
    // Approval restores the team, but must not bypass the FREE seat limit.
    expect(find.text('Upgrade to add staff'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending roles cannot be overwritten by a late member read', (
    tester,
  ) async {
    final lateMembers = Completer<List<VenueMember>>();
    final repo = _Members()..readMembers = (_) => lateMembers.future;
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsOneWidget);
    lateMembers.complete([_member]);
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsOneWidget);
    expect(find.text('Active Owner'), findsNothing);
    expect(find.text('Add Member'), findsNothing);
  });

  testWidgets('claim denial clears a previously loaded team on refresh', (
    tester,
  ) async {
    final repo = _Members()..code = null;
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Active Owner'), findsOneWidget);
    repo.code = 'VENUE_APPROVAL_REQUIRED';
    await tester
        .widget<RefreshIndicator>(find.byType(RefreshIndicator))
        .onRefresh();
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsOneWidget);
    expect(find.text('Active Owner'), findsNothing);
    expect(find.text('Add Member'), findsNothing);
  });

  testWidgets('another venue does not inherit the pending notice', (
    tester,
  ) async {
    final repo = _Members();
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsOneWidget);
    repo.code = null;
    await tester.pumpWidget(_app(repo, venue: 'venue-b'));
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsNothing);
    expect(find.text('Active Owner'), findsOneWidget);
  });

  testWidgets('a network failure is not presented as pending approval', (
    tester,
  ) async {
    final repo = _Members()
      ..code = null
      ..readMembers = (_) async => throw StateError('offline');
    await tester.pumpWidget(_app(repo));
    await tester.pumpAndSettle();
    expect(find.text('Failed to load team.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Venue approval pending'), findsNothing);
    repo.readMembers = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Active Owner'), findsOneWidget);
  });

  testWidgets('a late old-venue claim denial cannot lock the new venue', (
    tester,
  ) async {
    final old = Completer<List<VenueMember>>();
    final repo = _Members()
      ..code = null
      ..readMembers = (id) =>
          id == 'venue-a' ? old.future : Future.value([_member]);
    await tester.pumpWidget(_app(repo));
    await tester.pump();
    await tester.pumpWidget(_app(repo, venue: 'venue-b'));
    await tester.pumpAndSettle();
    old.completeError(
      ApiException(
        statusCode: 403,
        data: {'errorCode': 'VENUE_APPROVAL_REQUIRED'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Venue approval pending'), findsNothing);
    expect(find.text('Active Owner'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
