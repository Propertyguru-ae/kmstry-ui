import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/auth_api.dart';
import 'package:kmstry_frontend/features/auth/data/personal_onboarding_progress.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_gate_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/bio_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/gender_interest_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/photo_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/personal_onboarding_flow.dart';
import 'package:kmstry_frontend/features/profile/presentation/manage_accounts_page.dart';

const _paused = <String, dynamic>{
  'id': 'fixture',
  'fullName': 'Invited Member',
  'username': 'fixture.member',
  'birthdate': '1990-01-02',
  'onboardingStep': 'BIO',
  'hasPersonalProfile': true,
  'hasVenueMembership': true,
  'lastActiveContext': 'PERSONAL',
  'homeRoute': 'PERSONAL_ONBOARDING',
  'activeVenueId': 'alpha',
  'memberVenues': [
    {'id': 'alpha', 'name': 'Alpha', 'status': 'ACTIVE', 'role': 'ADMIN'},
  ],
};

class _Auth extends AuthRepository {
  Map<String, dynamic> me = Map.of(_paused);
  int uploads = 0;
  int saves = 0;
  bool fail = false;
  @override
  Future<bool> restoreSession() async => true;
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async =>
      Map.of(me);
  @override
  Future<Map<String, dynamic>> switchContext({
    required String lastActiveContext,
    String? activeVenueId,
  }) async {
    me['lastActiveContext'] = lastActiveContext;
    return Map.of(me);
  }

  @override
  Future<void> upsertPersonalProfile(Map<String, dynamic> data) async {
    saves++;
    me.addAll(data);
    me['onboardingStep'] = data.containsKey('bio')
        ? 'GENDER_INTEREST'
        : 'PHOTO';
  }

  @override
  Future<void> updateMe(Map<String, dynamic> data) async {
    if (fail) throw StateError('offline');
    saves++;
    me['onboardingStep'] = 'PERMISSIONS';
  }

  @override
  Future<void> uploadProfilePhoto(File file) async {
    uploads++;
    if (fail) throw StateError('upload failed');
  }
}

class _Api extends AuthApi {
  int saves = 0;
  int mirrors = 0;
  @override
  Future<Map<String, dynamic>> upsertPersonalProfile({
    required String accessToken,
    required Map<String, dynamic> data,
  }) async {
    saves++;
    return {};
  }

  @override
  Future<Map<String, dynamic>> updateMe({
    required String accessToken,
    required Map<String, dynamic> data,
  }) async {
    mirrors++;
    return {};
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'access_token': 'fixture'});
  });
  Future<void> open(WidgetTester tester, Widget widget, _Auth auth) async {
    tester.view.physicalSize = const Size(800, 1050);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: widget,
        routes: {AuthRoutes.authGate: (_) => AuthGatePage(repository: auth)},
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  test('row existence does not complete onboarding; required fields win', () {
    expect(personalOnboardingStep(_paused), 'BIO');
    expect(
      personalOnboardingStep({..._paused, 'onboardingStep': 'COMPLETED'}),
      'GENDER_INTEREST',
    );
    expect(
      personalOnboardingStep({
        ..._paused,
        'onboardingStep': 'COMPLETED',
        'gender': 'female',
        'interestedIn': 'everyone',
      }),
      isNull,
    );
    expect(
      personalOnboardingStep({
        ..._paused,
        'fullName': null,
        'registrationName': 'Private',
      }),
      'NAME_DOB',
    );
  });

  test(
    'one atomic profile write; no delayed mirror can rewind onboarding',
    () async {
      final api = _Api();
      await AuthRepository(api: api).upsertPersonalProfile({
        'fullName': 'Member',
        'birthdate': '1990-01-02',
      });
      await Future<void>.delayed(Duration.zero);
      expect(api.saves, 1);
      expect(api.mirrors, 0);
    },
  );

  testWidgets('paused personal has Finish setup and resumes bio then gender', (
    tester,
  ) async {
    final auth = _Auth();
    auth.me['lastActiveContext'] = 'VENUE';
    await open(tester, ManageAccountsPage(repository: auth), auth);
    expect(find.text('Personal · Finish setup'), findsOneWidget);
    await tap(tester, 'Finish setup');
    expect(find.byType(BioOnboardingPage), findsOneWidget);
    await tap(tester, 'Skip');
    expect(find.byType(GenderInterestOnboardingPage), findsOneWidget);
    await tap(tester, 'Female');
    await tap(tester, 'Everyone');
    await tap(tester, 'Continue');
    expect(find.byType(PhotoOnboardingPage), findsOneWidget);
    expect(auth.me['gender'], 'female');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Back to venue from bio pauses without saving/completing personal',
    (tester) async {
      final auth = _Auth();
      var cancelled = false;
      await open(
        tester,
        PersonalOnboardingFlow(
          startAt: OnboardingFlowStep.bio,
          repository: auth,
          nameDobCompleted: true,
          onCancel: () {
            cancelled = true;
          },
        ),
        auth,
      );
      await tap(tester, 'Back to venue');
      expect(cancelled, isTrue);
      expect(auth.saves, 0);
      expect(auth.me['onboardingStep'], 'BIO');
      await tester.pumpWidget(const SizedBox());
      await open(tester, AuthGatePage(repository: auth), auth);
      expect(find.byType(BioOnboardingPage), findsOneWidget);
    },
  );

  testWidgets('stale COMPLETED flag cannot skip missing gender/interest', (
    tester,
  ) async {
    final auth = _Auth();
    auth.me['onboardingStep'] = 'COMPLETED';
    await open(tester, AuthGatePage(repository: auth), auth);
    expect(find.byType(GenderInterestOnboardingPage), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed photo skip stays put; retry advances once', (
    tester,
  ) async {
    final auth = _Auth()..fail = true;
    var advanced = 0;
    await open(
      tester,
      PhotoOnboardingPage(
        repository: auth,
        onContinue: () {
          advanced++;
        },
      ),
      auth,
    );
    await tap(tester, 'Skip');
    expect(advanced, 0);
    expect(find.textContaining('Could not save this step'), findsOneWidget);
    auth.fail = false;
    await tap(tester, 'Skip');
    expect(advanced, 1);
    expect(auth.uploads, 0);
  });

  test(
    'Skip ignores even a selected file; upload failure propagates',
    () async {
      final auth = _Auth();
      await auth.completePhotoOnboarding(
        image: File('/unused-fixture.jpg'),
        skip: true,
      );
      expect(auth.uploads, 0);
      expect(auth.saves, 1);
      auth.fail = true;
      await expectLater(
        auth.completePhotoOnboarding(image: File('/unused-fixture.jpg')),
        throwsStateError,
      );
      expect(auth.uploads, 1);
    },
  );
}
