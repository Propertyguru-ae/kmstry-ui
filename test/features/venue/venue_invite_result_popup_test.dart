import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

class _Members extends VenueMemberRepository {
  @override
  Future<List<VenueRole>> getRoles(String venueId) async => const [
    VenueRole(
      id: 'STAFF',
      name: 'Staff',
      isSystem: true,
      isOwnerRole: false,
      permissions: {},
      memberCount: 0,
    ),
  ];
}

class _Invites extends VenueInviteRepository {
  _Invites(this.type, {this.seatsFull = false});
  final InviteResultType type;
  final bool seatsFull;
  int calls = 0;

  @override
  Future<InviteResult> createInvite({
    required String venueId,
    required String email,
    required VenueMemberRole role,
    String? venueRoleId,
    int expiresInDays = 7,
  }) async {
    calls++;
    if (seatsFull) {
      throw ApiException(
        statusCode: 403,
        data: {'error': 'PLAN_MEMBER_LIMIT_REACHED', 'limit': 3},
      );
    }
    return InviteResult(
      type: type,
      email: email,
      role: 'STAFF',
      inviteUrl: type == InviteResultType.linkCreated
          ? 'https://kmstry.app/invite/abc123'
          : null,
    );
  }
}

Future<void> _sendInvite(
  WidgetTester tester,
  _Invites invites, {
  bool dark = true,
  String email = 'hilal@example.com',
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: VenueAddMemberPage(
        venueId: 'venue-1',
        repo: _Members(),
        inviteRepository: invites,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('Invite Link'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
  await tester.tap(find.text('Send Invite'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a join request opens the standard popup and resets the form', (
    tester,
  ) async {
    final invites = _Invites(InviteResultType.existingUserRequestSent);
    await _sendInvite(tester, invites);

    expect(invites.calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('Request sent'), findsOneWidget);
    expect(find.byIcon(Icons.mark_email_read_rounded), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    // Ready for the next invite.
    expect(find.text('hilal@example.com'), findsNothing);
    expect(find.text('Send Invite'), findsOneWidget);
  });

  for (final (type, title) in [
    (InviteResultType.alreadyMember, 'Already a member'),
    (InviteResultType.alreadyInvited, 'Invite pending'),
  ]) {
    testWidgets('$type is explained in the standard popup', (tester) async {
      await _sendInvite(tester, _Invites(type), dark: false);
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
    });
  }

  testWidgets(
    'a new invite link is shown only in the popup and can be copied there',
    (tester) async {
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

      await _sendInvite(tester, _Invites(InviteResultType.linkCreated));

      expect(find.text('Invite link ready'), findsWidgets);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.text('https://kmstry.app/invite/abc123'),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Copy link'));
      await tester.pump();
      expect(copied, 'https://kmstry.app/invite/abc123');
      // Let the "Link copied" toast finish.
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsNothing);
      // No second copy of the result on the page; the form is ready again.
      expect(find.text('Invite link ready'), findsNothing);
      expect(find.text('Copy Link'), findsNothing);
      expect(find.text('hilal@example.com'), findsNothing);
      expect(find.text('Send Invite'), findsOneWidget);
    },
  );

  testWidgets(
    'closing the link popup without copying lets the same email be invited again',
    (tester) async {
      final invites = _Invites(InviteResultType.linkCreated);
      await _sendInvite(tester, invites);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'hilal@example.com',
      );
      await tester.tap(find.text('Send Invite'));
      await tester.pumpAndSettle();

      expect(invites.calls, 2);
      expect(find.text('Invite link ready'), findsOneWidget);
    },
  );

  testWidgets('an invalid email is rejected without sending', (tester) async {
    final invites = _Invites(InviteResultType.existingUserRequestSent);
    await _sendInvite(tester, invites, email: 'not-an-email');
    expect(invites.calls, 0);
    expect(find.text('Please enter a valid email address.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'a full plan explains the seat limit instead of a generic error',
    (tester) async {
      await _sendInvite(
        tester,
        _Invites(InviteResultType.linkCreated, seatsFull: true),
      );
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('No seats left'), findsOneWidget);
      expect(find.textContaining('up to 3 team accounts'), findsOneWidget);
      expect(find.text('Upgrade'), findsOneWidget);

      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      // The email stays so it can be sent after a seat frees up.
      expect(find.text('hilal@example.com'), findsOneWidget);
    },
  );
}
