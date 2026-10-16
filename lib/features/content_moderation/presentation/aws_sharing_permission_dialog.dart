import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

Future<bool> showAwsSharingPermissionDialog(
  BuildContext context,
  Map<String, dynamic> notice,
) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AwsSharingPermissionDialog(notice: notice),
    ) ??
    false;

/// Uygulamanın standart popup dili (ikon kutusu, kalın başlık, düz mavi CTA,
/// altta metin butonu). Uzun metin kendi içinde kayar; butonlar hep görünür.
class _AwsSharingPermissionDialog extends StatefulWidget {
  const _AwsSharingPermissionDialog({required this.notice});
  final Map<String, dynamic> notice;

  @override
  State<_AwsSharingPermissionDialog> createState() =>
      _AwsSharingPermissionDialogState();
}

class _AwsSharingPermissionDialogState
    extends State<_AwsSharingPermissionDialog> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final notice = widget.notice;
    final paragraphs = (notice['paragraphs'] as List? ?? const [])
        .map((text) => text.toString())
        .toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF111425) : Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: AppColors.blue.withValues(alpha: isDark ? 0.28 : 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.14),
              blurRadius: 32,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  color: AppColors.blue,
                  size: 25,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              notice['title'] as String? ??
                  'Safety checks for your public content',
              style: theme.textTheme.titleLarge?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: Scrollbar(
                controller: _scroll,
                child: SingleChildScrollView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(right: 6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < paragraphs.length; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i == paragraphs.length - 1 ? 0 : 12,
                          ),
                          child: Text(
                            paragraphs[i],
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurface.withValues(alpha: 0.68),
                              height: 1.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: notice['acceptLabel'] as String? ?? 'Allow safety checks',
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(46),
                foregroundColor: colors.onSurface.withValues(alpha: 0.72),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              child: Text(notice['declineLabel'] as String? ?? 'Not now'),
            ),
          ],
        ),
      ),
    );
  }
}
