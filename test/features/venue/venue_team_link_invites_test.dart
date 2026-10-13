import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

class _Members extends VenueMemberRepository {
  _Members({this.members, this.roles = const []});
  final List<VenueMember>? members;
  final List<VenueRole> roles;
  bool denied = false;

  @override
  Future<List<VenueMember>> getMembers(String venueId) async {
    if (denied) throw ApiException(statusCode: 403, data: {});
    return members ??
        [
          _member(
            'Owner Olivia',
            VenueMemberRole.owner,
            VenueMemberStatus.active,
          ),
          _member(
            'Sam Pending',
            VenueMemberRole.staff,
            VenueMemberStatus.pending,
          ),
        ];
  }

  @override
  Future<List<VenueRole>> getRoles(String venueId) async => roles;
}

class _Invites extends VenueInviteRepository {
  List<CreatedInvite> invites = [
    CreatedInvite(
      id: 'invite-1',
      token: 'tok1',
      inviteUrl: 'https://kmstry.app/invite/tok1',
      role: 'STAFF',
      email: 'newbie@example.com',
      expiresAt: DateTime.now()
          .add(const Duration(days: 5, hours: 1))
          .toUtc()
          .toIso8601String(),
    ),
  ];
  final revoked = <String>[];

  @override
  Future<List<CreatedInvite>> listInvites(String venueId) async => invites;

  @override
  Future<void> revokeInvite(String venueId, String inviteId) async {
    revoked.add(inviteId);
    invites = invites.where((i) => i.id != inviteId).toList();
  }
}

VenueMember _member(
  String name,
  VenueMemberRole role,
  VenueMemberStatus status, {
  bool? isSelf,
}) => VenueMember(
  id: name,
  isSelf: isSelf,
  role: role,
  status: status,
  createdAt: '2026-10-06T10:00:00Z',
  user: VenueMemberUser(id: name, fullName: name),
);

