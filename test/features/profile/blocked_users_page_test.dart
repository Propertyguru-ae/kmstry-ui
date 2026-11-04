import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/friendship_changes.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/blocked_users_page.dart';

class _Matches extends MatchRepository {
  @override
  Future<List<BlockedUser>> getBlockedUsers() async => [
    BlockedUser(userId: 'bob', fullName: 'Bob'),
  ];
}

class _Checkins extends CheckinRepository {
  final unblocked = <String>[];
  bool fail = false;

  @override
  Future<void> unblockUser(String targetUserId) async {
    if (fail) throw Exception('offline');
    unblocked.add(targetUserId);
  }
}

Future<void> _openConfirm(WidgetTester tester, _Checkins checkins) async {
  await tester.pumpWidget(
    MaterialApp(
      home: BlockedUsersPage(
        repository: _Matches(),
        checkinRepository: checkins,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(TextButton, 'Unblock'));
  await tester.pumpAndSettle();
  expect(find.text('Unblock this user?'), findsOneWidget);
}

void main() {
  testWidgets('Unblock asks first; Cancel changes nothing', (tester) async {
    final checkins = _Checkins();
    await _openConfirm(tester, checkins);
    expect(checkins.unblocked, isEmpty);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(checkins.unblocked, isEmpty);
    expect(find.text('Bob'), findsOneWidget);
    expect(find.byType(BrandedNoticeCard), findsNothing);
  });

  testWidgets('confirming removes the person and shows the standard card', (
    tester,
  ) async {
    final checkins = _Checkins();
    final revision = FriendshipChanges.revision;
    await _openConfirm(tester, checkins);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(checkins.unblocked, ['bob']);
    expect(FriendshipChanges.revision, revision + 1);
    expect(find.text('Bob'), findsNothing);
    expect(find.text('No blocked users'), findsOneWidget);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User unblocked'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failed unblock keeps the person and says so', (tester) async {
    final checkins = _Checkins()..fail = true;
    await _openConfirm(tester, checkins);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'Could not unblock user'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextButton, 'Unblock'), findsOneWidget);
  });
}
