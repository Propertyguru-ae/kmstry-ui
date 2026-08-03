import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:url_launcher/url_launcher.dart';

class LegalUpdateRequiredPage extends StatefulWidget {
  const LegalUpdateRequiredPage({super.key});

  @override
  State<LegalUpdateRequiredPage> createState() =>
      _LegalUpdateRequiredPageState();
}

class _LegalUpdateRequiredPageState extends State<LegalUpdateRequiredPage> {
  bool _accepted = false;
  bool _accepting = false;
  bool _loggingOut = false;
  String? _error;

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.siteBaseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      setState(() => _error = 'Could not open the document. Please try again.');
    }
  }

  Future<void> _continue() async {
    if (!_accepted || _accepting || _loggingOut) return;
    setState(() {
      _accepting = true;
      _error = null;
    });

    try {
      await AuthRepository().acceptActiveLegalVersions();
      if (!mounted) return;
      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.authGate, (route) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'We could not save your acceptance. Please try again.';
        _accepting = false;
      });
    }
  }

  Future<void> _logout() async {
    if (_accepting || _loggingOut) return;
    setState(() {
      _loggingOut = true;
      _error = null;
    });

    try {
      await AuthRepository().logout();
    } catch (_) {
      // Even if the server logout fails, clear the local session through the
      // repository path as far as possible and return to startup.
    }

    if (!mounted) return;
    Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AuthRoutes.startupGate, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF050814) : const Color(0xFFF7F9FC);
    final card = isDark ? const Color(0xFF0C1220) : Colors.white;
    final primary = isDark ? const Color(0xFF1A9FE8) : const Color(0xFF087CC1);
    final text = isDark ? Colors.white : const Color(0xFF121826);
    final sub = isDark ? const Color(0xFF9EA6B8) : const Color(0xFF5D6678);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.28 : 0.08,
                      ),
                      blurRadius: 28,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: primary.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.verified_user_outlined, color: primary),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      'Terms and Privacy updated',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: text,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Please review the latest Terms of Service and Privacy Policy before continuing.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: sub,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: _DocButton(
                            label: 'Terms of Service',
                            onTap: () => _openPolicy('/terms'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _DocButton(
                            label: 'Privacy Policy',
                            onTap: () => _openPolicy('/privacy'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _accepted = !_accepted),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Checkbox(
                              value: _accepted,
                              onChanged: (value) =>
                                  setState(() => _accepted = value ?? false),
                              activeColor: primary,
                            ),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'I have read and agree to the updated Terms of Service and Privacy Policy.',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: text.withValues(alpha: 0.9),
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 10),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFFFF5C68),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    Text(
                      'If you do not agree, you can log out and return later.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: sub,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: FilledButton(
                        onPressed: _accepted && !_accepting && !_loggingOut
                            ? _continue
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: primary,
                          disabledBackgroundColor: primary.withValues(
                            alpha: 0.35,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _accepting
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Accept and continue'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: TextButton(
                        onPressed: _accepting || _loggingOut ? null : _logout,
                        child: _loggingOut
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: sub,
                                ),
                              )
                            : Text(
                                'Log out',
                                style: TextStyle(
                                  color: sub,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DocButton extends StatelessWidget {
  const _DocButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = isDark ? Colors.white : const Color(0xFF121826);
    final bg = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : const Color(0xFFF1F5F9);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.16)
        : const Color(0xFFD7DEE9);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.open_in_new_rounded, size: 16, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
