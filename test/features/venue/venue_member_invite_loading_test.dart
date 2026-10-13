import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_member_invite_page.dart';

class _PendingRepository extends VenueMemberRepository {
  final accepting = Completer<void>();
  final declining = Completer<void>();
  int acceptCalls = 0;
  int declineCalls = 0;

  @override
  Future<void> acceptMemberInvite(String venueId, String memberId) {
    acceptCalls++;
    return accepting.future;
  }

  @override
  Future<void> declineMemberInvite(String venueId, String memberId) {
    declineCalls++;
    return declining.future;
  }
}

const _invite = MemberVenue(
  id: 'venue-1',
  membershipId: 'member-1',
  name: 'Cafe Alpha',
  role: 'STAFF',
  status: 'PENDING',
  inviterName: 'Handan',
);

Future<_PendingRepository> _open(
  WidgetTester tester, {
  bool dark = true,
}) async {
  final repository = _PendingRepository();
  // Phone-sized screen so the invite card is fully on screen.
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      home: VenueMemberInvitePage(
        pendingInvites: const [_invite],
        repository: repository,
      ),
    ),
  );
  await tester.pump();
  return repository;
}

void main() {
  testWidgets('accept shows the loader only on the accept button', (
    tester,
  ) async {
    final repository = await _open(tester);

    await tester.tap(find.text('Accept invitation'));
    await tester.pump();

    // Exactly one loader: it replaced the Accept label, Decline stays readable.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.text('Accept invitation'), findsNothing);

    // Decline is locked while accepting.
    await tester.tap(find.text('Decline'));
    await tester.pump();
    expect(repository.declineCalls, 0);
    expect(repository.acceptCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('decline shows the loader only on the decline button', (
    tester,
  ) async {
    final repository = await _open(tester, dark: false);

    await tester.tap(find.text('Decline'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Accept invitation'), findsOneWidget);
    expect(find.text('Decline'), findsNothing);

    await tester.tap(find.text('Accept invitation'));
    await tester.pump();
    expect(repository.acceptCalls, 0);
    expect(repository.declineCalls, 1);

    await tester.pumpWidget(const SizedBox());
  });
}
