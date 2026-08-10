import 'dart:async';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';

class NotificationPermissionPage extends StatefulWidget {
  final VoidCallback onNext;

  const NotificationPermissionPage({super.key, required this.onNext});

  @override
  State<NotificationPermissionPage> createState() =>
      _NotificationPermissionPageState();
}

class _NotificationPermissionPageState
    extends State<NotificationPermissionPage> {
  bool _systemNotificationGranted = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final status = await Permission.notification.status;
    _systemNotificationGranted =
        status.isGranted || status == PermissionStatus.provisional;
    setState(() {
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    debugPrint("Notification button pressed");

    try {
      await PushManager.instance.handlePermissionFlow();
    } catch (_) {}

    await SecureStorage.setNotificationOnboardingDone();
    if (!mounted) return;

    widget.onNext();
    unawaited(PushManager.instance.reconcileNotificationState());
  }

  Future<void> _notNow() async {
    // Account-level preference (user opt-out)
    await AuthRepository().updatePermissions({
      'notificationPermissionGranted': false,
    });

    await SecureStorage.setNotificationOnboardingDone();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.notifications_active, size: 72),
            const SizedBox(height: 16),
            const Text(
              'Enable notifications',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Get notified about matches and activity.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _systemNotificationGranted
                  ? 'System notifications: ON'
                  : 'System notifications: OFF',
              style: TextStyle(
                color: _systemNotificationGranted
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),

            // 🔔 ENABLE (her zaman var)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enableNotifications,
                child: const Text('Enable Notifications'),
              ),
            ),

            const SizedBox(height: 8),
            TextButton(onPressed: _notNow, child: const Text('Not now')),
          ],
        ),
      ),
    );
  }
}
