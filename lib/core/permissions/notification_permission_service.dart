import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

enum NotificationSystemStatus { authorized, provisional, denied, notDetermined }

class NotificationPermissionState {
  final NotificationSystemStatus systemStatus;
  final bool accountPreference;

  const NotificationPermissionState({
    required this.systemStatus,
    required this.accountPreference,
  });

  bool get systemGranted =>
      systemStatus == NotificationSystemStatus.authorized ||
      systemStatus == NotificationSystemStatus.provisional;

  bool get effectiveStatus => systemGranted && accountPreference;
}

class NotificationPermissionService {
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final AuthRepository _auth = AuthRepository();

  NotificationSystemStatus _mapAuthorization(AuthorizationStatus status) {
    switch (status) {
      case AuthorizationStatus.authorized:
        return NotificationSystemStatus.authorized;
      case AuthorizationStatus.provisional:
        return NotificationSystemStatus.provisional;
      case AuthorizationStatus.denied:
        return NotificationSystemStatus.denied;
      case AuthorizationStatus.notDetermined:
        return NotificationSystemStatus.notDetermined;
    }
  }

  Future<NotificationPermissionState> readStateFromBackend() async {
    final me = await _auth.getMe();
    final accountPreference = me['notificationPermissionGranted'] != false;
    final settings = await _messaging.getNotificationSettings();
    return NotificationPermissionState(
      systemStatus: _mapAuthorization(settings.authorizationStatus),
      accountPreference: accountPreference,
    );
  }

  Future<NotificationPermissionState> readStateWithAccountPreference(
    bool accountPreference,
  ) async {
    final settings = await _messaging.getNotificationSettings();
    return NotificationPermissionState(
      systemStatus: _mapAuthorization(settings.authorizationStatus),
      accountPreference: accountPreference,
    );
  }

  Future<void> reconcileBackendPreferenceWithSystem() async {
    final state = await readStateFromBackend();
    if (!state.systemGranted && state.accountPreference) {
      // System permission revoked → sync backend to false
      await _auth.updatePermissions({'notificationPermissionGranted': false});
    } else if (state.systemGranted && !state.accountPreference) {
      // System permission granted but backend still false (e.g. invite-signup users
      // who never went through the notification onboarding screen) → sync to true
      await _auth.updatePermissions({'notificationPermissionGranted': true});
    }
  }
}
