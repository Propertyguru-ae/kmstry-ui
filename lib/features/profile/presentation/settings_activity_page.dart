import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/blocked_users_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/notifications_settings_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class SettingsActivityPage extends StatefulWidget {
  const SettingsActivityPage({super.key});

  @override
  State<SettingsActivityPage> createState() => _SettingsActivityPageState();
}

class _SettingsActivityPageState extends State<SettingsActivityPage>
    with WidgetsBindingObserver {
  static const _notificationsEnabledKey = 'notifications_enabled';

  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();

  bool _loading = true;
  bool _accountNotificationsEnabled = false;
  bool _systemNotificationsEnabled = false;
  bool _receiveTestNotifications = true;
  int _blockedUsersCount = 0;
  bool _deletingAccount = false;
  bool _loggingOut = false;
  bool _canDeleteCurrentContextProfile = false;
  bool _isVenueContext = false;
  String? _activeVenueId;

  // Device permissions
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadAndSyncNotifications();
    }
  }

  Future<void> _loadAndSyncNotifications() async {
    final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
    final systemGranted =
        fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
        fcmSettings.authorizationStatus == AuthorizationStatus.provisional;

    if (systemGranted && !_accountNotificationsEnabled) {
      await _setNotifications(true);
    } else {
      await _load();
    }
  }

  Future<void> _load() async {
    try {
      final me = await AuthRepository().getMe();
      final accountOptIn = me['notificationPermissionGranted'];
      final receiveTest = me['receiveTestNotifications'];
      final accountEnabled = accountOptIn is bool ? accountOptIn : true;
      final permissionState = await _notificationPermissionService
          .readStateWithAccountPreference(accountEnabled);
      await SecureStorage.write(_notificationsEnabledKey, accountEnabled.toString());

      // blocked count
      int blockedCount = 0;
      try {
        final blocked = await MatchRepository().getBlockedUsers();
        blockedCount = blocked.length;
      } catch (_) {}

      final meContext = MeContextModel.fromMe(me);

      // Device permissions
      final cameraStatus = await Permission.camera.status;
      final locationStatus = await Permission.locationWhenInUse.status;
      // iOS'ta permission_handler bildirim iznini yanlış okuyabiliyor.
      // Firebase'in kendi API'si her zaman doğru durumu döndürür.
      final fcmSettings = await FirebaseMessaging.instance.getNotificationSettings();
      final notifGranted =
          fcmSettings.authorizationStatus == AuthorizationStatus.authorized ||
          fcmSettings.authorizationStatus == AuthorizationStatus.provisional;

      if (!mounted) return;
      setState(() {
        _cameraGranted = cameraStatus.isGranted;
        _locationGranted = locationStatus.isGranted;
        _notificationGranted = notifGranted;
        _accountNotificationsEnabled = accountEnabled;
        _systemNotificationsEnabled = permissionState.systemGranted;
        _receiveTestNotifications = receiveTest is bool ? receiveTest : true;
        _blockedUsersCount = blockedCount;
        _isVenueContext = meContext.lastActiveContext?.toUpperCase() == 'VENUE';
        _canDeleteCurrentContextProfile = meContext.canDeleteCurrentContextProfile;
        _activeVenueId = meContext.activeVenueId ??
            (meContext.memberVenues.isNotEmpty ? meContext.memberVenues.first.id : null);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setNotifications(bool enabled) async {
    if (enabled && !_systemNotificationsEnabled) {
      final status = await Permission.notification.request();
      final granted = status == PermissionStatus.granted;
      if (!mounted) return;
      setState(() => _systemNotificationsEnabled = granted);
      if (!granted) return;
    }
    setState(() => _accountNotificationsEnabled = enabled);
    await SecureStorage.write(_notificationsEnabledKey, enabled.toString());
    await AuthRepository().updateMe({'notification_permission_granted': enabled});
    if (enabled) {
      await PushManager.instance.ensureRegisteredIfAllowed();
    }
  }

  Future<void> _handleNotificationTileTap() async {
    if (_notificationGranted && !_accountNotificationsEnabled) {
      await _setNotifications(true);
    } else {
      openAppSettings();
    }
  }

  Future<void> _setTestNotifications(bool enabled) async {
    setState(() => _receiveTestNotifications = enabled);
    try {
      await AuthRepository().updateMe({'receive_test_notifications': enabled});
    } catch (_) {
      if (mounted) setState(() => _receiveTestNotifications = !enabled);
    }
  }

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthRepository().logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AuthRoutes.login, (r) => false);
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount || !_canDeleteCurrentContextProfile) return;
    final isVenue = _isVenueContext;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isVenue ? 'Delete venue profile?' : 'Delete personal profile?'),
        content: Text(
          isVenue
              ? 'This action is permanent. Your venue context will be removed, but your root account stays active. Are you sure?'
              : 'This action is permanent. Only your personal profile will be deleted. Your account and any venue memberships stay active. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      if (isVenue) {
        final venueId = _activeVenueId;
        if (venueId == null || venueId.isEmpty) throw Exception('Active venue id is missing');
        await AuthRepository().deleteVenueContextMembership(venueId: venueId);
      } else {
        await AuthRepository().deletePersonalContextProfile();
      }
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(AuthRoutes.authGate, (r) => false);
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not delete ${isVenue ? 'venue' : 'personal'} profile: '
            '${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final tileBg = isDark
        ? colors.surface.withValues(alpha: 0.92)
        : const Color(0xFFF8FBFD);
    final tileBorder = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE6EEF4);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Settings & Activity',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Account Center ───────────────────────────────
                _SectionLabel(label: 'Account'),
                const SizedBox(height: 8),
                _Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const AccountSettingsPage())),
                    leading: Icon(Icons.manage_accounts_outlined, color: colors.primary),
                    title: Text('Account Center',
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text('Email, password, theme & more',
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Device Permissions ───────────────────────────
                _SectionLabel(label: 'Device Permissions'),
                const SizedBox(height: 8),
                _PermissionTile(
                  icon: Icons.camera_alt_outlined,
                  title: 'Camera',
                  subtitle: 'Used for check-in photos and videos',
                  granted: _cameraGranted,
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _PermissionTile(
                  icon: Icons.location_on_outlined,
                  title: 'Location',
                  subtitle: 'Used to show nearby venues',
                  granted: _locationGranted,
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _PermissionTile(
                  icon: Icons.notifications_outlined,
                  title: 'Notifications',
                  subtitle: _notificationGranted && !_accountNotificationsEnabled
                      ? 'Tap to enable in-app notifications'
                      : 'System-level notification permission',
                  granted: _notificationGranted && _accountNotificationsEnabled,
                  onTap: _handleNotificationTileTap,
                  colors: colors,
                ),

                const SizedBox(height: 24),

                // ── How you use KMSTRY ───────────────────────────
                _SectionLabel(label: 'How you use KMSTRY'),
                const SizedBox(height: 8),
                _Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const NotificationsSettingsPage())),
                    leading: Icon(Icons.notifications_none_rounded, color: colors.primary),
                    title: Text('Notifications',
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text('Messages, invites, venue updates',
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
                const SizedBox(height: 8),
                _Card(
                  child: SwitchListTile(
                    secondary: Icon(Icons.science_outlined, color: colors.primary),
                    title: Text('Test Notifications',
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
                    subtitle: Text('Receive nearby venue test pings',
                        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6), fontSize: 13)),
                    value: _receiveTestNotifications,
                    onChanged: _setTestNotifications,
                  ),
                ),

                const SizedBox(height: 24),

                // ── Privacy ──────────────────────────────────────
                _SectionLabel(label: 'Who can see your account'),
              
                const SizedBox(height: 8),
                _Card(
                  child: ListTile(
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => const BlockedUsersPage())),
                    title: Text('Blocked',
                        style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
                    trailing: Text('$_blockedUsersCount',
                        style: TextStyle(
                            fontSize: 16,
                            color: colors.onSurface.withValues(alpha: 0.8),
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Log Out ──────────────────────────────────────
                _Card(
                  child: ListTile(
                    onTap: _loggingOut ? null : _logout,
                    leading: _loggingOut
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.error,
                            ),
                          )
                        : Icon(Icons.logout, color: colors.error),
                    title: Text(
                      'Log Out',
                      style: TextStyle(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label,
      style: theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.92)
        : const Color(0xFFF8FBFD);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE6EEF4);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool granted;
  final ColorScheme colors;
  final VoidCallback? onTap;

  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? colors.surface.withValues(alpha: 0.92)
        : const Color(0xFFF8FBFD);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE6EEF4);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: onTap ?? openAppSettings,
        leading: Icon(icon, color: colors.primary),
        title: Text(title,
            style: TextStyle(
                color: colors.onSurface, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle,
            style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.6), fontSize: 12)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: granted
                    ? Colors.green.withValues(alpha: 0.15)
                    : colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                granted ? 'Allowed' : 'Denied',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: granted ? Colors.green : colors.error,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right,
                color: colors.onSurface.withValues(alpha: 0.4), size: 18),
          ],
        ),
      ),
    );
  }
}
