import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/public_content_permission.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class _Auth extends AuthRepository {
  Map<String, dynamic> me = {
    'registrationName': 'Provider Name',
    'birthdate': '1990-01-02',
  };
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => me;
  @override
  Future<Map<String, dynamic>> switchContext({
    required String lastActiveContext,
    String? activeVenueId,
  }) async => {};
}

class _Venues extends VenueRepository {
  int step = 4;
  int submissions = 0;
  String? submittedName;
  String? submittedDob;
  bool fail = true;
  bool draftDeleted = false;
  @override
  Future<void> deleteClaimDraft() async {
    draftDeleted = true;
  }

  @override
  Future<Map<String, dynamic>?> getClaimDraft() async => {
    'current_step': step,
    'owner_phone': '+971501234567',
    'venue': {
      'id': 'venue',
      'name': 'Fixture Cafe',
      'city': 'Dubai',
      'isInDb': true,
    },
  };
  @override
  Future<Map<String, dynamic>> claimVenue({
    required String venueId,
    required String ownerNote,
    String? ownerFullName,
    String? ownerBirthdate,
    String? tradeLicenceUrl,
    String? ownerVideoUrl,
    bool hasDocuments = false,
  }) async {
    submissions++;
    submittedName = ownerFullName;
    submittedDob = ownerBirthdate;
    // Remain on the form, without shell navigation or real network writes.
    if (fail) throw StateError('fixture server unavailable');
    return {'claimId': 'fixture', 'status': 'PENDING'};
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'fixture'});
    SharedPreferences.setMockInitialValues({});
    PublicContentPermission.onRequired = (_) async {};
  });
  tearDown(() => PublicContentPermission.onRequired = null);
  Future<void> open(
    WidgetTester tester,
    _Auth auth,
    _Venues venues, {
    ThemeData? theme,
    Size size = const Size(800, 1100),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        routes: {
          AuthRoutes.authGate: (_) =>
              const Scaffold(body: Text('Claim received')),
        },
        home: VenueContextOnboardingPage(
          repository: venues,
          authRepository: auth,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }

  testWidgets('provider/private registration name and DOB prefill contact', (
    tester,
  ) async {
    final venues = _Venues()..step = 2;
    await open(tester, _Auth(), venues);
    expect(find.text('Provider Name'), findsOneWidget);
    expect(find.byKey(const ValueKey('claim-birthdate')), findsOneWidget);
    expect(find.text('02/01/1990'), findsOneWidget);
    expect(venues.submissions, 0);
  });

  testWidgets('missing DOB in an old review draft returns to contact', (
    tester,
  ) async {
    final auth = _Auth()..me = {'registrationName': 'Invited Name'};
    final venues = _Venues();
    await open(tester, auth, venues);
    expect(find.text('STEP 2 OF 4'), findsOneWidget);
    expect(find.text('Invited Name'), findsOneWidget);
    expect(find.text('DATE OF BIRTH'), findsOneWidget);
    expect(find.text('DD/MM/YYYY'), findsOneWidget);
    expect(venues.submissions, 0);
  });

  for (final dark in [true, false]) {
    for (final saved in [true, false]) {
      testWidgets('DOB is readable and ${saved ? 'locked' : 'selectable'} in '
          '${dark ? 'dark' : 'light'} theme on a phone', (tester) async {
        final auth = _Auth();
        if (!saved) auth.me.remove('birthdate');
        final venues = _Venues()..step = 2;
        await open(
          tester,
          auth,
          venues,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
          size: const Size(390, 844),
        );
        final field = find.byKey(const ValueKey('claim-birthdate'));
        await tester.ensureVisible(field);
        await tester.pumpAndSettle();
        final button = tester.widget<OutlinedButton>(field);
        expect(button.onPressed == null, saved);
        final background = tester
            .widget<Material>(
              find.descendant(of: field, matching: find.byType(Material)),
            )
            .color;
        expect(
          background,
          dark ? const Color(0xFF0F1C35) : const Color(0xFFF3F6FA),
        );
        final text = find.text(saved ? '02/01/1990' : 'DD/MM/YYYY');
        final foreground = DefaultTextStyle.of(
          tester.element(text),
        ).style.color!;
        final contrast = dark
            ? (foreground.computeLuminance() + 0.05) /
                  (background!.computeLuminance() + 0.05)
            : (background!.computeLuminance() + 0.05) /
                  (foreground.computeLuminance() + 0.05);
        expect(contrast, greaterThanOrEqualTo(4.5));
        expect(find.text('DATE OF BIRTH'), findsOneWidget);
        await tester.tap(field);
        await tester.pumpAndSettle();
        if (saved) {
          expect(find.byType(DatePickerDialog), findsNothing);
          expect(find.text('02/01/1990'), findsOneWidget);
        } else {
          expect(find.byType(DatePickerDialog), findsOneWidget);
          final selected = tester
              .widget<DatePickerDialog>(find.byType(DatePickerDialog))
              .initialDate!;
          await tester.tap(find.text('OK'));
          await tester.pumpAndSettle();
          expect(
            find.text(
              '${selected.day.toString().padLeft(2, '0')}/'
              '${selected.month.toString().padLeft(2, '0')}/'
              '${selected.year}',
            ),
            findsOneWidget,
          );
          expect(find.byType(DatePickerDialog), findsNothing);
        }
        expect(venues.submissions, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('Not now keeps claim form and retry sends adult DOB and name', (
    tester,
  ) async {
    var allow = false;
    PublicContentPermission.onRequired = (_) async {
      if (!allow) {
        throw ApiException(
          statusCode: 403,
          data: {'errorCode': 'AWS_SHARING_PERMISSION_DECLINED'},
        );
      }
    };
    final venues = _Venues();
    await open(tester, _Auth(), venues);
    await tap(tester, 'Register Without Documents');
    expect(venues.submissions, 0);
    expect(find.byType(Dialog), findsNothing);
    expect(
      find.textContaining('Your application has not been submitted'),
      findsOneWidget,
    );
    expect(find.textContaining('Could not submit'), findsNothing);
    allow = true;
    await tap(tester, 'Review permission');
    expect(venues.submissions, 1);
    expect(venues.submittedName, 'Provider Name');
    expect(venues.submittedDob, '1990-01-02');
    expect(find.textContaining('Could not submit'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'successful adult claim proceeds without reopening registration',
    (tester) async {
      await SecureStorage.setNotificationOnboardingDone();
      final venues = _Venues()..fail = false;
      await open(tester, _Auth(), venues);
      await tap(tester, 'Register Without Documents');
      expect(venues.submissions, 1);
      expect(venues.draftDeleted, isTrue);
      expect(find.text('Claim received'), findsOneWidget);
    },
  );

  testWidgets('underage DOB cannot submit even from a saved review draft', (
    tester,
  ) async {
    final auth = _Auth()
      ..me = {'registrationName': 'Member', 'birthdate': '2020-01-01'};
    final venues = _Venues();
    await open(tester, auth, venues);
    await tap(tester, 'Register Without Documents');
    expect(venues.submissions, 0);
    expect(find.text('You must be 18 or older to use KMSTRY.'), findsOneWidget);
    expect(find.text('STEP 2 OF 4'), findsOneWidget);
  });
}
