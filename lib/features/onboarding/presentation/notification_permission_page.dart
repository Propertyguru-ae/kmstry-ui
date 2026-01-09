import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:kmstry_frontend/core/notifications/notifications_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class NotificationPermissionPage extends StatefulWidget {
  final VoidCallback onNext;

  const NotificationPermissionPage({super.key, required this.onNext});

  @override
  State<NotificationPermissionPage> createState() =>
      _NotificationPermissionPageState();
}

class _NotificationPermissionPageState
    extends State<NotificationPermissionPage> {
  bool _notifShownOnDevice = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _notifShownOnDevice = await SecureStorage.isNotificationOnboardingDone();
    setState(() {
      _loading = false;
    });
  }

  Future<void> _enableNotifications() async {
    final iosPlugin = notificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();

    if (iosPlugin != null) {
      // Popup sadece ilk sefer çıkar
      await iosPlugin.requestPermissions(alert: true, badge: true, sound: true);
    }

    // Enable = explicit app-level consent
    await AuthRepository().updatePermissions({
      'notificationPermissionGranted': true,
    });

    await SecureStorage.setNotificationOnboardingDone();
    widget.onNext();
  }

  Future<void> _notNow() async {
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
            const Spacer(),

            // 🔔 ENABLE (her zaman var)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _enableNotifications,
                child: const Text('Enable Notifications'),
              ),
            ),

            // ⛔ NOT NOW (sadece popup artık çıkmıyorsa)
            if (_notifShownOnDevice) ...[
              const SizedBox(height: 8),
              TextButton(onPressed: _notNow, child: const Text('Not now')),
            ],
          ],
        ),
      ),
    );
  }
}
