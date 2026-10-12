import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';

class SettingsDevicePermissions {
  const SettingsDevicePermissions({
    required this.camera,
    required this.location,
    required this.notifications,
  });
  final bool camera;
  final bool location;
  final bool notifications;

  /// Read existing permission states concurrently; never prompts the user.
  static Future<SettingsDevicePermissions> read() async {
    final results = await Future.wait([
      Permission.camera.status.then((status) => status.isGranted),
      Permission.locationWhenInUse.status.then((status) => status.isGranted),
      FirebaseMessaging.instance.getNotificationSettings().then(
        (settings) =>
            settings.authorizationStatus == AuthorizationStatus.authorized ||
            settings.authorizationStatus == AuthorizationStatus.provisional,
      ),
    ]);
    return SettingsDevicePermissions(
      camera: results[0],
      location: results[1],
      notifications: results[2],
    );
  }
}
