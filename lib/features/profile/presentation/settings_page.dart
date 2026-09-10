import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/change_email_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/change_password_page.dart';
import 'package:kmstry_frontend/features/data_export/presentation/data_export_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_detail_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/privacy_choices_page.dart';

/// Unified premium settings hub. Replaces the old "Settings & Activity" +
/// "Account Center" split: one grouped page where every row carries the right
/// scope — account-level (shared across profiles), or context-aware (follows
/// the active Personal / Venue profile).
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with WidgetsBindingObserver {
  // Temporarily hidden until account deactivation is implemented end-to-end.
  static const bool _showAccountDeactivation = false;
  bool _loading = true;
  Map<String, dynamic> _me = const {};

  // Context
  bool _isVenue = false;
  String? _activeVenueId;
  String? _venueName;

  // Account
  String? _email;
  bool _hasPassword = false;
  bool _marketingOptIn = false;
  bool _updatingMarketing = false;

  // Device permissions
  bool _cameraGranted = false;
  bool _locationGranted = false;
  bool _notificationGranted = false;

  // Busy
  bool _loggingOut = false;
  bool _deactivating = false;
  bool _deleting = false;

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
    if (state == AppLifecycleState.resumed) _load(quietly: true);
  }

  Future<void> _load({bool quietly = false}) async {
    if (!quietly && mounted) setState(() => _loading = true);
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);

      final cameraStatus = await Permission.camera.status;
      final locationStatus = await Permission.locationWhenInUse.status;
      final fcm = await FirebaseMessaging.instance.getNotificationSettings();
      final notifGranted =
          fcm.authorizationStatus == AuthorizationStatus.authorized ||
          fcm.authorizationStatus == AuthorizationStatus.provisional;

      final isVenue = ctx.lastActiveContext?.toUpperCase() == 'VENUE';
      final venueId =
          ctx.activeVenueId ??
          (ctx.memberVenues.isNotEmpty ? ctx.memberVenues.first.id : null);
      String? venueName;
      for (final v in ctx.memberVenues) {
        if (v.id == venueId) {
          venueName = v.name;
          break;
        }
      }

      final emailRaw =
          (me['email'] ?? me['emailAddress'] ?? me['email_address'])
              ?.toString()
              .trim();

      if (!mounted) return;
      setState(() {
        _me = me;
        _isVenue = isVenue;
        _activeVenueId = venueId;
        _venueName = venueName;
        _email = (emailRaw != null && emailRaw.isNotEmpty) ? emailRaw : null;
        _hasPassword = AuthRepository().hasLocalPasswordProvider(me);
        _marketingOptIn =
            me['marketingEmailOptIn'] == true ||
            me['marketing_email_opt_in'] == true;
        _cameraGranted = cameraStatus.isGranted;
        _locationGranted = locationStatus.isGranted;
        _notificationGranted = notifGranted;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── actions ────────────────────────────────────────────────
  Future<void> _open(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    if (mounted) _load(quietly: true);
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.siteBaseUrl}$path');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _setMarketing(bool enabled) async {
    if (_updatingMarketing) return;
    final prev = _marketingOptIn;
    setState(() {
      _marketingOptIn = enabled;
      _updatingMarketing = true;
    });
    try {
      await AuthRepository().updatePermissions({
        'marketingEmailOptIn': enabled,
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _marketingOptIn = prev);
      await showPremiumErrorDialog(
        context,
        message: 'Marketing email preference could not be saved.',
      );
    } finally {
      if (mounted) setState(() => _updatingMarketing = false);
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
    ).pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
  }

  Future<void> _deactivate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deactivate account?'),
        content: const Text(
          'Your account will be temporarily disabled. You can contact support to reactivate. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deactivating = true);
    try {
      await AuthRepository().deactivateAccount();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message:
            'Could not deactivate account: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
      );
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: 'Delete your KMSTRY account?',
      message:
          'Your identity, personal profile, venue access, conversations and linked data will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Delete entire account',
    );
    if (!confirmed || !mounted) return;
    setState(() => _deleting = true);
    try {
      await AuthRepository().deleteRootAccount();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (_) => false);
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message:
            'Could not delete account: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ── build ──────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF06091A) : const Color(0xFFF7FAFD);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 36),
              children: [
                _profileHeader(theme),
                const SizedBox(height: 22),

                // ── THIS PROFILE (context-aware) ──
                _label('This profile'),
                _card([
                  _tile(
                    icon: _isVenue
                        ? Icons.storefront_outlined
                        : Icons.person_outline_rounded,
                    color: AppColors.teal,
                    title: _isVenue
                        ? 'Manage this venue'
                        : 'Manage this profile',
                    subtitle: _isVenue
                        ? 'Plan, notifications, offers & more'
                        : 'Profile, notifications, blocked & more',
                    onTap: () => _open(
                      AccountDetailPage(
                        accountName: _isVenue
                            ? (_venueName ?? 'Venue')
                            : (_me['fullName'] ??
                                      _me['full_name'] ??
                                      'Personal')
                                  .toString(),
                        isVenue: _isVenue,
                        venueId: _isVenue ? _activeVenueId : null,
                      ),
                    ),
                  ),
                ]),

                // The current email-change flow verifies the local password.
                // Hide both password-backed actions for Apple/Google-only
                // accounts until provider reauthentication is implemented.
                if (_hasPassword) ...[
                  _label('Account'),
                  _card([
                    _tile(
                      icon: Icons.alternate_email_rounded,
                      color: AppColors.blue,
                      title: 'Change email',
                      subtitle: _email ?? 'Update the login email',
                      onTap: () => _open(const ChangeEmailPage()),
                    ),
                    _tile(
                      icon: Icons.lock_outline_rounded,
                      color: AppColors.blue,
                      title: 'Change password',
                      subtitle: 'Update your password',
                      onTap: () => _open(const ChangePasswordPage()),
                    ),
                  ]),
                ],

                // ── PREFERENCES ──
                _label('Preferences'),
                _card([
                  _themeTile(
                    ThemeMode.light,
                    'Light',
                    Icons.light_mode_outlined,
                  ),
                  _themeTile(ThemeMode.dark, 'Dark', Icons.dark_mode_outlined),
                ]),

                // ── PRIVACY & SAFETY ──
                _label('Privacy & safety'),
                _card([
                  _tile(
                    icon: Icons.shield_outlined,
                    color: AppColors.teal,
                    title: 'Privacy choices',
                    subtitle: 'Control venue discovery analytics',
                    onTap: () => _open(const PrivacyChoicesPage()),
                  ),
                  _permTile(
                    Icons.camera_alt_outlined,
                    'Camera',
                    _cameraGranted,
                  ),
                  _permTile(
                    Icons.location_on_outlined,
                    'Location',
                    _locationGranted,
                  ),
                  _permTile(
                    Icons.notifications_active_outlined,
                    'System notifications',
                    _notificationGranted,
                  ),
                  _switchTile(
                    icon: Icons.mark_email_read_outlined,
                    title: 'Marketing emails',
                    subtitle: 'Product news & offers',
                    value: _marketingOptIn,
                    onChanged: _updatingMarketing ? null : _setMarketing,
                  ),
                ]),

                // ── YOUR DATA ──
                _label('Your data'),
                _card([
                  _tile(
                    icon: Icons.download_rounded,
                    color: AppColors.blue,
                    title: 'Download your data',
                    subtitle: 'Create a private copy of your information',
                    onTap: () => _open(const DataExportPage()),
                  ),
                ]),

                // ── ABOUT & LEGAL ──
                _label('About & legal'),
                _card([
                  _tile(
                    icon: Icons.privacy_tip_outlined,
                    color: AppColors.blue,
                    title: 'Privacy Policy',
                    onTap: () => _openPolicy('/privacy'),
                    external: true,
                  ),
                  _tile(
                    icon: Icons.description_outlined,
                    color: AppColors.blue,
                    title: 'Terms of Service',
                    onTap: () => _openPolicy('/terms'),
                    external: true,
                  ),
                  _tile(
                    icon: Icons.help_outline_rounded,
                    color: AppColors.blue,
                    title: 'Support',
                    onTap: () => _openPolicy('/support'),
                    external: true,
                  ),
                ]),

                // ── DANGER ZONE ──
                const SizedBox(height: 22),
                _card([
                  _tile(
                    icon: Icons.logout_rounded,
                    color: theme.colorScheme.error,
                    title: 'Log out',
                    danger: true,
                    trailing: _loggingOut
                        ? _spinner(theme.colorScheme.error)
                        : null,
                    onTap: _loggingOut ? null : _logout,
                  ),
                  if (_showAccountDeactivation)
                    _tile(
                      icon: Icons.pause_circle_outline_rounded,
                      color: theme.colorScheme.error,
                      title: 'Deactivate account',
                      subtitle: 'Temporarily disable — reversible',
                      danger: true,
                      trailing: _deactivating
                          ? _spinner(theme.colorScheme.error)
                          : null,
                      onTap: _deactivating ? null : _deactivate,
                    ),
                  _tile(
                    icon: Icons.delete_outline_rounded,
                    color: theme.colorScheme.error,
                    title: 'Delete KMSTRY account',
                    subtitle: 'Identity + all contexts — permanent',
                    danger: true,
                    trailing: _deleting
                        ? _spinner(theme.colorScheme.error)
                        : null,
                    onTap: _deleting ? null : _deleteAccount,
                  ),
                ], danger: true),
              ],
            ),
    );
  }

  // ── premium building blocks ────────────────────────────────
  Widget _profileHeader(ThemeData theme) {
    final colors = theme.colorScheme;
    final name = (_me['fullName'] ?? _me['full_name'] ?? '').toString().trim();
    final username = (_me['username'] ?? '').toString().trim();
    final avatar = (_me['photo'] ?? _me['photoUrl'] ?? _me['photo_url'])
        ?.toString()
        .trim();
    final title = _isVenue
        ? (_venueName ?? 'Venue')
        : (name.isEmpty ? 'You' : name);
    final sub = _isVenue
        ? 'Venue account'
        : (username.isNotEmpty ? '@$username' : (_email ?? 'Personal account'));
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.blue.withValues(alpha: 0.16),
            AppColors.magenta.withValues(alpha: 0.12),
          ],
        ),
        border: Border.all(color: AppColors.blue.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: colors.primary.withValues(alpha: 0.15),
            backgroundImage: (avatar != null && avatar.isNotEmpty)
                ? NetworkImage(avatar)
                : null,
            child: (avatar == null || avatar.isEmpty)
                ? Icon(
                    _isVenue ? Icons.storefront_rounded : Icons.person_rounded,
                    color: colors.primary,
                  )
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.65),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _isVenue ? 'Venue' : 'Personal',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 22, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
      ),
    ),
  );

  Widget _card(List<Widget> children, {bool danger = false}) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.92)
        : const Color(0xFFFFFFFF);
    final border = danger
        ? theme.colorScheme.error.withValues(alpha: 0.28)
        : (isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE6EEF4));
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(
          Divider(
            height: 1,
            thickness: 1,
            indent: 58,
            color: (isDark ? Colors.white : Colors.black).withValues(
              alpha: 0.06,
            ),
          ),
        );
      }
      rows.add(children[i]);
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(children: rows),
    );
  }

  Widget _tile({
    required IconData icon,
    required Color color,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
    Widget? trailing,
    bool danger = false,
    bool external = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: color),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: danger ? colors.error : colors.onSurface,
        ),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                color: colors.onSurface.withValues(alpha: 0.55),
              ),
            ),
      trailing:
          trailing ??
          (onTap == null
              ? null
              : Icon(
                  external ? Icons.open_in_new_rounded : Icons.chevron_right,
                  size: external ? 17 : 22,
                  color: colors.onSurface.withValues(alpha: 0.4),
                )),
    );
  }

  Widget _switchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    final colors = Theme.of(context).colorScheme;
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      secondary: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.blue.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 19, color: AppColors.blue),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12.5,
          color: colors.onSurface.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  Widget _permTile(IconData icon, String title, bool granted) {
    final color = granted ? AppColors.teal : AppColors.orange;
    return _tile(
      icon: icon,
      color: color,
      title: title,
      subtitle: granted ? 'Allowed' : 'Not allowed — tap to open settings',
      onTap: () => openAppSettings(),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          granted ? 'On' : 'Off',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _themeTile(ThemeMode mode, String title, IconData icon) {
    final selected = context.watch<ThemeProvider>().themeMode == mode;
    final colors = Theme.of(context).colorScheme;
    return _tile(
      icon: icon,
      color: AppColors.blue,
      title: title,
      onTap: () => context.read<ThemeProvider>().setThemeMode(mode),
      trailing: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
        color: selected
            ? colors.primary
            : colors.onSurface.withValues(alpha: 0.4),
      ),
    );
  }

  Widget _spinner(Color color) => SizedBox(
    width: 18,
    height: 18,
    child: CircularProgressIndicator(strokeWidth: 2, color: color),
  );
}
