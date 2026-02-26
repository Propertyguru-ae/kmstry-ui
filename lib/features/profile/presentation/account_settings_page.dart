import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/blocked_users_page.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  static const _notificationsEnabledKey = 'notifications_enabled';
  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();
  final MatchRepository _matchRepository = MatchRepository();
  bool _loading = true;
  bool _accountNotificationsEnabled = false;
  bool _systemNotificationsEnabled = false;
  int _blockedUsersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final me = await AuthRepository().getMe();
      final accountOptIn = me['notificationPermissionGranted'];
      final accountEnabled = accountOptIn is bool ? accountOptIn : false;
      final permissionState = await _notificationPermissionService
          .readStateWithAccountPreference(accountEnabled);
      final blockedUsers = await _matchRepository.getBlockedUsers();

      await SecureStorage.write(_notificationsEnabledKey, accountEnabled.toString());
      await _syncNotificationToBackend(accountEnabled);

      if (!mounted) return;
      setState(() {
        _accountNotificationsEnabled = accountEnabled;
        _systemNotificationsEnabled = permissionState.systemGranted;
        _blockedUsersCount = blockedUsers.length;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openBlockedUsers() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const BlockedUsersPage()),
    );
    await _loadSettings();
  }

  Future<void> _syncNotificationToBackend(bool enabled) async {
    try {
      await AuthRepository().updatePermissions({
        'notificationPermissionGranted': enabled,
      });
    } catch (_) {}
  }

  Future<void> _setNotifications(bool enabled) async {
    if (enabled && !_systemNotificationsEnabled) {
      final status = await Permission.notification.request();
      if (!mounted) return;

      final granted =
          status.isGranted || status == PermissionStatus.provisional;
      setState(() => _systemNotificationsEnabled = granted);
      if (!granted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enable system notifications to turn this on.'),
          ),
        );
        if (status.isPermanentlyDenied) {
          await openAppSettings();
        }
        return;
      }
    }

    // This switch controls ACCOUNT preference.
    setState(() => _accountNotificationsEnabled = enabled);
    await SecureStorage.write(_notificationsEnabledKey, enabled.toString());
    await _syncNotificationToBackend(enabled);
  }

  Widget _buildThemeModeTile({
    required String title,
    required String subtitle,
    required ThemeMode mode,
    required ThemeMode selected,
    required IconData icon,
  }) {
    final colors = Theme.of(context).colorScheme;
    final selectedMode = selected == mode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      tileColor: selectedMode
          ? colors.primary.withValues(alpha: 0.12)
          : Colors.transparent,
      leading: Icon(
        icon,
        color: selectedMode ? colors.primary : colors.onSurface,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: colors.onSurface,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7)),
      ),
      trailing: selectedMode
          ? Icon(Icons.check_circle, color: colors.primary)
          : Icon(
              Icons.radio_button_unchecked,
              color: colors.onSurface.withValues(alpha: 0.5),
            ),
      onTap: () async {
        await context.read<ThemeProvider>().setThemeMode(mode);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selectedMode = context.watch<ThemeProvider>().themeMode;
    final permissionState = NotificationPermissionState(
      systemStatus: _systemNotificationsEnabled
          ? NotificationSystemStatus.authorized
          : NotificationSystemStatus.denied,
      accountPreference: _accountNotificationsEnabled,
    );
    final effectiveNotificationsEnabled = permissionState.effectiveStatus;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: const Text('Settings'),
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: colors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'Notifications',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: SwitchListTile(
                    value: _accountNotificationsEnabled,
                    onChanged: (v) => _setNotifications(v),
                    activeThumbColor: colors.secondary,
                    activeTrackColor: colors.secondary.withValues(alpha: 0.4),
                    title: Text(
                      'Push notifications (account)',
                      style: TextStyle(color: colors.onSurface),
                    ),
                    subtitle: Text(
                      effectiveNotificationsEnabled
                          ? 'On (system + account)'
                          : _systemNotificationsEnabled
                          ? 'Off (account)'
                          : 'Off (system permission)',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ),
                if (!_systemNotificationsEnabled) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: openAppSettings,
                    icon: const Icon(Icons.settings_outlined),
                    label: const Text('Open system notification settings'),
                  ),
                ],
                const SizedBox(height: 22),
                Text(
                  'Privacy',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: ListTile(
                    onTap: _openBlockedUsers,
                    title: Text(
                      'Blocked',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    trailing: Text(
                      '$_blockedUsersCount ',
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.onSurface.withValues(alpha: 0.8),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'App mode',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Column(
                    children: [
                      _buildThemeModeTile(
                        title: 'Light',
                        subtitle: 'Clean white interface',
                        mode: ThemeMode.light,
                        selected: selectedMode,
                        icon: Icons.light_mode_rounded,
                      ),
                      _buildThemeModeTile(
                        title: 'Dark',
                        subtitle: 'Matte black interface',
                        mode: ThemeMode.dark,
                        selected: selectedMode,
                        icon: Icons.dark_mode_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
