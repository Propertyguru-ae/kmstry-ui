import 'package:flutter/material.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState
    extends State<NotificationsSettingsPage> {
  // Push Notifications — UI only, backend bağlantısı sonra eklenecek
  bool _messages = true;
  bool _invites = true;
  bool _venueUpdates = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Notifications',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Push Notifications ───────────────────────────────
          Text(
            'Push Notifications',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Choose what you get notified about.',
            style: TextStyle(
              fontSize: 13,
              color: colors.onSurface.withValues(alpha: 0.55),
            ),
          ),
          const SizedBox(height: 12),
          _NotifTile(
            icon: Icons.chat_bubble_outline_rounded,
            title: 'Messages',
            subtitle: 'New messages from your connections',
            value: _messages,
            onChanged: (v) => setState(() => _messages = v),
            colors: colors,
          ),
          const SizedBox(height: 8),
          _NotifTile(
            icon: Icons.person_add_alt_1_outlined,
            title: 'Invites',
            subtitle: 'Connection requests and venue invites',
            value: _invites,
            onChanged: (v) => setState(() => _invites = v),
            colors: colors,
          ),
          const SizedBox(height: 8),
          _NotifTile(
            icon: Icons.location_on_outlined,
            title: 'Venue Updates',
            subtitle: 'Live updates and offers from nearby venues',
            value: _venueUpdates,
            onChanged: (v) => setState(() => _venueUpdates = v),
            colors: colors,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _NotifTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colors;

  const _NotifTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark
        ? colors.surface.withValues(alpha: 0.92)
        : const Color(0xFFF8FBFD);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE6EEF4);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.22)
                : Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        activeThumbColor: colors.secondary,
        activeTrackColor: colors.secondary.withValues(alpha: 0.4),
        secondary: Icon(icon, color: colors.primary),
        title: Text(
          title,
          style: TextStyle(
            color: colors.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.6),
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
