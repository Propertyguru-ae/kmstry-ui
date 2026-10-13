import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';

/// Uygulamanın alt sayfa (bottom sheet) dili: zemin, tutma çubuğu, başlık ve
/// kart içinde ikonlu seçenek satırları. Mesajlaşma "+" menüsü ile aynı palet;
/// Photo credits, rapor seçenekleri ve profil menüsü bunu paylaşır.
class AppSheetPalette {
  const AppSheetPalette(this.isDark);

  factory AppSheetPalette.of(BuildContext context) =>
      AppSheetPalette(Theme.of(context).brightness == Brightness.dark);

  final bool isDark;

  Color get surface => isDark ? const Color(0xFF121A2B) : Colors.white;
  Color get barrier => Colors.black.withValues(alpha: isDark ? 0.55 : 0.35);
  Color get title => isDark ? Colors.white : AppColors.lightTextPrimary;
  Color get muted => isDark
      ? Colors.white.withValues(alpha: 0.62)
      : AppColors.lightTextSecondary;
  Color get handle => (isDark ? Colors.white : Colors.black).withValues(
    alpha: isDark ? 0.22 : 0.14,
  );
  Color get card =>
      isDark ? Colors.white.withValues(alpha: 0.04) : const Color(0xFFF5F7FA);
  Color get border => isDark
      ? Colors.white.withValues(alpha: 0.08)
      : Colors.black.withValues(alpha: 0.06);
}

const appSheetShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
);

Future<T?> showAppSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool isScrollControlled = false,
}) {
  final palette = AppSheetPalette.of(context);
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useSafeArea: true,
    backgroundColor: palette.surface,
    barrierColor: palette.barrier,
    shape: appSheetShape,
    builder: builder,
  );
}

/// Tutma çubuğu + başlık (+ isteğe bağlı açıklama).
class AppSheetHeader extends StatelessWidget {
  const AppSheetHeader({super.key, this.title, this.subtitle});
  final String? title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = AppSheetPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: palette.handle,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        if (title != null) ...[
          const SizedBox(height: 16),
          Text(
            title!,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: palette.title,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.muted, fontSize: 13),
          ),
        ],
        const SizedBox(height: 18),
      ],
    );
  }
}

class AppSheetSectionLabel extends StatelessWidget {
  const AppSheetSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        color: AppSheetPalette.of(context).muted,
        fontSize: 11.5,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
      ),
    ),
  );
}

/// Satırları yuvarlak bir kartta, aralarında ince ayraçla toplar.
class AppSheetCard extends StatelessWidget {
  const AppSheetCard({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = AppSheetPalette.of(context);
    return Container(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, indent: 66, color: palette.border),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

class AppSheetRow extends StatelessWidget {
  const AppSheetRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.showLink = false,
    this.onTap,
  });
  final Widget leading;
  final String title;
  final String? subtitle;

  /// Uygulama dışına (ör. Google Maps) götüren satırlarda sağda link ikonu.
  final bool showLink;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppSheetPalette.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: palette.title,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        color: palette.muted,
                        fontSize: 12.5,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (showLink) ...[
              const SizedBox(width: 8),
              Icon(Icons.open_in_new_rounded, size: 18, color: palette.muted),
            ],
          ],
        ),
      ),
    );
  }
}

class AppSheetIconTile extends StatelessWidget {
  const AppSheetIconTile({super.key, required this.icon, required this.color});
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 21, color: color),
    );
  }
}
