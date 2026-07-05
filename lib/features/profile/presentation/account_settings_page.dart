import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/permissions/battery_optimization_service.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/change_email_page.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/change_password_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/features/profile/presentation/manage_accounts_page.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _deleting = false;
  bool _deactivating = false;
  bool _showChangePasswordTile = true;
  bool _marketingEmailOptIn = false;
  bool _updatingMarketingOptIn = false;
  String? _accountEmail;
  bool _loadingAccountInfo = true;

  final _batteryOptimizationService = BatteryOptimizationService();
  bool _batteryOptimizationIgnored = true;
  bool _loadingBatteryStatus = true;

  @override
  void initState() {
    super.initState();
    _loadAccountFlags();
    if (Platform.isAndroid) {
      _loadBatteryStatus();
    } else {
      _loadingBatteryStatus = false;
    }
  }

  Future<void> _loadBatteryStatus() async {
    final ignored = await _batteryOptimizationService
        .isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _batteryOptimizationIgnored = ignored;
      _loadingBatteryStatus = false;
    });
  }

  Future<void> _requestIgnoreBatteryOptimization() async {
    await _batteryOptimizationService.requestIgnoreBatteryOptimizations();
    await _loadBatteryStatus();
  }

  Future<void> _loadAccountFlags() async {
    if (mounted) {
      setState(() => _loadingAccountInfo = true);
    }
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      final marketingOptIn =
          me['marketingEmailOptIn'] == true ||
          me['marketing_email_opt_in'] == true;
      final emailRaw = (me['email'] ?? me['emailAddress'] ?? me['email_address'])
          ?.toString()
          .trim();
      setState(() {
        _showChangePasswordTile = AuthRepository().hasLocalPasswordProvider(me);
        _marketingEmailOptIn = marketingOptIn;
        _accountEmail = (emailRaw != null && emailRaw.isNotEmpty)
            ? emailRaw
            : null;
        _loadingAccountInfo = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showChangePasswordTile = true;
        _marketingEmailOptIn = false;
        _accountEmail = null;
        _loadingAccountInfo = false;
      });
    }
  }

  Future<void> _setMarketingEmailOptIn(bool enabled) async {
    if (_updatingMarketingOptIn) return;
    final previous = _marketingEmailOptIn;
    setState(() {
      _marketingEmailOptIn = enabled;
      _updatingMarketingOptIn = true;
    });
    try {
      await AuthRepository().updatePermissions({
        'marketingEmailOptIn': enabled,
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _marketingEmailOptIn = previous);
      await showPremiumErrorDialog(
        context,
        message: 'Marketing email preference could not be saved.',
      );
    } finally {
      if (mounted) setState(() => _updatingMarketingOptIn = false);
    }
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
        style: TextStyle(fontWeight: FontWeight.w600, color: colors.onSurface),
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

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await showPremiumErrorDialog(
        context,
        message: 'Unable to open link.',
      );
    }
  }

  Future<void> _openChangePassword() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangePasswordPage()));
  }

  Future<void> _openChangeEmail() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const ChangeEmailPage()));
    await _loadAccountFlags();
  }

  Future<void> _deactivateAccount() async {
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
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deletee account?'),
        content: const Text(
          'This permanently removes your full account identity and all linked data. Are you sure?',
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

    setState(() => _deleting = true);
    try {
      await AuthRepository().deleteRootAccount();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final deactivateColor = colors.tertiary;
    final selectedMode = context.watch<ThemeProvider>().themeMode;
    final premiumTileBg = theme.brightness == Brightness.dark
        ? colors.surface.withValues(alpha: 0.92)
        : const Color(0xFFF8FBFD);
    final premiumTileBorder = theme.brightness == Brightness.dark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE6EEF4);

    Widget premiumTile(Widget child) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: premiumTileBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: premiumTileBorder),
            boxShadow: [
              BoxShadow(
                color: theme.brightness == Brightness.dark
                    ? Colors.black.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Accounts Center')),
      body: ListView(
        children: <Widget>[
          // ── Manage Accounts ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: ListTile(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const ManageAccountsPage(),
                ),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: colors.primary.withValues(alpha: 0.12),
                ),
              ),
              tileColor: theme.brightness == Brightness.dark
                  ? colors.surface
                  : const Color(0xFFF8FBFD),
              leading: Icon(Icons.manage_accounts_outlined,
                  color: colors.primary),
              title: Text(
                'Manage Accounts',
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                'Add, view or delete your accounts',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Account email',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? colors.surface
                    : const Color(0xFFF8FBFD),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Text(
                _loadingAccountInfo
                    ? 'Loading...'
                    : (_accountEmail ?? 'Email not available'),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'App mode',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              clipBehavior: Clip.antiAlias,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark
                    ? colors.surface
                    : const Color(0xFFF8FBFD),
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
          ),
          const SizedBox(height: 16),
          // İlk açılışta satır kaybolup sonradan belirmesin:
          // loading sürecinde de varsayılan olarak göster, sadece kesin bilgi gelince gizle.
          if (_showChangePasswordTile) ...[
            premiumTile(
              ListTile(
                leading: Icon(
                  Icons.alternate_email_rounded,
                  color: colors.primary,
                ),
                title: const Text('Change email'),
                subtitle: const Text('Update email for this account'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
                onTap: _openChangeEmail,
              ),
            ),
            premiumTile(
              ListTile(
                leading: Icon(Icons.lock_outline, color: colors.primary),
                title: const Text('Change password'),
                subtitle: const Text('Update password for this account'),
                trailing: Icon(
                  Icons.chevron_right_rounded,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
                onTap: _openChangePassword,
              ),
            ),
          ],
          if (_loadingAccountInfo)
            premiumTile(
              ListTile(
                leading: Icon(Icons.campaign_outlined, color: colors.primary),
                title: const Text('Marketing emails'),
                subtitle: const Text('Loading your preference...'),
                trailing: const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            premiumTile(
              ListTile(
                leading: Icon(Icons.campaign_outlined, color: colors.primary),
                title: const Text('Marketing emails'),
                subtitle: const Text(
                  'Receive occasional product updates and special offers',
                ),
                trailing: Switch(
                  value: _marketingEmailOptIn,
                  onChanged: _updatingMarketingOptIn
                      ? null
                      : _setMarketingEmailOptIn,
                ),
              ),
            ),
          if (Platform.isAndroid && !_loadingBatteryStatus)
            premiumTile(
              ListTile(
                leading: Icon(
                  Icons.battery_charging_full_outlined,
                  color: colors.primary,
                ),
                title: const Text('Reliable notifications'),
                subtitle: Text(
                  _batteryOptimizationIgnored
                      ? 'Background activity allowed — notifications arrive on time'
                      : 'Some phones delay notifications in the background. Tap to fix.',
                ),
                trailing: _batteryOptimizationIgnored
                    ? Icon(Icons.check_circle, color: colors.primary)
                    : Icon(
                        Icons.chevron_right_rounded,
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                onTap: _batteryOptimizationIgnored
                    ? null
                    : _requestIgnoreBatteryOptimization,
              ),
            ),
          premiumTile(
            ListTile(
              leading: Icon(Icons.privacy_tip_outlined, color: colors.primary),
              title: const Text('Privacy Policy'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurface.withValues(alpha: 0.45),
              ),
              onTap: () => _openPolicy('/legal/privacy'),
            ),
          ),
          premiumTile(
            ListTile(
              leading: Icon(Icons.gavel_outlined, color: colors.primary),
              title: const Text('Terms of Service'),
              trailing: Icon(
                Icons.chevron_right_rounded,
                color: colors.onSurface.withValues(alpha: 0.45),
              ),
              onTap: () => _openPolicy('/legal/terms'),
            ),
          ),
          premiumTile(
            ListTile(
              leading: Icon(Icons.pause_circle_outline, color: deactivateColor),
              title: Text(
                'Deactivate Account',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: deactivateColor,
                ),
              ),
              subtitle: const Text('Temporarily disable your account'),
              trailing: _deactivating
                  ? SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: deactivateColor,
                      ),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: deactivateColor.withValues(alpha: 0.6),
                    ),
              onTap: (_deactivating || _deleting) ? null : _deactivateAccount,
            ),
          ),
          premiumTile(
            ListTile(
              leading: Icon(Icons.delete_forever_outlined, color: colors.error),
              title: Text(
                'Delete account',
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text('Delete identity and all linked contexts'),
              trailing: _deleting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      Icons.chevron_right_rounded,
                      color: colors.error.withValues(alpha: 0.65),
                    ),
              onTap: (_deleting || _deactivating) ? null : _deleteAccount,
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }
}
