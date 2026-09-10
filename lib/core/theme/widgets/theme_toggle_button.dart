import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme_provider.dart';

class ThemeToggleButton extends StatelessWidget {
  const ThemeToggleButton({super.key});

  Future<void> _openThemeSheet(BuildContext context) async {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    final current = themeProvider.themeMode;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        Widget item({
          required String title,
          required String subtitle,
          required IconData icon,
          required ThemeMode mode,
        }) {
          final selected = current == mode;
          final colors = Theme.of(context).colorScheme;
          return ListTile(
            leading: Icon(
              icon,
              color: selected
                  ? colors.primary
                  : colors.onSurface.withValues(alpha: 0.7),
            ),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: selected
                ? Icon(Icons.check_circle, color: colors.primary)
                : const SizedBox.shrink(),
            onTap: () async {
              await themeProvider.setThemeMode(mode);
              if (context.mounted) Navigator.pop(context);
            },
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Appearance',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                item(
                  title: 'Light',
                  subtitle: 'Bright background, same accent palette',
                  icon: Icons.wb_sunny_rounded,
                  mode: ThemeMode.light,
                ),
                item(
                  title: 'Dark',
                  subtitle: 'Matte black, same accent palette',
                  icon: Icons.dark_mode_rounded,
                  mode: ThemeMode.dark,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;

    return IconButton(
      tooltip: 'Appearance',
      onPressed: () => _openThemeSheet(context),
      icon: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
      color: isDark
          ? const Color(0xFF1FE4D2)
          : Theme.of(context).colorScheme.primary,
      style: IconButton.styleFrom(
        backgroundColor: Theme.of(
          context,
        ).colorScheme.surface.withValues(alpha: isDark ? 0.65 : 0.95),
      ),
    );
  }
}
