import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
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
    final fcmSettings = await FirebaseMessaging.instance
        .getNotificationSettings();
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
      final me = await AuthRepository().getMe(forceRefresh: true);
      final accountOptIn = me['notificationPermissionGranted'];
      final accountEnabled = accountOptIn is bool ? accountOptIn : true;
      final permissionState = await _notificationPermissionService
          .readStateWithAccountPreference(accountEnabled);
      await SecureStorage.write(
        _notificationsEnabledKey,
        accountEnabled.toString(),
      );

      final meContext = MeContextModel.fromMe(me);

      // Device permissions
      final cameraStatus = await Permission.camera.status;
      final locationStatus = await Permission.locationWhenInUse.status;
      // iOS'ta permission_handler bildirim iznini yanlış okuyabiliyor.
      // Firebase'in kendi API'si her zaman doğru durumu döndürür.
      final fcmSettings = await FirebaseMessaging.instance
          .getNotificationSettings();
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
        _isVenueContext = meContext.lastActiveContext?.toUpperCase() == 'VENUE';
        _canDeleteCurrentContextProfile =
            meContext.canDeleteCurrentContextProfile;
        _activeVenueId =
            meContext.activeVenueId ??
            (meContext.memberVenues.isNotEmpty
                ? meContext.memberVenues.first.id
                : null);
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
    await AuthRepository().updatePermissions({
      'notificationPermissionGranted': enabled,
    });
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

  Future<void> _logout() async {
    if (_loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await AuthRepository().logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AuthRoutes.login, (r) => false);
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount || !_canDeleteCurrentContextProfile) return;
    final isVenue = _isVenueContext;
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: isVenue ? 'Leave this venue?' : 'Delete personal profile?',
      message: isVenue
          ? 'Your venue access will be removed. Your KMSTRY account and other profiles will stay active.'
          : 'Only your personal profile will be deleted. Your KMSTRY account and any venue access will stay active.',
      confirmLabel: isVenue ? 'Leave venue' : 'Delete personal profile',
      icon: isVenue ? Icons.logout_rounded : Icons.person_remove_rounded,
    );
    if (!confirmed || !mounted) return;
    setState(() => _deletingAccount = true);
    try {
      if (isVenue) {
        final venueId = _activeVenueId;
        if (venueId == null || venueId.isEmpty)
          throw Exception('Active venue id is missing');
        await AuthRepository().deleteVenueContextMembership(venueId: venueId);
      } else {
        await AuthRepository().deletePersonalContextProfile();
      }
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.authGate, (r) => false);
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message:
            'Could not delete ${isVenue ? 'venue' : 'personal'} profile: '
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

    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kBorder = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFD9E1EA);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Settings & Activity',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
                padding: const EdgeInsets.all(16),
                children: [
                // ── Account Center ───────────────────────────────
                _SectionLabel(label: 'Account'),
                const SizedBox(height: 8),
                _Card(
                  child: ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AccountSettingsPage(),
                      ),
                    ),
                    leading: Icon(
                      Icons.manage_accounts_outlined,
                      color: colors.primary,
                    ),
                    title: Text(
                      'Account Center',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Email, password, theme & more',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
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
                  subtitle:
                      _notificationGranted && !_accountNotificationsEnabled
                      ? 'Tap to enable in-app notifications'
                      : 'System-level notification permission',
                  granted: _notificationGranted && _accountNotificationsEnabled,
                  onTap: _handleNotificationTileTap,
                  colors: colors,
                ),

                const SizedBox(height: 8),

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
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
        title: Text(
          title,
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
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
            Icon(
              Icons.chevron_right,
              color: colors.onSurface.withValues(alpha: 0.4),
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
