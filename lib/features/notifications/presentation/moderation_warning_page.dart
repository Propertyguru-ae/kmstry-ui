import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:url_launcher/url_launcher.dart';

class ModerationWarningPage extends StatelessWidget {
  const ModerationWarningPage({super.key, this.contentRemoved = false});

  final bool contentRemoved;

  Future<void> _open(BuildContext context, String path) async {
    final uri = Uri.parse('${AppConfig.siteBaseUrl}$path');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      showBrandedNotice(
        context,
        title: 'Could not open link',
        message: 'Please try again in a moment.',
        tone: BrandedNoticeTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF0D172A) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE1E8F2);
    final secondary = colors.onSurface.withValues(alpha: isDark ? 0.72 : 0.68);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          'Account notice',
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandedNoticeCard(
                    title: 'Community Guidelines warning',
                    message:
                        'A recent contribution was reviewed and found to violate our Community Guidelines.',
                    tone: BrandedNoticeTone.warning,
                    icon: Icons.gpp_maybe_rounded,
                  ),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: border),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark ? 0.20 : 0.05,
                          ),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _NoticeSection(
                          icon: contentRemoved
                              ? Icons.delete_outline_rounded
                              : Icons.info_outline_rounded,
                          title: 'Action taken',
                          body: contentRemoved
                              ? 'The reported message has been removed. Your account remains active.'
                              : 'A formal warning has been recorded. Your account remains active.',
                          color: AppColors.orange,
                          textColor: colors.onSurface,
                          secondaryColor: secondary,
                        ),
                        Divider(height: 32, color: border),
                        _NoticeSection(
                          icon: Icons.shield_outlined,
                          title: 'What happens next',
                          body:
                              'Please keep future contributions respectful and within our Terms. Repeated or severe violations may result in account restrictions.',
                          color: AppColors.blue,
                          textColor: colors.onSurface,
                          secondaryColor: secondary,
                        ),
                        Divider(height: 32, color: border),
                        _NoticeSection(
                          icon: Icons.lock_outline_rounded,
                          title: 'Report privacy',
                          body:
                              'Reports are confidential. We do not disclose the identity of the person who submitted a report.',
                          color: AppColors.teal,
                          textColor: colors.onSurface,
                          secondaryColor: secondary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () => _open(context, '/terms'),
                    icon: const Icon(Icons.description_outlined),
                    label: const Text('Review Terms of Service'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(54),
                      backgroundColor: AppColors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _open(context, '/support'),
                    icon: const Icon(Icons.support_agent_rounded),
                    label: const Text('Contact support'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      foregroundColor: isDark
                          ? AppColors.blueDark
                          : AppColors.blue,
                      side: BorderSide(
                        color: (isDark ? AppColors.blueDark : AppColors.blue)
                            .withValues(alpha: 0.55),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoticeSection extends StatelessWidget {
  const _NoticeSection({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
    required this.textColor,
    required this.secondaryColor,
  });

  final IconData icon;
  final String title;
  final String body;
  final Color color;
  final Color textColor;
  final Color secondaryColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: textColor,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                body,
                style: TextStyle(
                  color: secondaryColor,
                  fontSize: 13.5,
                  height: 1.48,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
