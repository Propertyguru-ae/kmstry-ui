// Offline fixtures shared by widget tests and the local native theme preview.
// Nothing here creates users, uploads media or changes a server-side draft.
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/context_choice_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/forgot_password_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/login_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_email_otp_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/reset_password_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/signup_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/location_permission_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/app_intro_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/notification_permission_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/personal_onboarding_flow.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_search_location.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class ThemePreviewAuth extends AuthRepository {
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => {
    'registrationName': 'Alex Morgan',
    'birthdate': '1990-01-02',
  };

  @override
  Future<ActiveLegalVersions> getActiveLegalVersions() async =>
      const ActiveLegalVersions(
        termsVersionId: 'preview',
        privacyVersionId: 'preview',
      );
}

class _Venues extends VenueRepository {
  _Venues(this.step);
  final int step;

  @override
  Future<Map<String, dynamic>?> getClaimDraft() async => {
    'current_step': step,
    'owner_full_name': 'Alex Morgan',
    'owner_phone': '+971501234567',
    if (step > 1)
      'venue': {
        'id': 'preview',
        'name': 'Preview Cafe',
        'city': 'Dubai',
        'isInDb': true,
      },
  };
}

class _NoLocation extends VenueSearchLocationResolver {
  @override
  Future<VenueSearchLocation?> resolve() async => null;
}

Map<String, Widget Function()> themePreviewScreens() {
  late final auth = ThemePreviewAuth();
  return {
    'intro': () => const AppIntroPage(),
    'login': () => LoginPage(authRepository: auth),
    'account-type': () => const ContextChoicePage(),
    'signup-personal': () => const SignupPage(),
    'signup-venue': () => const SignupPage(isVenueSignup: true),
    'email-otp': () => const RegisterEmailOtpPage(
      email: 'preview@example.com',
      initialOtpResponse: {},
    ),
    'password': () => RegisterSetPasswordPage(
      email: 'preview@example.com',
      otpProof: 'preview',
      authRepository: auth,
    ),
    'forgot-password': () => const ForgotPasswordPage(),
    'reset-password': () => const ResetPasswordPage(resetToken: 'preview'),
    for (final step in OnboardingFlowStep.values)
      'personal-${step.name}': () => PersonalOnboardingFlow(
        startAt: step,
        initialUsername: 'alex_morgan',
        initialName: 'Alex Morgan',
        initialBirthdate: DateTime(1990, 1, 2),
        repository: auth,
      ),
    'location-permission': () => LocationPermissionPage(onNext: () {}),
    'notification-permission': () => NotificationPermissionPage(onNext: () {}),
    for (final step in [1, 2, 3, 4])
      'venue-step-$step': () => VenueContextOnboardingPage(
        authRepository: auth,
        repository: _Venues(step),
        searchLocationResolver: _NoLocation(),
      ),
  };
}