Future<_Invites> _open(
  WidgetTester tester, {
  _Members? members,
  VenueMemberRole callerRole = VenueMemberRole.owner,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final invites = _Invites();
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.darkTheme,
      home: VenueTeamPage(
        venueId: 'venue-1',
        callerRole: callerRole,
        repository: members ?? _Members(),
        inviteRepository: invites,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return invites;
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  for (final roleIds in [
    ['OWNER', 'ADMIN', 'STAFF', 'custom-role'],
    ['OWNER'],
    <String>[],
  ]) {
    testWidgets('invite dropdown never grants Owner: $roleIds', (tester) async {
      final roles = roleIds
          .map(
            (id) => VenueRole.fromJson({
              'id': id,
              'name': id,
              'isOwnerRole': id == 'OWNER',
              'isSystem': id != 'custom-role',
            }),
          )
          .toList();
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: VenueAddMemberPage(
            venueId: 'venue-1',
            repo: _Members(roles: roles),
            inviteRepository: _Invites(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Invite Link'));
      await tester.pumpAndSettle();
      if (roleIds.every((id) => id == 'OWNER')) {
        expect(find.byType(DropdownButtonFormField<VenueRole>), findsNothing);
        expect(tester.takeException(), isNull);
        return;
      }
      final dropdown = tester.widget<DropdownButtonFormField<VenueRole>>(
        find.byType(DropdownButtonFormField<VenueRole>),
      );
      final fieldState = tester.state<FormFieldState<VenueRole>>(
        find.byType(DropdownButtonFormField<VenueRole>),
      );
      final selectable = tester.widget<DropdownButton<VenueRole>>(
        find.descendant(
          of: find.byWidget(dropdown),
          matching: find.byType(DropdownButton<VenueRole>),
        ),
      );
      expect(
        selectable.items!.map((item) => item.value!.id),
        roleIds.where((id) => id != 'OWNER'),
      );
      expect(fieldState.value?.id, roleIds.contains('STAFF') ? 'STAFF' : null);
      expect(tester.takeException(), isNull);
    });
  }

  test(
    'membership identity is parsed without assuming unknown means another user',
    () {
      expect(VenueMember.fromJson({'isSelf': true}).isSelf, isTrue);
      expect(VenueMember.fromJson({'isSelf': false}).isSelf, isFalse);
      expect(VenueMember.fromJson({}).isSelf, isNull);
      expect(VenueMember.fromJson({'isSelf': 'false'}).isSelf, isNull);
    },
  );

  testWidgets(
    'own admin row stays visible with no actions; another member remains manageable',
    (tester) async {
      await _open(
        tester,
        members: _Members(
          members: [
            _member(
              'Yan',
              VenueMemberRole.admin,
              VenueMemberStatus.active,
              isSelf: true,
            ),
            _member(
              'Other member',
              VenueMemberRole.staff,
              VenueMemberStatus.active,
              isSelf: false,
            ),
          ],
        ),
      );
      expect(find.text('Yan'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('team-member-actions-Yan')),
        findsNothing,
      );
      expect(find.byTooltip('Member options'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('team-member-actions-Other member')),
      );
      await tester.pumpAndSettle();
      expect(find.text('Change Role'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('no management menu without confirmed caller identity', (
    tester,
  ) async {
    await _open(
      tester,
      members: _Members(
        members: [
          _member('Unknown', VenueMemberRole.admin, VenueMemberStatus.active),
        ],
      ),
    );
    expect(find.text('Unknown'), findsOneWidget);
    expect(find.byTooltip('Member options'), findsNothing);
  });

  testWidgets('read-only staff cannot manage another member', (tester) async {
    await _open(
      tester,
      callerRole: VenueMemberRole.staff,
      members: _Members(
        members: [
          _member(
            'Another admin',
            VenueMemberRole.admin,
            VenueMemberStatus.active,
            isSelf: false,
          ),
        ],
      ),
    );
    expect(find.text('Another admin'), findsOneWidget);
    expect(find.byTooltip('Member options'), findsNothing);
    expect(find.text('Add Member'), findsNothing);
  });

  testWidgets(
    'denied team refresh removes previously visible members and invitations',
    (tester) async {
      final members = _Members();
      await _open(tester, members: members);
      expect(find.text('Owner Olivia'), findsOneWidget);
      expect(find.text('newbie@example.com'), findsOneWidget);
      members.denied = true;
      await tester
          .widget<RefreshIndicator>(find.byType(RefreshIndicator))
          .onRefresh();
      await tester.pumpAndSettle();
      expect(find.text('Owner Olivia'), findsNothing);
      expect(find.text('newbie@example.com'), findsNothing);
      expect(find.text('Failed to load team.'), findsOneWidget);
      expect(find.text('Add Member'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('link invites are listed with in-app requests under Pending', (
    tester,
  ) async {
    await _open(tester);

    expect(find.text('newbie@example.com'), findsOneWidget);
    expect(find.text('Invite link · expires in 5 days'), findsOneWidget);
    // The in-app request has no link to copy.
    expect(find.text('Sam Pending'), findsOneWidget);
    expect(find.text('In-app request'), findsOneWidget);
    // The section title already says Pending.
    expect(find.text('Awaiting'), findsNothing);
    // Owner + in-app request + link: a pending link holds a seat too.
    expect(find.textContaining('3 / 1 seat used'), findsOneWidget);
  });

  testWidgets('Copy link puts the sent link on the clipboard again', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await _open(tester);

    await tester.tap(find.byTooltip('Invite options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(copied, 'https://kmstry.app/invite/tok1');
    // Let the "Link copied" toast finish.
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('Cancel invite revokes the link after confirmation', (
    tester,
  ) async {
    final invites = await _open(tester);

    await tester.tap(find.byTooltip('Invite options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel invite').last);
    await tester.pumpAndSettle();
    expect(find.text('Cancel invite?'), findsOneWidget);

    await tester.tap(find.text('Cancel invite').last);
    await tester.pumpAndSettle();
    expect(invites.revoked, ['invite-1']);
    expect(find.text('newbie@example.com'), findsNothing);
  });
}
