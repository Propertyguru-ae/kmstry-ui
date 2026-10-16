import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_gate_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/bio_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/manage_accounts_page.dart';

const _invitedMe = <String, dynamic>{
  'id': 'member',
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

/// Mirrors the backend's partial profile update: a username-only write keeps
/// the saved name/DOB and BIO step. No real account or database is modified.
class _Auth extends AuthRepository {
  _Auth(Map<String, dynamic> initial) : me = Map.of(initial);

  Map<String, dynamic> me;
  final saves = <Map<String, dynamic>>[];
  Object? nextSaveError;

  @override
  Future<bool> restoreSession() async => true;

  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async =>
      Map.of(me);

  @override
  Future<List<String>> getUsernameSuggestions(String base) async => [];

  @override
  Future<void> upsertPersonalProfile(Map<String, dynamic> data) async {
    final error = nextSaveError;
    nextSaveError = null;
    if (error != null) throw error;
    saves.add(Map.of(data));
    me = {
      ...me,
      ...data,
      'hasPersonalProfile': true,
      'lastActiveContext': 'PERSONAL',
      'homeRoute': 'PERSONAL_HOME',
      'nextAction': 'GO_TO_PERSONAL_HOME',
      if (data.containsKey('fullName') && data.containsKey('birthdate'))
        'onboardingStep': 'BIO',
    };
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    SharedPreferences.setMockInitialValues({});
    PublicContentPermission.onRequired = (_) async {};
  });
  tearDown(() => PublicContentPermission.onRequired = null);

  Future<void> open(WidgetTester tester, _Auth auth, {Widget? home}) async {
    // Route tests use a wide viewport because Flutter's Ahem test font makes
    // the existing bio suggestion chips artificially wide. Phone-width
    // name/DOB and permission layouts are covered in registration_identity_test.
    tester.view.physicalSize = const Size(800, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: home ?? AuthGatePage(repository: auth),
        routes: {AuthRoutes.authGate: (_) => AuthGatePage(repository: auth)},
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> saveUsername(WidgetTester tester) async {
    expect(find.byType(UsernameOnboardingPage), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'new.member');
    await tester.pump(const Duration(milliseconds: 350));
    await tap(tester, 'Continue');
  }

  void expectBio() {
    expect(find.byType(BioOnboardingPage), findsOneWidget);
    expect(find.byType(NameDobOnboardingPage), findsNothing);
    expect(find.byType(UsernameOnboardingPage), findsNothing);
  }

  testWidgets(
    'Add Personal: defer safety, save name/DOB, save username, then bio',
    (tester) async {
      final auth = _Auth(_invitedMe);
      var allowed = false;
      PublicContentPermission.onRequired = (_) async {
        if (!allowed) {
          throw ApiException(
            statusCode: 403,
            data: {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
          );
        }
      };
      await open(tester, auth, home: ManageAccountsPage(repository: auth));
      await tap(tester, 'Add Personal Account');
      expect(find.text('Invited Member'), findsOneWidget);
      expect(find.text('01/02/1990'), findsOneWidget);

      await tap(tester, 'Continue');
      expect(auth.saves, isEmpty);
      expect(find.byType(NameDobOnboardingPage), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);

      allowed = true;
      await tap(tester, 'Review permission');
      expect(auth.saves.single['fullName'], 'Invited Member');
      expect(find.byType(UsernameOnboardingPage), findsOneWidget);
      await saveUsername(tester);
      expectBio();
      expect(auth.saves, hasLength(2));
      expect(auth.saves.last, {'username': 'new.member'});
      expect(auth.me['fullName'], 'Invited Member');
      expect(auth.me['birthdate'], startsWith('1990-01-02'));
      expect(tester.takeException(), isNull);

      // A restart resumes at bio using persisted public data, with no reset.
      await tester.pumpWidget(const SizedBox.shrink());
      await open(tester, auth);
      expectBio();
      expect(auth.saves, hasLength(2));
    },
  );

  for (final source in ['email', 'Google', 'Apple']) {
    testWidgets('$source signup prefill still requires saving name/DOB', (
      tester,
    ) async {
      final auth = _Auth({
        'id': 'new-user',
        'registrationName': '$source Member',
        'birthdate': '1990-01-02',
        'fullName': null,
        'hasPersonalProfile': false,
        'homeRoute': 'PERSONAL_ONBOARDING',
        'onboardingStep': 'NAME_DOB',
      });
      await open(tester, auth);
      await saveUsername(tester);
      expect(find.byType(NameDobOnboardingPage), findsOneWidget);
      expect(find.text('$source Member'), findsOneWidget);
      expect(find.byType(BioOnboardingPage), findsNothing);
      expect(auth.saves.single, {'username': 'new.member'});

      await tap(tester, 'Continue');
      expectBio();
      expect(auth.saves.last['fullName'], '$source Member');
      expect(auth.saves, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('provider name without a birthday does not skip the date step', (
    tester,
  ) async {
    final auth = _Auth({
      'registrationName': 'Provider Member',
      'homeRoute': 'PERSONAL_ONBOARDING',
      'onboardingStep': 'NAME_DOB',
    });
    await open(tester, auth);
    await saveUsername(tester);
    expect(find.byType(NameDobOnboardingPage), findsOneWidget);
    expect(find.text('Provider Member'), findsOneWidget);
    await tap(tester, 'Continue');
    expect(auth.saves, hasLength(1));
    expect(find.byType(BioOnboardingPage), findsNothing);
  });

  for (final publicNameKey in ['fullName', 'full_name']) {
    testWidgets('saved $publicNameKey and DOB are not requested twice', (
      tester,
    ) async {
      final auth = _Auth({
        publicNameKey: 'Saved Member',
        'birthdate': '1990-01-02',
        'homeRoute': 'PERSONAL_HOME',
        'onboardingStep': 'BIO',
        'hasPersonalProfile': true,
      });
      await open(tester, auth);
      await saveUsername(tester);
      expectBio();
      expect(auth.saves.single, {'username': 'new.member'});
    });
  }

  testWidgets('username rejection stays on username and retry reaches bio', (
    tester,
  ) async {
    final auth =
        _Auth({
            'fullName': 'Saved Member',
            'birthdate': '1990-01-02',
            'homeRoute': 'PERSONAL_HOME',
            'onboardingStep': 'BIO',
            'hasPersonalProfile': true,
          })
          ..nextSaveError = ApiException(
            statusCode: 409,
            data: {'errorCode': 'USERNAME_ALREADY_IN_USE'},
          );
    await open(tester, auth);
    await saveUsername(tester);
    expect(auth.saves, isEmpty);
    expect(find.byType(UsernameOnboardingPage), findsOneWidget);
    expect(find.byType(BioOnboardingPage), findsNothing);
    expect(
      find.text('This username is already taken. Try another one.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField), 'another.member');
    await tester.pump(const Duration(milliseconds: 350));
    await tap(tester, 'Continue');
    expectBio();
    expect(auth.saves.single, {'username': 'another.member'});
  });

  testWidgets('back navigation keeps saved steps editable without duplicates', (
    tester,
  ) async {
    final auth = _Auth({
      'registrationName': 'Private Member',
      'birthdate': '1990-01-02',
      'homeRoute': 'PERSONAL_ONBOARDING',
      'onboardingStep': 'NAME_DOB',
    });
    await open(tester, auth);
    await saveUsername(tester);
    await tester.enterText(find.byType(TextField), 'My public name');
    await tap(tester, 'Continue');
    expectBio();

    Navigator.of(tester.element(find.byType(BioOnboardingPage))).pop();
    await tester.pumpAndSettle();
    expect(find.text('My public name'), findsOneWidget);
    expect(find.text('01/02/1990'), findsOneWidget);
    Navigator.of(tester.element(find.byType(NameDobOnboardingPage))).pop();
    await tester.pumpAndSettle();
    expect(find.byType(UsernameOnboardingPage), findsOneWidget);
    await tap(tester, 'Continue');
    expectBio();
    // Returning through username must not silently resubmit the saved name.
    expect(auth.saves.where((s) => s.containsKey('fullName')), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an unsuccessful name save never advances or completes the step',
    (tester) async {
      final auth = _Auth({
        'registrationName': 'Private Member',
        'birthdate': '1990-01-02',
        'homeRoute': 'PERSONAL_ONBOARDING',
        'onboardingStep': 'NAME_DOB',
      });
      await open(tester, auth);
      await saveUsername(tester);
      auth.nextSaveError = ApiException(statusCode: 503, data: {});
    await tester.tap(find.text('Continue'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
      expect(auth.saves, hasLength(1));
      expect(find.byType(BioOnboardingPage), findsNothing);
      await tap(tester, 'OK');
      Navigator.of(tester.element(find.byType(NameDobOnboardingPage))).pop();
      await tester.pumpAndSettle();
      await tap(tester, 'Continue');
      expect(find.byType(NameDobOnboardingPage), findsOneWidget);
      await tap(tester, 'Continue');
      expectBio();
      expect(auth.saves.where((s) => s.containsKey('fullName')), hasLength(1));
    },
  );
}
