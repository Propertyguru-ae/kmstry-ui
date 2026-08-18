import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';

/// AppBar bell that opens the notifications screen and shows the unread badge.
/// Reads the count from [NotificationUnreadScope] (provided by AppShell) and,
/// after the pushed page returns, re-syncs the real count so the badge clears.
///
/// Opening via a pushed route mirrors how deep links open notifications today,
/// so realtime updates and mark-as-read behaviour are unchanged.
class NotificationBell extends StatelessWidget {
  const NotificationBell({super.key});

  Future<void> _open(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const NotificationPage()),
    );
    if (!context.mounted) return;
    final scope = NotificationUnreadScope.of(context);
    if (scope == null) return;
    try {
      final count = await NotificationRepository().getUnreadCount();
      scope.updateUnreadCount(count);
    } catch (_) {
      // Non-fatal: realtime + app-resume refresh keep the badge eventually correct.
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    final unread = NotificationUnreadScope.of(context)?.unreadCount ?? 0;

    return IconButton(
      onPressed: () => _open(context),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          Icon(Icons.notifications_none, size: 26, color: color),
          if (unread > 0)
            Positioned(
              right: -4,
              top: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                  color: AppTheme.brandCta,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  unread > 99 ? '99+' : '$unread',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
