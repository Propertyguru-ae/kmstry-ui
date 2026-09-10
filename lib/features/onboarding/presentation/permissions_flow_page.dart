import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/location_permission_page.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/notification_permission_page.dart';
import 'permission_steps.dart';

class PermissionsFlowPage extends StatefulWidget {
  final bool markProfileCompleted;

  /// true → izin adımları dark'a zorlanır (fresh signup / ilk kurulum marka
  /// akışı). false → seçilen temayı izler (mevcut kullanıcı add-personal/venue).
  final bool forceDark;

  const PermissionsFlowPage({
    super.key,
    this.markProfileCompleted = true,
    this.forceDark = true,
  });

  @override
  State<PermissionsFlowPage> createState() => _PermissionsFlowPageState();
}

class _PermissionsFlowPageState extends State<PermissionsFlowPage> {
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();
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
    final locationStatus = await _locationPermissionService.status();
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

    // Account onboarding içinden geliyorsa ve backend completed ise direkt geç.
    if (widget.markProfileCompleted && me['onboarding_step'] == 'COMPLETED') {
      await _finishPermissions();
      return;
    }

    /* --------------------------------------------------
     * 📍 LOCATION — DEVICE ↔ DB SYNC (GÜVENLİ)
     * -------------------------------------------------- */

    final locationStatus = await _locationPermissionService.status();
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
     * 🔔 NOTIFICATION — DEVICE ONBOARDING FLAG + SYSTEM STATUS
     * -------------------------------------------------- */
    final notifOnboardingDone = await SecureStorage.isNotificationOnboardingDone();
    final notificationStatus = await Permission.notification.status;
    final systemNotificationGranted =
        notificationStatus.isGranted ||
        notificationStatus == PermissionStatus.provisional;

    // If system permission already granted but backend is null, sync once.
    final bool? accountOptIn = me['notificationPermissionGranted'] as bool?;
    if (systemNotificationGranted && accountOptIn == null) {
      await AuthRepository().updatePermissions({
        'notificationPermissionGranted': true,
      });
    }

    // Show notification onboarding on fresh device, and also if account says
    // notifications are still disabled while system permission is not granted.
    final shouldShowNotificationStep =
        !notifOnboardingDone ||
        (!systemNotificationGranted && accountOptIn != true);
    if (shouldShowNotificationStep) {
      _steps.add(PermissionStep.notifications);
    }

    setState(() {
      _initialized = true;
    });
  }

  Future<void> _finishPermissions() async {
    if (widget.markProfileCompleted) {
      await AuthRepository().updateMe({'profile_completed': true});
    }
    await SecureStorage.setDevicePermissionsOnboardingDone();

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
  }

  void _goNext() async {
    if (_currentIndex < _steps.length - 1) {
      setState(() {
        _currentIndex++;
      });
    } else {
      if (_steps.contains(PermissionStep.notifications)) {
        await SecureStorage.setNotificationOnboardingDone();
      }
      await _finishPermissions();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fresh signup / ilk kurulum → dark (marka akışı). Mevcut kullanıcı
    // add-personal/add-venue → seçilen temayı izler.
    if (widget.forceDark) {
      return ForceDark(child: Builder(builder: _buildBody));
    }
    return _buildBody(context);
  }

  Widget _buildBody(BuildContext context) {
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
