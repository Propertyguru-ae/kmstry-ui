import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_gate_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/photo_onboarding_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/context_choice_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';
import 'package:kmstry_frontend/features/people/presentation/people_page.dart';
import 'package:kmstry_frontend/features/messages/presntation/messages.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
class AuthRoutes {
  static const login = '/login';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const home = '/home';
  static const authGate = '/auth-gate';
  static const profile = '/profile';
  static const onboardingDob = '/onboarding/dob';
  static const onboardingGender = '/onboarding/gender';
  static const onboardingPhoto = '/onboarding/photo';
  static const appShell = '/app-shell';
  static const people = '/people';
  static const messages = '/messages';
  static const notifications = '/notifications';
  static const contextChoice = '/context-choice';
  static const venueOnboarding = '/venue-onboarding';

  static Map<String, WidgetBuilder> routes = {
    login: (_) => const LoginPage(),
    signup: (_) => const SignupPage(),
    forgotPassword: (_) => const ForgotPasswordPage(),
    home: (_) => const VenueHomePage(),
    authGate: (_) => const AuthGatePage(),
    profile: (_) => const ProfilePage(),
    messages: (_) => const DmListPage(),
    notifications: (_) => const NotificationPage(),
    contextChoice: (_) => const ContextChoicePage(),
    venueOnboarding: (_) => const VenueContextOnboardingPage(),
    people: (_) => const PeoplePage(),
    onboardingPhoto: (context) => const PhotoOnboardingPage(),
    appShell: (context) => const AppShell(),
  };
}
