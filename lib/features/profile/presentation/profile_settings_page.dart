import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/permissions/notification_permission_service.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/blocked_users_page.dart';
import 'package:permission_handler/permission_handler.dart';

class ProfileSettingsPage extends StatefulWidget {
  const ProfileSettingsPage({super.key});

  @override
  State<ProfileSettingsPage> createState() => _ProfileSettingsPageState();
}

class _ProfileSettingsPageState extends State<ProfileSettingsPage> {
  static const _notificationsEnabledKey = 'notifications_enabled';
  final NotificationPermissionService _notificationPermissionService =
      NotificationPermissionService();
  final MatchRepository _matchRepository = MatchRepository();
  bool _loading = true;
  bool _accountNotificationsEnabled = false;
  bool _systemNotificationsEnabled = false;
  int _blockedUsersCount = 0;
  bool _isVenueContext = false;
  bool _deletingAccount = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final me = await AuthRepository().getMe();
      final meContext = MeContextModel.fromMe(me);
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
        _isVenueContext = meContext.lastActiveContext?.toUpperCase() == 'VENUE';
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

    setState(() => _accountNotificationsEnabled = enabled);
    await SecureStorage.write(_notificationsEnabledKey, enabled.toString());
    await _syncNotificationToBackend(enabled);
  }

  Future<void> _deleteAccount() async {
    if (_deletingAccount) return;
    final isVenue = _isVenueContext;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          isVenue ? 'Delete venue account?' : 'Delete personal account?',
        ),
        content: Text(
          isVenue
              ? 'This action is permanent. Your venue account and related access may be removed. Are you sure?'
              : 'This action is permanent. Your personal account and data may be removed. Are you sure?',
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
      await AuthRepository().deleteAccount();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not delete ${_isVenueContext ? 'venue' : 'personal'} account: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _deletingAccount = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                if (!_isVenueContext) ...[
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
                ],
                const SizedBox(height: 22),
                Text(
                  'Account',
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
                    leading: Icon(Icons.delete_forever_outlined, color: colors.error),
                    title: Text(
                      _isVenueContext
                          ? 'Delete venue account'
                          : 'Delete personal account',
                      style: TextStyle(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      _isVenueContext
                          ? 'Remove venue operator access'
                          : 'Permanently remove your personal profile',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.65),
                        fontSize: 13,
                      ),
                    ),
                    trailing: _deletingAccount
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : null,
                    onTap: _deletingAccount ? null : _deleteAccount,
                  ),
                ),
              ],
            ),
    );
  }
}
