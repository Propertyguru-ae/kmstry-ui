import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';

/// Venue-account push notification settings (per membership). Mirrors the
/// personal notifications page. Muting a category stops its push delivery only;
/// in-app notifications are unaffected.
class VenueNotificationsSettingsPage extends StatefulWidget {
  final String venueId;
  final String venueName;
  const VenueNotificationsSettingsPage({
    super.key,
    required this.venueId,
    required this.venueName,
  });

  @override
  State<VenueNotificationsSettingsPage> createState() =>
      _VenueNotificationsSettingsPageState();
}

class _VenueNotificationsSettingsPageState
    extends State<VenueNotificationsSettingsPage> {
  final _repo = VenueOwnerRepository();
  bool _team = true;
  bool _events = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await _repo.getNotificationPrefs(widget.venueId);
      if (!mounted) return;
      setState(() {
        _team = prefs['team'] ?? true;
        _events = prefs['events'] ?? true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _update({bool? team, bool? events}) async {
    setState(() {
      if (team != null) _team = team;
      if (events != null) _events = events;
    });
    try {
      await _repo.setNotificationPrefs(
        widget.venueId,
        team: team,
        events: events,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (team != null) _team = !team;
        if (events != null) _events = !events;
      });
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
                Text(
                  'Push Notifications',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For ${widget.venueName}. You\'ll still see everything in '
                  'your in-app notifications.',
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(height: 12),
                _VenueNotifTile(
                  icon: Icons.groups_outlined,
                  title: 'Team updates',
                  subtitle: 'Members joining, invite responses, role changes',
                  value: _team,
                  onChanged: (v) => _update(team: v),
                  colors: colors,
                ),
                const SizedBox(height: 8),
                _VenueNotifTile(
                  icon: Icons.event_available_outlined,
                  title: 'Event activity',
                  subtitle: 'When your events are filling up',
                  value: _events,
                  onChanged: (v) => _update(events: v),
                  colors: colors,
                ),
                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

class _VenueNotifTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colors;

  const _VenueNotifTile({
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
