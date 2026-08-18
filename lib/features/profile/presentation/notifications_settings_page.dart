import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  State<NotificationsSettingsPage> createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState
    extends State<NotificationsSettingsPage> {
  // Per-category push preferences — backend-backed. Muting a category stops
  // its push delivery only; in-app notifications are unaffected.
  bool _messages = true;
  bool _invites = true;
  bool _venueUpdates = true;
  bool _receiveTest = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _messages = me['notifMessagesEnabled'] != false;
        _invites = me['notifInvitesEnabled'] != false;
        _venueUpdates = me['notifVenueUpdatesEnabled'] != false;
        _receiveTest = me['receiveTestNotifications'] != false;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update({
    bool? messages,
    bool? invites,
    bool? venueUpdates,
  }) async {
    // Optimistic — revert the specific toggle on failure.
    setState(() {
      if (messages != null) _messages = messages;
      if (invites != null) _invites = invites;
      if (venueUpdates != null) _venueUpdates = venueUpdates;
    });
    try {
      await AuthRepository().setNotificationPrefs(
        messages: messages,
        invites: invites,
        venueUpdates: venueUpdates,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (messages != null) _messages = !messages;
        if (invites != null) _invites = !invites;
        if (venueUpdates != null) _venueUpdates = !venueUpdates;
      });
    }
  }

  Future<void> _setTestNotifications(bool enabled) async {
    setState(() => _receiveTest = enabled);
    try {
      await AuthRepository().updateMe({'receive_test_notifications': enabled});
    } catch (_) {
      if (mounted) setState(() => _receiveTest = !enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kBorder = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : const Color(0xFFD9E1EA);
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.onSurface),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Notifications',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
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
                  'Choose what you get notified about. You\'ll still see '
                  'everything in your in-app notifications.',
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
                  onChanged: (v) => _update(messages: v),
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _NotifTile(
                  icon: Icons.person_add_alt_1_outlined,
                  title: 'Invites',
                  subtitle: 'Connection requests and venue invites',
                  value: _invites,
                  onChanged: (v) => _update(invites: v),
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _NotifTile(
                  icon: Icons.location_on_outlined,
                  title: 'Venue Updates',
                  subtitle: 'Nearby venues and friends checking in — soon',
                  value: _venueUpdates,
                  onChanged: null, // coming soon — not wired yet
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _NotifTile(
                  icon: Icons.science_outlined,
                  title: 'Test Notifications',
                  subtitle: 'Receive nearby venue test pings',
                  value: _receiveTest,
                  onChanged: _setTestNotifications,
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
  final ValueChanged<bool>? onChanged;
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
    final disabled = onChanged == null;
    return Opacity(
      opacity: disabled ? 0.55 : 1,
      child: Container(
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
      ),
    );
  }
}
