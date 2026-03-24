import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/forgot_password_page.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({super.key});

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  bool _deleting = false;
  bool _deactivating = false;

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

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open link.')),
      );
    }
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ForgotPasswordPage()),
    );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not deactivate account: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _deactivating = false);
    }
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete account?'),
        content: const Text(
          'This action is permanent. All account data may be removed. Are you sure?',
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
            'Could not delete account: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
          ),
        ),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: ListView(
        children: <Widget>[
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
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Forgot Password'),
            subtitle: const Text('Send password reset email'),
            onTap: _openForgotPassword,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.privacy_tip_outlined, color: colors.primary),
            title: const Text('Privacy Policy'),
            onTap: () => _openPolicy('/legal/privacy'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.gavel_outlined, color: colors.primary),
            title: const Text('Terms of Service'),
            onTap: () => _openPolicy('/legal/terms'),
          ),
          const Divider(height: 1),
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
                : null,
            onTap: (_deactivating || _deleting) ? null : _deactivateAccount,
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: colors.error),
            title: Text(
              'Delete Account',
              style: TextStyle(color: colors.error, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text('Permanently remove your account'),
            trailing: _deleting
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : null,
            onTap: (_deleting || _deactivating) ? null : _deleteAccount,
          ),
        ],
      ),
    );
  }
}
