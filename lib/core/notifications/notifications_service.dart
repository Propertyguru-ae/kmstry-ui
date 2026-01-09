import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false, // 🔴 ÇOK ÖNEMLİ
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const settings = InitializationSettings(iOS: iosSettings);

  await notificationsPlugin.initialize(settings);
}

