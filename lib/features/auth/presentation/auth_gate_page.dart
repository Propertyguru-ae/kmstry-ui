import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/auth/presentation/login_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/gender_interest_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/permissions_flow_page.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import '../data/auth_repository.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';

class AuthGatePage extends StatefulWidget {
  const AuthGatePage({super.key});

  @override
  State<AuthGatePage> createState() => _AuthGatePageState();
}

class _AuthGatePageState extends State<AuthGatePage> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final isLoggedIn = await AuthRepository().restoreSession();
    if (!mounted) return;

    if (!isLoggedIn) {
      _go(const LoginPage());
      return;
    }

    final me = await AuthRepository().getMe();
    final step = me['onboardingStep'];

    switch (step) {
      case 'NAME_DOB':
        _go(NameDobOnboardingPage(initialName: me['fullName']));
        return;

      case 'GENDER_INTEREST':
        _go(const GenderInterestOnboardingPage());
        return;

      /*case 'PHOTO':
        _go(const PhotoOnboardingPage());
        return;*/

      case 'PERMISSIONS':
        _go(const PermissionsFlowPage());
        return;

      case 'COMPLETED':
        final devicePermissionsDone =
            await SecureStorage.isDevicePermissionsOnboardingDone();
        if (!devicePermissionsDone) {
          _go(const PermissionsFlowPage(markProfileCompleted: false));
          return;
        }
        await PushManager.instance.ensureRegisteredIfAllowed();
        _go(const AppShell());
        return;

      default:
        final devicePermissionsDone =
            await SecureStorage.isDevicePermissionsOnboardingDone();
        if (!devicePermissionsDone) {
          _go(const PermissionsFlowPage(markProfileCompleted: false));
          return;
        }
        await PushManager.instance.ensureRegisteredIfAllowed();
        // Güvenli fallback
        _go(const AppShell());
        return;
    }
  }

  void _go(Widget page) {
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
