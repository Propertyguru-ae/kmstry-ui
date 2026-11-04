import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/core/user/daily_undo_quota.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Profile details fail to refresh, so the page keeps the hinted action state.
class _Repo extends CheckinRepository {
  @override
  Future<PublicUserProfile> getPublicUserProfile(String userId) async =>
      throw ApiException(statusCode: 500, data: {'message': 'offline'});

  @override
  Future<Set<String>> getBlockedUserIds() async => <String>{};

  final actions = <String>[];
  Completer<void>? sending;
  Completer<void>? undoing;
  ApiException? undoError;

  @override
  Future<MatchItem?> sendFeedAction({
    required String targetUserId,
    String? venueId,
    required String action,
    ({String id, DateTime version})? interestNotice,
  }) async {
    actions.add(action);
    await sending?.future;
    return null;
  }

  final undone = <String>[];
  bool failUndo = false;

  @override
  Future<DailyUndoQuota?> undoAction(String targetUserId) async {
    undone.add(targetUserId);
    await undoing?.future;
    if (undoError != null) throw undoError!;
    if (failUndo) {
      throw ApiException(statusCode: 500, data: {'message': 'offline'});
    }
    return quotaAfterUndo;
  }

  DailyUndoQuota? quota, quotaAfterUndo;
  Completer<DailyUndoQuota?>? reading;
  int quotaReads = 0;
  @override
  Future<DailyUndoQuota?> getUndoQuota() async {
    quotaReads++;
    return reading == null ? quota : await reading!.future;
  }
}

class _Matches extends MatchRepository {
  Completer<MatchItem?>? checking;
  int calls = 0;
  @override
  Future<MatchItem?> getFriendship(String userId) async {
    calls++;
    return await checking?.future;
  }
}

