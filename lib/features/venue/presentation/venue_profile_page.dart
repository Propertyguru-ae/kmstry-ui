import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_edit_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

class VenueProfilePage extends StatefulWidget {
  final String? activeVenueName;
  final List<String>? venueNames;
  final String? venueId;

  const VenueProfilePage({
    super.key,
    this.activeVenueName,
    this.venueNames,
    this.venueId,
  });

  @override
  State<VenueProfilePage> createState() => _VenueProfilePageState();
}

class _VenueProfilePageState extends State<VenueProfilePage> {
  bool _loading = true;
  VenueOwnerStatsVenue? _venue;
  VenueMemberRole _venueRole = VenueMemberRole.staff;

  @override
  void initState() {
    super.initState();
    _loadVenueProfile();
  }

  Future<void> _loadVenueProfile() async {
    setState(() => _loading = true);
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);

      String? venueId = widget.venueId;
      if (venueId == null || venueId.isEmpty) {
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) &&
            ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
      }

      if (venueId != null && venueId.isNotEmpty) {
        final memberVenue = ctx.memberVenues
            .where((v) => v.id == venueId)
            .firstOrNull;
        final resolvedRole = VenueMemberRoleExt.fromApi(
          memberVenue?.role ?? 'STAFF',
        );

        final response = await VenueOwnerRepository().getOwnerStats(venueId);
        if (!mounted) return;
        setState(() {
          _venue = response.venue;
          _venueRole = resolvedRole;
          _loading = false;
        });
      } else {
        if (!mounted) return;
        setState(() => _loading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openEdit() async {
    final venue = _venue;
    if (venue == null) return;
    final updated = await Navigator.push<VenueOwnerStatsVenue>(
      context,
      MaterialPageRoute(builder: (_) => VenueEditPage(venue: venue)),
    );
    if (updated != null && mounted) setState(() => _venue = updated);
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
    );
  }

  Future<void> _openTeam() async {
    final venueId = _venue?.id;
    if (venueId == null) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenueTeamPage(venueId: venueId, callerRole: _venueRole),
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$feature coming soon'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }

    final venue = _venue;
    final colors = Theme.of(context).colorScheme;
    final isOwner = _venueRole == VenueMemberRole.owner;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      body: CustomScrollView(
        slivers: [
          // ── Cover + action bar ──────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            automaticallyImplyLeading: false,
            backgroundColor: colors.surfaceContainerHighest,
            elevation: 0,
            flexibleSpace: FlexibleSpaceBar(
              background: venue?.photo != null && venue!.photo!.isNotEmpty
                  ? Image.network(
                      venue.photo!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) =>
                          _CoverPlaceholder(name: venue.name, colors: colors),
                    )
                  : _CoverPlaceholder(
                      name: venue?.name ?? widget.activeVenueName ?? '',
                      colors: colors,
                    ),
            ),
            actions: [
              if (venue != null)
                IconButton(
                  onPressed: _openEdit,
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  tooltip: 'Edit venue',
                ),
              IconButton(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined, color: Colors.white),
                tooltip: 'Settings',
              ),
              const SizedBox(width: 4),
            ],
          ),

          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Identity card ─────────────────────────────────────────
                _IdentityCard(
                  venue: venue,
                  fallbackName: widget.activeVenueName ?? 'Venue account',
                  venueRole: _venueRole,
                  colors: colors,
                ),

                // ── Description ───────────────────────────────────────────
                if (venue?.description != null &&
                    venue!.description!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionHeader(label: 'About', colors: colors),
                        const SizedBox(height: 6),
                        Text(
                          venue.description!,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.onSurface.withValues(alpha: 0.8),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 2),

                // ── Team management ───────────────────────────────────────
                _SectionCard(
                  child: Column(
                    children: [
                      _ActionRow(
                        icon: Icons.group_outlined,
                        label: 'Team Management',
                        subtitle: isOwner
                            ? 'Manage members & roles'
                            : 'View team',
                        onTap: venue != null ? _openTeam : null,
                        colors: colors,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 2),

                // ── Quick content actions ─────────────────────────────────
                _QuickActionsBar(
                  onEvent: () => _comingSoon('Events'),
                  onPost: () => _comingSoon('Posts'),
                  onStory: () => _comingSoon('Stories'),
                  colors: colors,
                ),

                const SizedBox(height: 2),

                // ── Events ────────────────────────────────────────────────
                _ContentSection(
                  icon: Icons.event_outlined,
                  title: 'Events',
                  emptyLabel: 'No upcoming events',
                  emptyHint: 'Publish your first event',
                  onAdd: () => _comingSoon('Events'),
                  colors: colors,
                ),

                const SizedBox(height: 2),

                // ── Posts ─────────────────────────────────────────────────
                _PostsSection(
                  onAdd: () => _comingSoon('Posts'),
                  colors: colors,
                ),

                SizedBox(
                  height: MediaQuery.of(context).padding.bottom +
                      kBottomNavigationBarHeight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Cover placeholder ────────────────────────────────────────────────────────

class _CoverPlaceholder extends StatelessWidget {
  final String name;
  final ColorScheme colors;
  const _CoverPlaceholder({required this.name, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: 0.85),
            colors.secondary.withValues(alpha: 0.65),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: name.isNotEmpty
          ? Text(
              name[0].toUpperCase(),
              style: const TextStyle(
                fontSize: 72,
                fontWeight: FontWeight.w900,
                color: Colors.white30,
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

// ─── Identity card ────────────────────────────────────────────────────────────

class _IdentityCard extends StatelessWidget {
  final VenueOwnerStatsVenue? venue;
  final String fallbackName;
  final VenueMemberRole venueRole;
  final ColorScheme colors;

  const _IdentityCard({
    required this.venue,
    required this.fallbackName,
    required this.venueRole,
    required this.colors,
  });

  String get _roleBadgeLabel {
    switch (venueRole) {
      case VenueMemberRole.owner:
        return 'Owner';
      case VenueMemberRole.admin:
        return 'Admin';
      default:
        return 'Staff';
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = venue?.name ?? fallbackName;
    final city = venue?.city;
    final address = venue?.address;
    final type = venue?.type;
    final isVerified = venue?.verificationLevel == 'VERIFIED';

    final locationParts = [
      address,
      city,
    ].where((s) => s != null && s.isNotEmpty).cast<String>().toList();

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Name + verified row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
              ),
              if (isVerified) ...[
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Icon(
                    Icons.verified_rounded,
                    color: colors.primary,
                    size: 22,
                  ),
                ),
              ],
            ],
          ),

          const SizedBox(height: 8),

          // Type + role badges
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (type != null && type.isNotEmpty)
                _Chip(
                  label: type,
                  icon: Icons.storefront_outlined,
                  colors: colors,
                  outlined: true,
                ),
              _Chip(
                label: _roleBadgeLabel,
                icon: Icons.badge_outlined,
                colors: colors,
                outlined: false,
              ),
            ],
          ),

          // Location
          if (locationParts.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.location_on_outlined,
                  size: 14,
                  color: colors.onSurface.withValues(alpha: 0.45),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    locationParts.join(', '),
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Quick content actions bar ────────────────────────────────────────────────

class _QuickActionsBar extends StatelessWidget {
  final VoidCallback onEvent;
  final VoidCallback onPost;
  final VoidCallback onStory;
  final ColorScheme colors;

  const _QuickActionsBar({
    required this.onEvent,
    required this.onPost,
    required this.onStory,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _QuickTile(
            icon: Icons.event_outlined,
            label: 'Event',
            onTap: onEvent,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _QuickTile(
            icon: Icons.grid_on_outlined,
            label: 'Post',
            onTap: onPost,
            colors: colors,
          ),
          const SizedBox(width: 8),
          _QuickTile(
            icon: Icons.auto_stories_outlined,
            label: 'Story',
            onTap: onStory,
            colors: colors,
          ),
        ],
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme colors;

  const _QuickTile({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: colors.onPrimaryContainer),
              const SizedBox(height: 4),
              Text(
                '+ $label',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: colors.onPrimaryContainer,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Generic content section (Events / Stories) ───────────────────────────────

class _ContentSection extends StatelessWidget {
  final IconData icon;
  final String title;
  final String emptyLabel;
  final String emptyHint;
  final VoidCallback onAdd;
  final ColorScheme colors;

  const _ContentSection({
    required this.icon,
    required this.title,
    required this.emptyLabel,
    required this.emptyHint,
    required this.onAdd,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(label: title, colors: colors),
              GestureDetector(
                onTap: onAdd,
                child: Text(
                  '+ Add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Center(
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.3),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  emptyLabel,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colors.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(height: 3),
                GestureDetector(
                  onTap: onAdd,
                  child: Text(
                    emptyHint,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Posts grid section ───────────────────────────────────────────────────────

class _PostsSection extends StatelessWidget {
  final VoidCallback onAdd;
  final ColorScheme colors;

  const _PostsSection({required this.onAdd, required this.colors});

  static Widget _postRow(
    List<int> indices,
    double cell,
    double gap,
    ColorScheme colors,
    VoidCallback onAdd,
  ) {
    return Row(
      children: [
        for (int k = 0; k < indices.length; k++) ...[
          if (k > 0) SizedBox(width: gap),
          _PostTile(
            index: indices[k],
            size: cell,
            colors: colors,
            onAdd: onAdd,
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _SectionHeader(label: 'Posts', colors: colors),
              GestureDetector(
                onTap: onAdd,
                child: Text(
                  '+ Add',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = 3.0;
              final cell = (constraints.maxWidth - gap * 2) / 3;
              final indices = List.generate(6, (i) => i);
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _postRow(indices.sublist(0, 3), cell, gap, colors, onAdd),
                  const SizedBox(height: gap),
                  _postRow(indices.sublist(3, 6), cell, gap, colors, onAdd),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─── Post placeholder tile ────────────────────────────────────────────────────

class _PostTile extends StatelessWidget {
  final int index;
  final double size;
  final ColorScheme colors;
  final VoidCallback onAdd;

  const _PostTile({
    required this.index,
    required this.size,
    required this.colors,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final isAdd = index == 0;
    return GestureDetector(
      onTap: isAdd ? onAdd : null,
      child: SizedBox(
        width: size,
        height: size,
        child: Container(
          decoration: BoxDecoration(
            color: isAdd
                ? colors.surfaceContainerHighest.withValues(alpha: 0.5)
                : colors.surfaceContainerHighest.withValues(
                    alpha: 0.28 - (index * 0.02).clamp(0.0, 0.16),
                  ),
            borderRadius: BorderRadius.circular(5),
            border: isAdd
                ? Border.all(
                    color: colors.outline.withValues(alpha: 0.2),
                    width: 1.5,
                  )
                : null,
          ),
          child: isAdd
              ? Icon(
                  Icons.add,
                  size: 24,
                  color: colors.onSurface.withValues(alpha: 0.28),
                )
              : null,
        ),
      ),
    );
  }
}

// ─── Section card wrapper ─────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final Widget child;
  const _SectionCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: child,
    );
  }
}

// ─── Section header label ─────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  const _SectionHeader({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: colors.onSurface,
        letterSpacing: 0.1,
      ),
    );
  }
}

// ─── Action row ───────────────────────────────────────────────────────────────

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback? onTap;
  final ColorScheme colors;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.colors,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: colors.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: colors.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colors.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small chip badge ─────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final ColorScheme colors;
  final bool outlined;

  const _Chip({
    required this.label,
    required this.icon,
    required this.colors,
    required this.outlined,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: outlined ? Colors.transparent : colors.primaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: outlined
            ? Border.all(color: colors.outline.withValues(alpha: 0.4), width: 1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 13,
            color: outlined
                ? colors.onSurface.withValues(alpha: 0.55)
                : colors.onPrimaryContainer,
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: outlined
                  ? colors.onSurface.withValues(alpha: 0.65)
                  : colors.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}
