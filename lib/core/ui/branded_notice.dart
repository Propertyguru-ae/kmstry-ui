import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

enum BrandedNoticeTone { info, success, warning, error }

class BrandedNoticeCard extends StatelessWidget {
  const BrandedNoticeCard({
    super.key,
    required this.title,
    required this.message,
    this.tone = BrandedNoticeTone.info,
    this.icon,
    this.compact = false,
  });

  final String title;
  final String message;
  final BrandedNoticeTone tone;
  final IconData? icon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _accent(isDark);
    final resolvedIcon = icon ?? _defaultIcon;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: _borderGradient(isDark),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.16 : 0.1),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.all(1.2),
        padding: EdgeInsets.all(compact ? 13 : 15),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D172A) : const Color(0xFFF8FBFF),
          borderRadius: BorderRadius.circular(16.8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: compact ? 38 : 42,
              height: compact ? 38 : 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: _iconGradient(isDark),
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                resolvedIcon,
                color: _iconForeground,
                size: compact ? 20 : 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextPrimary
                          : AppColors.lightTextPrimary,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                      height: 1.42,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData get _defaultIcon => switch (tone) {
    BrandedNoticeTone.info => Icons.info_outline_rounded,
    BrandedNoticeTone.success => Icons.check_rounded,
    BrandedNoticeTone.warning => Icons.priority_high_rounded,
    BrandedNoticeTone.error => Icons.close_rounded,
  };

  Color get _iconForeground => switch (tone) {
    BrandedNoticeTone.warning || BrandedNoticeTone.error => Colors.white,
    _ => const Color(0xFF04131D),
  };

  Color _accent(bool isDark) => switch (tone) {
    BrandedNoticeTone.info => isDark ? AppColors.blueDark : AppColors.blueLight,
    BrandedNoticeTone.success =>
      isDark ? AppColors.tealDark : const Color(0xFF087D61),
    BrandedNoticeTone.warning => AppColors.orange,
    BrandedNoticeTone.error => const Color(0xFFE34B65),
  };

  List<Color> _borderGradient(bool isDark) => switch (tone) {
    BrandedNoticeTone.info =>
      isDark
          ? [AppColors.blueDark, AppColors.magentaDark]
          : [AppColors.blueLight, AppColors.brandLight],
    BrandedNoticeTone.success => [
      isDark ? AppColors.tealDark : const Color(0xFF087D61),
      AppColors.blue,
    ],
    BrandedNoticeTone.warning => [AppColors.orange, AppColors.magenta],
    BrandedNoticeTone.error => [
      const Color(0xFFE34B65),
      isDark ? AppColors.magentaDark : AppColors.brand,
    ],
  };

  List<Color> _iconGradient(bool isDark) => switch (tone) {
    BrandedNoticeTone.info => [
      isDark ? AppColors.blueDark : AppColors.blue,
      AppColors.teal,
    ],
    BrandedNoticeTone.success => [AppColors.tealDark, AppColors.blueDark],
    BrandedNoticeTone.warning => [AppColors.orange, AppColors.magenta],
    BrandedNoticeTone.error => [const Color(0xFFE34B65), AppColors.magentaDark],
  };
}

void showBrandedNotice(
  BuildContext context, {
  required String title,
  required String message,
  BrandedNoticeTone tone = BrandedNoticeTone.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 6),
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        padding: EdgeInsets.zero,
        duration: duration,
        backgroundColor: Colors.transparent,
        content: BrandedNoticeCard(
          title: title,
          message: message,
          tone: tone,
          icon: icon,
          compact: true,
        ),
      ),
    );
}