Future<void> _pump(
  WidgetTester tester,
  ProfileActionState state, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
  _Repo? repo,
  _Matches? matches,
}) async {
  ProfilePreviewPage.clearActionStateCache();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: ProfilePreviewPage(
        userId: 'zeynep',
        userName: 'Zeynep',
        actionStateHint: state,
        checkinRepository: repo ?? _Repo(),
        matchRepository: matches ?? _Matches(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

BoxDecoration _decorationOf(WidgetTester tester, String label) {
  final ink = tester.widget<Ink>(
    find.ancestor(of: find.text(label), matching: find.byType(Ink)).first,
  );
  return ink.decoration! as BoxDecoration;
}

Rect _buttonRect(WidgetTester tester, String label) => tester.getRect(
  find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first,
);

void main() {
  tearDown(UserSession.instance.clear);
  for (final dark in [false, true]) {
    testWidgets('incoming interest explains the choice; dark=$dark', (
      tester,
    ) async {
      await _pump(
        tester,
        ProfileActionState.incomingInterested,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      expect(find.text('Interested in you'), findsOneWidget);
      expect(
        find.text('Choose Interested to match and start chatting.'),
        findsOneWidget,
      );
      expect(find.textContaining('caught their attention'), findsNothing);

      final prompt = tester.getCenter(find.text('Interested in you'));
      final helper = tester.getCenter(
        find.text('Choose Interested to match and start chatting.'),
      );
      expect(helper.dx, closeTo(195, 1));
      expect(prompt.dx, greaterThan(helper.dx - 12));

      final pass = _buttonRect(tester, 'Pass');
      final interested = _buttonRect(tester, 'Interested');
      expect(pass.size, interested.size);
      expect(pass.height, 48);
      expect(pass.top, interested.top);
      expect(pass.right, lessThan(interested.left));

      final primary = _decorationOf(tester, 'Interested');
      expect(primary.color, AppColors.blue);
      expect(primary.gradient, isNull);
      expect(primary.border, isNull);
      expect(primary.borderRadius, BorderRadius.circular(14));
      final secondary = _decorationOf(tester, 'Pass');
      expect(secondary.gradient, isNull);
      expect(secondary.color, isNot(AppColors.blue));
      expect(secondary.border, isNotNull);
      expect(secondary.borderRadius, BorderRadius.circular(14));
    });
  }

  testWidgets('without an incoming interest only the buttons show', (
    tester,
  ) async {
    await _pump(tester, ProfileActionState.showActions);
    expect(find.text('Interested in you'), findsNothing);
    expect(
      find.text('Choose Interested to match and start chatting.'),
      findsNothing,
    );
    expect(find.text('Pass'), findsOneWidget);
    expect(find.text('Interested'), findsOneWidget);
  });

  testWidgets('buttons fit a small screen with large text', (tester) async {
    await _pump(
      tester,
      ProfileActionState.incomingInterested,
      size: const Size(320, 640),
      textScale: 1.6,
    );
    // The test font is much wider than real fonts; only the action area is
    // under test here, so overflow elsewhere in the header is tolerated.
    final exception = tester.takeException();
    expect(exception == null || '$exception'.contains('overflowed'), isTrue);
    expect(
      tester.widget<Text>(find.text('Interested')).overflow,
      TextOverflow.ellipsis,
    );
    final pass = _buttonRect(tester, 'Pass');
    final interested = _buttonRect(tester, 'Interested');
    expect(pass.size, interested.size);
    expect(interested.right, lessThanOrEqualTo(320));
  });

  group('metered Undo', () {
    test(
      'old quota replies cannot restore a spent undo or affect a new login',
      () async {
        final member = UserSession.instance;
        final reset = DateTime.now().add(const Duration(hours: 1));
        member.recordUndoQuota(DailyUndoQuota(0, reset));
        member.recordUndoQuota(DailyUndoQuota(1, reset));
        expect(member.recentUndoQuota?.remaining, 0);
        member.applyFromMe({'isPremium': true});
        expect(member.recentUndoQuota, isNull);
        member.clear();
        final late = Completer<DailyUndoQuota?>();
        final reading = member.warmUndoQuota(() => late.future);
        member.clear();
        late.complete(DailyUndoQuota(0, reset));
        await reading;
        expect(member.recentUndoQuota, isNull);
      },
    );

    const limitMessage =
        "You've used all 3 daily undos included with your account. Try again tomorrow.";
    DailyUndoQuota quota(int remaining) =>
        DailyUndoQuota(remaining, DateTime.now().add(const Duration(hours: 1)));
    testWidgets(
      'a known last free undo responds on tap even while Interested is being sent',
      (tester) async {
        UserSession.instance.applyFromMe({'isPremium': false});
        final repo = _Repo()
          ..quota = quota(1)
          ..sending = Completer<void>()
          ..undoing = Completer<void>()
          ..quotaAfterUndo = quota(0);
        await _pump(tester, ProfileActionState.showActions, repo: repo);
        await tester.tap(find.text('Interested'));
        await tester.pump();
        await tester.tap(find.text('Undo').hitTestable());
        await tester.pump();
        expect(find.text('Pass').hitTestable(), findsOneWidget);
        expect(repo.undone, isEmpty);
        await tester.tap(find.text('Pass'));
        await tester.pump();
        repo.sending!.complete();
        await tester.pump();
        expect(repo.undone, ['zeynep']);
        expect(repo.actions, ['interested']);
        repo.undoing!.complete();
        await tester.pumpAndSettle();
        expect(repo.actions, ['interested', 'pass']);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(find.text(limitMessage), findsOneWidget);
        expect(find.text('Interested'), findsNothing);
        expect(repo.undone, ['zeynep']);
        expect(repo.quotaReads, 1);
      },
    );

    testWidgets(
      'known exhausted quota opens the sheet without sending an undo',
      (tester) async {
        final repo = _Repo()..quota = quota(0);
        await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(find.text(limitMessage), findsOneWidget);
        expect(find.text('Interested'), findsNothing);
        expect(find.text('Pass'), findsNothing);
        expect(repo.undone, isEmpty);
      },
    );

    testWidgets(
      'a fresher server denial wins over a cached allowance and a queued Pass',
      (tester) async {
        final repo = _Repo()
          ..quota = quota(1)
          ..undoing = Completer<void>()
          ..undoError = ApiException(
            statusCode: 403,
            data: {
              'error': 'REWIND_LIMIT_REACHED',
              'quota': {
                'remaining': 0,
                'resetsAt': quota(0).resetsAt.toUtc().toIso8601String(),
              },
            },
          );
        await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        await tester.tap(find.text('Pass'));
        repo.undoing!.complete();
        await tester.pumpAndSettle();
        expect(find.text(limitMessage), findsOneWidget);
        expect(find.text('Interest sent'), findsOneWidget);
        expect(repo.actions, isEmpty);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Undo'));
        await tester.pump();
        expect(repo.undone, ['zeynep']);
      },
    );

    testWidgets(
      'slow prefetch cannot overwrite a successful undo or block the tap',
      (tester) async {
        final repo = _Repo()
          ..reading = Completer<DailyUndoQuota?>()
          ..quotaAfterUndo = quota(0);
        await _pump(tester, ProfileActionState.proactivePass, repo: repo);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        repo.reading!.complete(quota(3));
        await tester.pump();
        expect(UserSession.instance.recentUndoQuota?.remaining, 0);
        expect(repo.undone, ['zeynep']);
      },
    );

    testWidgets('an expired quota cannot block a new day', (tester) async {
      final repo = _Repo()..quota = DailyUndoQuota(0, DateTime.utc(2020));
      await _pump(tester, ProfileActionState.proactivePass, repo: repo);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(repo.undone, ['zeynep']);
      expect(find.text('Interested'), findsOneWidget);
    });
    for (final (state, status) in [
      (ProfileActionState.waitingResponse, 'Interest sent'),
      (ProfileActionState.proactivePass, 'You passed'),
    ]) {
      for (final exhausted in [true, false]) {
        testWidgets(
          'free account keeps "$status" until the server replies; exhausted=$exhausted',
          (tester) async {
            UserSession.instance.applyFromMe({'isPremium': false});
            final repo = _Repo()..undoing = Completer<void>();
            if (exhausted) {
              repo.undoError = ApiException(
                statusCode: 403,
                data: {'error': 'REWIND_LIMIT_REACHED'},
              );
            }
            await _pump(tester, state, repo: repo);
            await tester.tap(find.text('Undo'));
            await tester.pump();
            expect(find.text('Interested'), findsNothing);
            expect(find.text('Pass'), findsNothing);
            expect(find.text(status), findsOneWidget);
            expect(find.byType(CircularProgressIndicator), findsNothing);
            await tester.tap(find.text('Undoing…'));
            await tester.pump(const Duration(seconds: 2));
            expect(repo.undone, ['zeynep']);
            expect(find.text('Interested'), findsNothing);
            expect(find.text('Pass'), findsNothing);
            repo.undoing!.complete();
            await tester.pumpAndSettle();
            if (exhausted) {
              expect(find.text(limitMessage), findsOneWidget);
              await tester.tap(find.text('Close'));
              await tester.pumpAndSettle();
              expect(find.text(status), findsOneWidget);
              expect(find.text('Interested'), findsNothing);
              expect(find.text('Pass'), findsNothing);
            } else {
              expect(find.text('Interested'), findsOneWidget);
              expect(find.text('Pass'), findsOneWidget);
              expect(find.text('Daily undo limit reached'), findsNothing);
            }
          },
        );
      }
    }
    for (final expired in [false, true]) {
      testWidgets(
        'unknown or expired membership waits and shows the server limit directly; expired=$expired',
        (tester) async {
          UserSession.instance.clear();
          if (expired) {
            UserSession.instance.applyFromMe({
              'isPremium': true,
              'premiumUntil': DateTime.utc(2000).toIso8601String(),
            });
          }
          final repo = _Repo()
            ..undoing = Completer<void>()
            ..undoError = ApiException(
              statusCode: 403,
              data: {'error': 'REWIND_LIMIT_REACHED'},
            );
          await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
          await tester.tap(find.text('Undo'));
          await tester.pump();
          expect(find.text('Interested'), findsNothing);
          repo.undoing!.complete();
          await tester.pumpAndSettle();
          expect(find.text(limitMessage), findsOneWidget);
          expect(UserSession.instance.loaded, expired);
        },
      );
    }
  });

  group('after choosing with KMSTRY+', () {
    setUp(() => UserSession.instance.applyFromMe({'isPremium': true}));
    const helper = 'If they choose Interested too, you can start chatting.';

    for (final dark in [false, true]) {
      testWidgets('Interest sent is a full-width bar; dark=$dark', (
        tester,
      ) async {
        await _pump(
          tester,
          ProfileActionState.waitingResponse,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        expect(find.text('Interest sent'), findsOneWidget);
        expect(find.text('Undo'), findsOneWidget);
        expect(find.text(helper), findsOneWidget);
        expect(find.text('Pass'), findsNothing);
        expect(find.text('Interested'), findsNothing);

        final bar = find
            .ancestor(
              of: find.text('Interest sent'),
              matching: find.byType(Container),
            )
            .first;
        final rect = tester.getRect(bar);
        expect(rect.height, 48);
        expect(rect.width, greaterThan(340));
        expect(
          tester.getCenter(find.text('Interest sent')).dx,
          lessThan(tester.getCenter(find.text('Undo')).dx),
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('You passed uses the same bar without the helper; '
          'dark=$dark', (tester) async {
        await _pump(
          tester,
          ProfileActionState.proactivePass,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        expect(find.text('You passed'), findsOneWidget);
        expect(find.text('You passed.'), findsNothing);
        expect(find.text('Undo'), findsOneWidget);
        expect(find.text(helper), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final (button, status, action) in [
      ('Interested', 'Interest sent', 'interested'),
      ('Pass', 'You passed', 'pass'),
    ]) {
      testWidgets('$button turns into the $status bar in place', (
        tester,
      ) async {
        FlutterSecureStorage.setMockInitialValues({});
        final repo = _Repo();
        await _pump(tester, ProfileActionState.showActions, repo: repo);
        final top = _buttonRect(tester, button).top;
        await tester.tap(find.text(button));
        await tester.pumpAndSettle();
        expect(repo.actions, [action]);
        expect(find.text(status), findsOneWidget);
        expect(find.text('Pass'), findsNothing);
        expect(find.text('Interested'), findsNothing);
        final bar = find
            .ancestor(of: find.text(status), matching: find.byType(Container))
            .first;
        expect(tester.getRect(bar).top, top);
      });
    }

    testWidgets(
      'Undo acknowledges immediately and serializes a slow send then one rewind',
      (tester) async {
        final repo = _Repo()
          ..sending = Completer<void>()
          ..undoing = Completer<void>();
        final matches = _Matches();
        await _pump(
          tester,
          ProfileActionState.showActions,
          repo: repo,
          matches: matches,
        );
        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();
        expect(repo.actions, ['interested']);
        final undo = find.ancestor(
          of: find.text('Undo'),
          matching: find.byWidgetPredicate((widget) => widget is TextButton),
        );
        expect(tester.widget<TextButton>(undo).onPressed, isNotNull);
        await tester.tap(undo);
        await tester.pump();
        expect(find.text('Undoing…'), findsNothing);
        expect(find.text('Pass').hitTestable(), findsOneWidget);
        expect(find.text('Interested').hitTestable(), findsOneWidget);
        expect(repo.undone, isEmpty);
        repo.sending!.complete();
        await tester.pump();
        expect(repo.undone, ['zeynep']);
        expect(find.text('Undoing…'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        repo.undoing!.complete();
        await tester.pumpAndSettle();
        expect(find.text('Interested'), findsOneWidget);
        expect(find.text('Pass'), findsOneWidget);
        expect(matches.calls, 1);
      },
    );

    testWidgets(
      'Undo stays available while the post-send friendship lookup is slow',
      (tester) async {
        final repo = _Repo();
        final matches = _Matches();
        await _pump(
          tester,
          ProfileActionState.showActions,
          repo: repo,
          matches: matches,
        );
        matches.checking = Completer<MatchItem?>();
        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();
        expect(matches.calls, 2);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect(repo.undone, ['zeynep']);
        matches.checking!.complete(
          MatchItem(matchId: 'stale', userId: 'zeynep', fullName: 'Zeynep'),
        );
        await tester.pumpAndSettle();
        expect(find.text('Interested'), findsOneWidget);
        expect(find.text('Message'), findsNothing);
      },
    );

    for (final cancelNext in [false, true]) {
      testWidgets(
        'new choice during Undo is responsive and ordered; cancelled=$cancelNext',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          final repo = _Repo()..undoing = Completer<void>();
          await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
          await tester.tap(find.text('Undo'));
          await tester.pump();
          await tester.tap(find.text('Pass'));
          await tester.pump();
          expect(find.text('You passed'), findsOneWidget);
          expect(repo.undone, ['zeynep']);
          expect(repo.actions, isEmpty);
          if (cancelNext) {
            await tester.tap(find.text('Undo'));
            await tester.pump();
            expect(find.text('Interested'), findsOneWidget);
          }
          repo.undoing!.complete();
          await tester.pumpAndSettle();
          expect(repo.actions, cancelNext ? isEmpty : ['pass']);
          expect(repo.undone, ['zeynep']);
          expect(
            find.text(cancelNext ? 'Interested' : 'You passed'),
            findsOneWidget,
          );
        },
      );
    }

    testWidgets(
      'a failed rewind restores the pending interest and discards the queued choice',
      (tester) async {
        final repo = _Repo()
          ..undoing = Completer<void>()
          ..failUndo = true;
        await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        await tester.tap(find.text('Pass'));
        await tester.pump();
        repo.undoing!.complete();
        await tester.pumpAndSettle();
        expect(repo.actions, isEmpty);
        expect(find.text('Interest sent'), findsOneWidget);
        expect(find.text('Could not undo. Please try again.'), findsOneWidget);
      },
    );

    testWidgets(
      'a choice queued during Undo is sent even if the profile closes',
      (tester) async {
        final repo = _Repo()..undoing = Completer<void>();
        await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
        await tester.tap(find.text('Undo'));
        await tester.pump();
        await tester.tap(find.text('Pass'));
        await tester.pumpWidget(const SizedBox.shrink());
        repo.undoing!.complete();
        await tester.pump();
        expect(repo.actions, ['pass']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a definitive send rejection does not spend a rewind', (
      tester,
    ) async {
      final repo = _Repo()..sending = Completer<void>();
      await _pump(tester, ProfileActionState.showActions, repo: repo);
      await tester.tap(find.text('Interested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      repo.sending!.completeError(
        ApiException(statusCode: 400, data: {'message': 'rejected'}),
      );
      await tester.pumpAndSettle();
      expect(repo.undone, isEmpty);
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('a lost send response still fulfills the requested undo', (
      tester,
    ) async {
      final repo = _Repo()..sending = Completer<void>();
      await _pump(tester, ProfileActionState.showActions, repo: repo);
      await tester.tap(find.text('Interested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      repo.sending!.completeError(Exception('connection lost after POST'));
      await tester.pumpAndSettle();
      expect(repo.undone, ['zeynep']);
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('acceptance winning the race preserves the match', (
      tester,
    ) async {
      final repo = _Repo()
        ..undoing = Completer<void>()
        ..undoError = ApiException(
          statusCode: 409,
          data: {'error': 'MATCH_EXISTS'},
        );
      await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.tap(find.text('Interested'));
      await tester.pump();
      repo.undoing!.complete();
      await tester.pumpAndSettle();
      expect(repo.actions, isEmpty);
      expect(find.text('Message'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(
        find.text('You have already matched. Use unmatch instead.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'a queued Undo completes after leaving the profile in the same session',
      (tester) async {
        final repo = _Repo()..sending = Completer<void>();
        await _pump(tester, ProfileActionState.showActions, repo: repo);
        await tester.tap(find.text('Interested'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Undo'));
        await tester.pumpWidget(const SizedBox.shrink());
        repo.sending!.complete();
        await tester.pump();
        expect(repo.undone, ['zeynep']);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('a queued Undo cannot run under a new login', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = _Repo()..sending = Completer<void>();
      await _pump(tester, ProfileActionState.showActions, repo: repo);
      await tester.tap(find.text('Interested'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Undo'));
      await tester.pump();
      await tester.tap(find.text('Pass'));
      await tester.pumpWidget(const SizedBox.shrink());
      await SecureStorage.saveTokens(
        accessToken: 'another-test-session',
        refreshToken: 'test',
      );
      repo.sending!.complete();
      await tester.pump();
      expect(repo.undone, isEmpty);
      expect(repo.actions, ['interested']);
    });

    testWidgets('Undo returns to the choice, once even with a second tap', (
      tester,
    ) async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = _Repo();
      await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
      await tester.tap(find.text('Undo'));
      await tester.pump();
      // The bar is still fading out; it must not take another tap.
      await tester.tap(find.text('Undo'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(repo.undone, ['zeynep']);
      expect(find.text('Interest sent'), findsNothing);
      expect(find.text('Pass'), findsOneWidget);
      expect(find.text('Interested'), findsOneWidget);
    });

    testWidgets('a failed Undo brings the bar back', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final repo = _Repo()..failUndo = true;
      await _pump(tester, ProfileActionState.waitingResponse, repo: repo);
      await tester.tap(find.text('Undo'));
      await tester.pumpAndSettle();
      expect(find.text('Could not undo. Please try again.'), findsOneWidget);
      expect(find.text('Interest sent'), findsOneWidget);
      expect(find.text('Pass'), findsNothing);
    });

    testWidgets('the bar fits a small screen with large text', (tester) async {
      await _pump(
        tester,
        ProfileActionState.waitingResponse,
        size: const Size(320, 640),
        textScale: 1.6,
      );
      // The wide test font can overflow the header; only this area is checked.
      final exception = tester.takeException();
      expect(exception == null || '$exception'.contains('overflowed'), isTrue);
      expect(find.text('Undo').hitTestable(), findsOneWidget);
      expect(
        tester.widget<Text>(find.text('Interest sent')).overflow,
        TextOverflow.ellipsis,
      );
      expect(tester.getRect(find.text('Undo')).right, lessThanOrEqualTo(320));
    });
  });
}
