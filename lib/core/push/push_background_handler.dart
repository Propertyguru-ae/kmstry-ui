import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../firebase_options.dart';
import '../notifications/notifications_service.dart';

/// Top-level FCM background handler.
///
/// Firebase requires this to be a top-level function annotated with
/// @pragma('vm:entry-point'). It runs in a separate Dart isolate — there is
/// no widget tree, no Navigator, and no access to the running app's state.
///
/// What we CAN do here:
///   • Show a local notification banner (Android).
///   • Read / write to secure storage or shared_preferences.
///
/// What we CANNOT do:
///   • Navigate to a screen (no BuildContext).
///   • Update UI state.
///
/// Tap routing for notifications shown here is handled by the existing
/// onDidReceiveNotificationResponse callback registered in initNotifications().
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Background isolate needs its own binding + Firebase init.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // iOS: the system shows the notification banner automatically for background
  // messages — nothing extra needed.
  if (!Platform.isAndroid) return;

  // If the message already carries a `notification` payload, the Android
  // system will show the banner itself.  We only need to act on data-only
  // messages (no notification payload), which are otherwise invisible.
  if (message.notification != null) return;

  final data = message.data;
  final title = (data['title'] as String?) ?? '';
  final body = (data['body'] as String?) ?? '';
  if (title.isEmpty && body.isEmpty) return;

  // Initialize the local-notifications plugin (no navigatorKey — routing is
  // handled via the tap callback registered when the app is foregrounded).
  await initNotifications();

  final androidDetails = AndroidNotificationDetails(
    kForegroundChannel.id,
    kForegroundChannel.name,
    channelDescription: kForegroundChannel.description,
    importance: Importance.high,
    priority: Priority.high,
    icon: '@mipmap/ic_launcher',
  );

  final payload = data.isNotEmpty ? jsonEncode(data) : null;
  final id = (message.messageId ?? '').hashCode;

  await notificationsPlugin.show(
    id,
    title,
    body,
    NotificationDetails(android: androidDetails),
    payload: payload,
  );
}
