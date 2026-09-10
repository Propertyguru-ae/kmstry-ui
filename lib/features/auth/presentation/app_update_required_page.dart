import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/update/app_update_coordinator.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateRequiredPage extends StatefulWidget {
  const AppUpdateRequiredPage({super.key, required this.update});

  final RequiredAppUpdate update;

  @override
  State<AppUpdateRequiredPage> createState() => _AppUpdateRequiredPageState();
}

class _AppUpdateRequiredPageState extends State<AppUpdateRequiredPage> {
  bool _opening = false;
  String? _error;

  Future<void> _openUpdate() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });

    final configured = Uri.tryParse(widget.update.updateUrl ?? '');
    final primary =
        configured ??
        Uri.parse(
          widget.update.platform == 'ios'
              ? 'itms-beta://'
              : 'market://details?id=com.brightminds.kmstry',
        );
    var launched = await launchUrl(
      primary,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && widget.update.platform == 'android') {
      launched = await launchUrl(
        Uri.parse(
          'https://play.google.com/store/apps/details?id=com.brightminds.kmstry',
        ),
        mode: LaunchMode.externalApplication,
      );
    }

    if (!mounted) return;
    setState(() {
      _opening = false;
      if (!launched) {
        _error =
            'We could not open the update page. Please open the store and update KMSTRY.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final background = isDark
        ? const Color(0xFF050814)
        : const Color(0xFFF6F8FC);
    final card = isDark ? const Color(0xFF0C1424) : Colors.white;
    final text = isDark ? Colors.white : const Color(0xFF101522);
    final secondary = isDark
        ? const Color(0xFFAAB3C7)
        : const Color(0xFF5E687A);
    const accent = Color(0xFF42C5F5);

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: background,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                width: double.infinity,
                constraints: const BoxConstraints(maxWidth: 440),
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: isDark ? 0.30 : 0.08,
                      ),
                      blurRadius: 30,
                      offset: const Offset(0, 18),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFF29D3C2),
                            Color(0xFF42A5F5),
                            Color(0xFFE21BD2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.system_update_rounded,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 22),
                    Text(
                      'Update KMSTRY',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        color: text,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'A newer version is required to keep KMSTRY secure and working smoothly.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: secondary,
                        height: 1.5,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: FilledButton(
                        onPressed: _opening ? null : _openUpdate,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: const Color(0xFF06101A),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: _opening
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : const Text(
                                'Update now',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
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
