import 'package:flutter/material.dart';

import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class PrivacyChoicesPage extends StatefulWidget {
  const PrivacyChoicesPage({super.key});

  @override
  State<PrivacyChoicesPage> createState() => _PrivacyChoicesPageState();
}

class _PrivacyChoicesPageState extends State<PrivacyChoicesPage> {
  bool _loading = true;
  bool _saving = false;
  bool _optionalAnalyticsEnabled = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await AuthRepository().getPrivacyPreferences();
      if (!mounted) return;
      setState(() {
        _optionalAnalyticsEnabled = data['optionalAnalyticsEnabled'] == true;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showPremiumErrorDialog(
        context,
        message: 'Your privacy choices could not be loaded. Please try again.',
      );
    }
  }

  Future<void> _setOptionalAnalytics(bool enabled) async {
    if (_saving) return;
    final previous = _optionalAnalyticsEnabled;
    setState(() {
      _optionalAnalyticsEnabled = enabled;
      _saving = true;
    });
    try {
      final data = await AuthRepository().setOptionalAnalyticsEnabled(enabled);
      if (!mounted) return;
      setState(() {
        _optionalAnalyticsEnabled = data['optionalAnalyticsEnabled'] == true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _optionalAnalyticsEnabled = previous);
      await showPremiumErrorDialog(
        context,
        message: 'Your privacy choice could not be saved. Please try again.',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF06091A)
        : const Color(0xFFF7FAFD);
    final cardColor = isDark
        ? colors.surface.withValues(alpha: 0.92)
        : Colors.white;

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Privacy choices'),
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      colors: [
                        AppColors.blue.withValues(alpha: 0.16),
                        AppColors.magenta.withValues(alpha: 0.10),
                      ],
                    ),
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: AppColors.blue,
                        size: 26,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'You are in control',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'This account-level choice applies to both your Personal and Venue profiles.',
                              style: TextStyle(
                                height: 1.4,
                                fontSize: 13,
                                color: colors.onSurface.withValues(alpha: 0.68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'OPTIONAL ANALYTICS',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.9,
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFE6EEF4),
                    ),
                  ),
                  child: SwitchListTile.adaptive(
                    value: _optionalAnalyticsEnabled,
                    onChanged: _saving ? null : _setOptionalAnalytics,
                    contentPadding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
                    secondary: Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.teal.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.insights_outlined,
                              size: 21,
                              color: AppColors.teal,
                            ),
                    ),
                    title: const Text(
                      'Share venue discovery analytics',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Text(
                        'Allow venue discovery activity to be linked to your account to help improve search and trending insights. When off, trend counts remain anonymous.',
                        style: TextStyle(
                          height: 1.35,
                          fontSize: 12.5,
                          color: colors.onSurface.withValues(alpha: 0.60),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppColors.blue.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.security_rounded,
                        color: AppColors.blue,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Essential security, fraud prevention and crash diagnostics remain active. They protect KMSTRY and are not used for advertising.',
                          style: TextStyle(
                            height: 1.4,
                            fontSize: 12.5,
                            color: colors.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
