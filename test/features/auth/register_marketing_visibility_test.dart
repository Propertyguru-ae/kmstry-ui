import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthRepository {
  bool? sentMarketingOptIn;
  bool? sentConsent;
  String? sentTermsVersion;
  String? sentPrivacyVersion;

  @override
  Future<ActiveLegalVersions> getActiveLegalVersions() async =>
      const ActiveLegalVersions(
        termsVersionId: 'terms-current',
        privacyVersionId: 'privacy-current',
      );

  @override
  Future<void> registerAndAutoLogin(
    String email,
    String password,
    String otpProof, {
    bool marketingEmailOptIn = false,
    required bool consentGiven,
    required String termsVersionId,
    required String privacyVersionId,
    String consentSource = 'MOBILE',
  }) async {
    sentMarketingOptIn = marketingEmailOptIn;
    sentConsent = consentGiven;
    sentTermsVersion = termsVersionId;
    sentPrivacyVersion = privacyVersionId;
    // Stop at the submission boundary: no account or network request is made.
    throw StateError('Test captured registration');
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final flow in ['personal', 'venue', 'invite']) {
    testWidgets('$flow hides marketing but still requires legal consent', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final auth = _Auth();
      await tester.pumpWidget(
        MaterialApp(
          home: RegisterSetPasswordPage(
            email: 'test@example.com',
            otpProof: 'test-proof',
            isVenueSignup: flow == 'venue',
            isInviteSignup: flow == 'invite',
            authRepository: auth,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Send me occasional emails about my account and special offers',
        ),
        findsNothing,
      );
      expect(find.text('Terms of Service'), findsOneWidget);
      expect(find.text('Privacy Policy'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField).at(0), 'Test1234!');
      await tester.enterText(find.byType(TextFormField).at(1), 'Test1234!');
      await tester.pump();
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNull,
      );

      final consent = find.textContaining('I agree to the ');
      await tester.ensureVisible(consent);
      // Tap the consent row itself, not one of the embedded policy links.
      await tester.tapAt(tester.getTopLeft(consent) + const Offset(5, 5));
      await tester.pump();
      expect(
        tester.widget<PrimaryButton>(find.byType(PrimaryButton)).onPressed,
        isNotNull,
      );
      await tester.ensureVisible(find.byType(PrimaryButton));
      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      expect(auth.sentMarketingOptIn, isFalse);
      expect(auth.sentConsent, isTrue);
      expect(auth.sentTermsVersion, 'terms-current');
      expect(auth.sentPrivacyVersion, 'privacy-current');
      expect(tester.takeException(), isNull);
    });
  }
}
