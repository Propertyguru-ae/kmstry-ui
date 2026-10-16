import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/data/registration_prefill.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/manage_accounts_page.dart';

const deferredMessage =
    'Your personal profile isn’t ready yet. Allow safety checks to continue.';
const inviteMe = <String, dynamic>{
  'id': 'invited',
  'registrationName': 'Invited Member',
  'birthdate': '1990-01-02T00:00:00.000Z',
  'fullName': null,
  'hasPersonalProfile': false,
  'lastActiveContext': 'VENUE',
  'hasVenueMembership': true,
  'activeVenueId': 'alpha',
  'memberVenues': [
    {'id': 'alpha', 'name': 'Alpha', 'role': 'ADMIN', 'status': 'ACTIVE'},
  ],
};

class FakeAuth extends AuthRepository {
  FakeAuth(this.me);
  Map<String, dynamic> me;
  Completer<Map<String, dynamic>>? pending;
  final saves = <Map<String, dynamic>>[];
  final switches = <String>[];
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async =>
      pending == null ? me : pending!.future;
  @override
  Future<void> upsertPersonalProfile(Map<String, dynamic> data) async {
    saves.add(Map.of(data));
  }

  @override
  Future<List<String>> getUsernameSuggestions(String base) async => [];
  @override
  Future<Map<String, dynamic>> switchContext({
    required String lastActiveContext,
    String? activeVenueId,
  }) async {
    switches.add('$lastActiveContext:$activeVenueId');
    return {};
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    SharedPreferences.setMockInitialValues({});
    PublicContentPermission.onRequired = (_) async {};
  });
  tearDown(() {
    PublicContentPermission.onRequired = null;
  });
  Future<void> open(
    WidgetTester tester,
    Widget page, {
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: page,
        routes: {
          AuthRoutes.authGate: (_) =>
              const Scaffold(body: Text('Returned to gate')),
        },
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final target = find.text(label);
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  test('private prefill alone never counts as a personal profile', () {
    expect(MeContextModel.fromMe(inviteMe).hasPersonalProfile, false);
  });

  RegistrationPrefill prefill([Map<String, dynamic>? me]) =>
      RegistrationPrefill.fromMe(
        me ?? inviteMe,
        sessionRevision: SecureStorage.sessionRevision,
      );

  testWidgets('existing account data paints before a slow background read', (
    tester,
  ) async {
    final auth = FakeAuth(Map.of(inviteMe))..pending = Completer();
    await open(
      tester,
      NameDobOnboardingPage(repository: auth, registrationPrefill: prefill()),
    );
    expect(auth.pending!.isCompleted, false);
    expect(find.text('Invited Member'), findsOneWidget);
    expect(find.text('01/02/1990'), findsOneWidget);
    expect(find.text('Back to venue'), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Invited Member'), findsOneWidget);
    auth.pending!.complete({
      ...inviteMe,
      'registrationName': 'Updated Member',
      'birthdate': '1991-02-03T00:00:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.text('Updated Member'), findsOneWidget);
    expect(find.text('02/03/1991'), findsOneWidget);
    expect(auth.saves, isEmpty);
  });

  testWidgets('background refresh cannot overwrite edited name or birthday', (
    tester,
  ) async {
    final auth = FakeAuth(Map.of(inviteMe))..pending = Completer();
    await open(
      tester,
      NameDobOnboardingPage(repository: auth, registrationPrefill: prefill()),
    );
    await tester.enterText(find.byType(TextField), 'Typed name');
    await tap(tester, '01/02/1990');
    await tap(tester, '15');
    await tap(tester, 'OK');
    auth.pending!.complete({
      ...inviteMe,
      'registrationName': 'Server name',
      'birthdate': '1991-02-03T00:00:00Z',
    });
    await tester.pumpAndSettle();
    expect(find.text('Typed name'), findsOneWidget);
    expect(find.text('01/15/1990'), findsOneWidget);
    await tap(tester, 'Continue');
    expect(auth.saves.single['fullName'], 'Typed name');
    expect(auth.saves.single['birthdate'], startsWith('1990-01-15'));
  });

  testWidgets('old-login defaults never paint in a new session', (
    tester,
  ) async {
    final old = prefill();
    await tester.runAsync(
      () => SecureStorage.saveTokens(
        accessToken: 'replacement-account',
        refreshToken: 'replacement-refresh',
      ),
    );
    final auth = FakeAuth({})..pending = Completer();
    await open(
      tester,
      NameDobOnboardingPage(repository: auth, registrationPrefill: old),
    );
    expect(find.text('Invited Member'), findsNothing);
    expect(find.text('01/02/1990'), findsNothing);
    expect(find.text('Back to venue'), findsNothing);
    auth.pending!.complete({'registrationName': 'New account'});
    await tester.pumpAndSettle();
    expect(find.text('New account'), findsOneWidget);
  });

  testWidgets(
    'Manage Accounts forwards defaults without waiting for another read',
    (tester) async {
      final auth = FakeAuth(Map.of(inviteMe));
      await open(tester, ManageAccountsPage(repository: auth));
      auth.pending = Completer();
      await tap(tester, 'Add Personal Account');
      expect(auth.pending!.isCompleted, false);
      expect(find.text('Invited Member'), findsOneWidget);
      expect(find.text('01/02/1990'), findsOneWidget);
      auth.pending!.complete(inviteMe);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'invite prefill and Not now preserve draft at $width; accepting resumes',
      (tester) async {
        final auth = FakeAuth(Map.of(inviteMe));
        var allowed = false;
        var continued = 0;
        PublicContentPermission.onRequired = (_) async {
          if (!allowed) {
            throw ApiException(
              statusCode: 403,
              data: {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
            );
          }
        };
        await open(
          tester,
          NameDobOnboardingPage(
            repository: auth,
            onContinue: () => continued++,
          ),
          width: width,
        );
        expect(find.text('Invited Member'), findsOneWidget);
        expect(find.text('01/02/1990'), findsOneWidget);
        expect(auth.saves, isEmpty);
        await tester.enterText(find.byType(TextField), 'My chosen public name');
        await tap(tester, 'Continue');
        expect(auth.saves, isEmpty);
        expect(continued, 0);
        expect(find.text(deferredMessage), findsOneWidget);
        expect(find.text('My chosen public name'), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.text('Back to venue'), findsOneWidget);
        allowed = true;
        await tap(tester, 'Review permission');
        expect(auth.saves.single['fullName'], 'My chosen public name');
        expect(continued, 1);
        expect(find.text(deferredMessage), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Back to venue restores venue context without creating a profile',
    (tester) async {
      final auth = FakeAuth(Map.of(inviteMe));
      await open(tester, NameDobOnboardingPage(repository: auth));
      await tap(tester, 'Back to venue');
      expect(auth.switches, ['VENUE:alpha']);
      expect(auth.saves, isEmpty);
      expect(find.text('Returned to gate'), findsOneWidget);
    },
  );

  testWidgets('late prefill does not overwrite a name already being edited', (
    tester,
  ) async {
    final auth = FakeAuth(Map.of(inviteMe))..pending = Completer();
    await open(tester, NameDobOnboardingPage(repository: auth));
    await tester.enterText(find.byType(TextField), 'Typed first');
    auth.pending!.complete(inviteMe);
    await tester.pumpAndSettle();
    expect(find.text('Typed first'), findsOneWidget);
    expect(find.text('01/02/1990'), findsOneWidget);
  });

  testWidgets(
    'existing public name takes priority over provider prefill; missing DOB stays empty',
    (tester) async {
      final auth = FakeAuth({
        'fullName': 'My Edited Name',
        'registrationName': 'Google Name',
      });
      await open(tester, NameDobOnboardingPage(repository: auth));
      expect(find.text('My Edited Name'), findsOneWidget);
      expect(find.text('Google Name'), findsNothing);
      expect(find.text('Finish later'), findsOneWidget);
      await tap(tester, 'Continue');
      expect(auth.saves, isEmpty);
    },
  );

  testWidgets(
    'normal signup username Not now stays editable and resumes on acceptance',
    (tester) async {
      final auth = FakeAuth({});
      var allowed = false;
      var continued = 0;
      PublicContentPermission.onRequired = (_) async {
        if (!allowed) {
          throw ApiException(
            statusCode: 403,
            data: {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
          );
        }
      };
      await open(
        tester,
        UsernameOnboardingPage(
          repository: auth,
          initialUsername: 'new_user',
          onContinue: () => continued++,
        ),
      );
      await tap(tester, 'Continue');
      expect(auth.saves, isEmpty);
      expect(find.text(deferredMessage), findsOneWidget);
      expect(find.text('new_user'), findsOneWidget);
      expect(find.text('Finish later'), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      allowed = true;
      await tap(tester, 'Review permission');
      expect(auth.saves.single['username'], 'new_user');
      expect(continued, 1);
    },
  );

  testWidgets('a late prefill from a previous login is ignored', (
    tester,
  ) async {
    final auth = FakeAuth(Map.of(inviteMe))..pending = Completer();
    await open(tester, NameDobOnboardingPage(repository: auth));
    await tester.runAsync(
      () => SecureStorage.saveTokens(
        accessToken: 'other-user',
        refreshToken: 'other-refresh',
      ),
    );
    auth.pending!.complete(inviteMe);
    await tester.pumpAndSettle();
    expect(find.text('Invited Member'), findsNothing);
    expect(find.text('Back to venue'), findsNothing);
    expect(auth.saves, isEmpty);
  });

  testWidgets(
    'permission completing after account change never submits the old form',
    (tester) async {
      final auth = FakeAuth(Map.of(inviteMe));
      final permission = Completer<void>();
      PublicContentPermission.onRequired = (_) => permission.future;
      await open(tester, NameDobOnboardingPage(repository: auth));
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      await tester.runAsync(
        () => SecureStorage.saveTokens(
          accessToken: 'different-user',
          refreshToken: 'different-refresh',
        ),
      );
      permission.complete();
      await tester.pump();
      expect(auth.saves, isEmpty);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
