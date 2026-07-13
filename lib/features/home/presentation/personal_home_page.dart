import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_bell.dart';

/// Personal account landing tab. Intentionally empty for now — the surface
/// (feed / highlights) will be designed incrementally. Venue discovery +
/// check-in lives in its own navbar destination (the location tab).
class PersonalHomePage extends StatelessWidget {
  const PersonalHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final bg = isDark ? const Color(0xFF0B0F17) : theme.scaffoldBackgroundColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey[200];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const AppLogo(),
        title: Text(
          'Home',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        actions: const [
          NotificationBell(),
          SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: Center(
        child: Text(
          'Coming soon',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colors.onSurface.withValues(alpha: 0.45),
          ),
        ),
      ),
    );
  }
}
