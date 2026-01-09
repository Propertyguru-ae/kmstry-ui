import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/location_permission_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/notification_permission_page.dart';
import 'permission_steps.dart';

class PermissionsFlowPage extends StatefulWidget {
  const PermissionsFlowPage({super.key});

  @override
  State<PermissionsFlowPage> createState() => _PermissionsFlowPageState();
}

class _PermissionsFlowPageState extends State<PermissionsFlowPage> {
  final List<PermissionStep> _steps = [];
  int _currentIndex = 0;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _initPermissions();
  }

  /*Future<void> _initPermissions() async {
    final me = await AuthRepository().getMe();

    if (me['onboarding_step'] == 'COMPLETED') {
      _finishPermissions();
      return;
    }

    // 📍 Location
    final locationStatus = await Permission.locationWhenInUse.status;
    debugPrint('locationStatus: $locationStatus');

    if (!locationStatus.isGranted) {
      _steps.add(PermissionStep.location);
    }

    // 🔔 Notification → SADECE DEVICE FLAG
    final notifShownOnDevice =
        await SecureStorage.isNotificationOnboardingDone();

    debugPrint('notifShownOnDevice: $notifShownOnDevice');

    if (!notifShownOnDevice) {
      _steps.add(PermissionStep.notifications);
    }
    setState(() {
      _initialized = true;
    });
  }*/

  Future<void> _initPermissions() async {
    final me = await AuthRepository().getMe();

    // Backend onboarding tamamlandıysa direkt geç
    if (me['onboarding_step'] == 'COMPLETED') {
      await _finishPermissions();
      return;
    }

    /* --------------------------------------------------
     * 📍 LOCATION — DEVICE ↔ DB SYNC (GÜVENLİ)
     * -------------------------------------------------- */

    final locationStatus = await Permission.locationWhenInUse.status;
    final bool systemLocationGranted = locationStatus.isGranted;
    final bool? userLocationPermission = me['locationPermissionGranted'];

    if (systemLocationGranted && userLocationPermission == null) {
      await AuthRepository().updatePermissions({
        'locationPermissionGranted': true,
      });
    }

    if (!systemLocationGranted) {
      _steps.add(PermissionStep.location);
    }

    /* --------------------------------------------------
     * 🔔 NOTIFICATION — SADECE DEVICE FLAG
     * -------------------------------------------------- */


    final bool? userNotificationPermission =
        me['notificationPermissionGranted'];

    // iOS için status okunmaz → sadece explicit consent
    if (userNotificationPermission == null) {
      _steps.add(PermissionStep.notifications);
    }

    setState(() {
      _initialized = true;
    });
  }

  Future<void> _finishPermissions() async {
    await AuthRepository().updateMe({'profile_completed': true});

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
  }

  void _goNext() async {
    if (_currentIndex < _steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      await SecureStorage.setNotificationOnboardingDone();
      await _finishPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_steps.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _finishPermissions();
      });
      return const Scaffold();
    }

    final step = _steps[_currentIndex];

    switch (step) {
      case PermissionStep.location:
        return LocationPermissionPage(onNext: _goNext);

      case PermissionStep.notifications:
        return NotificationPermissionPage(onNext: _goNext);

      case PermissionStep.done:
        return const Scaffold();
    }
  }
}
