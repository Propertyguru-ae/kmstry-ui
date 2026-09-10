import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../push/push_deep_link_handler.dart';

final FlutterLocalNotificationsPlugin notificationsPlugin =
    FlutterLocalNotificationsPlugin();

/// Android notification channel for foreground push banners.
const AndroidNotificationChannel kForegroundChannel = AndroidNotificationChannel(
  'kmstry_foreground',
  'KMSTRY Notifications',
  description: 'Real-time notifications from KMSTRY',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
);

/// Call once from main() before runApp.
/// [navigatorKey] is used to route taps on local notifications.
Future<void> initNotifications({
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  // Android: ensure the notification channel exists.
  final androidPlugin = notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
  await androidPlugin?.createNotificationChannel(kForegroundChannel);

  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');

  // iOS permission dialogs are handled by FirebaseMessaging.requestPermission
  // in PushManager — not by flutter_local_notifications.
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: false,
    requestBadgePermission: false,
    requestSoundPermission: false,
  );

  const settings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );

  await notificationsPlugin.initialize(
    settings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      final payload = response.payload;
      if (payload == null || payload.isEmpty) return;
      if (navigatorKey == null) return;
      try {
        final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
        PushDeepLinkHandler.instance.routeFromData(navigatorKey, data);
      } catch (_) {}
    },
  );
}
