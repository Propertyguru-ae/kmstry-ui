import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_gate_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/photo_onboarding_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'login_page.dart';
import 'signup_page.dart';
import 'forgot_password_page.dart';

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

  static Map<String, WidgetBuilder> routes = {
    login: (_) => const LoginPage(),
    signup: (_) => const SignupPage(),
    forgotPassword: (_) => const ForgotPasswordPage(),
    home: (_) => const VenueHomePage(),
    authGate: (_) => const AuthGatePage(),
    profile: (_) => const ProfilePage(),
    onboardingPhoto: (context) => const PhotoOnboardingPage(),
    appShell: (context) => const AppShell(),
  };
}
