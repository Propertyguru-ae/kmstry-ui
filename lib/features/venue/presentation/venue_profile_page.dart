import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_edit_page.dart';

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

  @override
  void initState() {
    super.initState();
    _loadVenueProfile();
  }

  Future<void> _loadVenueProfile() async {
    setState(() => _loading = true);
    try {
      String? venueId = widget.venueId;
      if (venueId == null || venueId.isEmpty) {
        final me = await AuthRepository().getMe();
        final ctx = MeContextModel.fromMe(me);
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) &&
            ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
      }

      if (venueId != null && venueId.isNotEmpty) {
        final stats = await VenueOwnerRepository().getOwnerStats(venueId);
        if (!mounted) return;
        setState(() {
          _venue = stats.venue;
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
      MaterialPageRoute(
        builder: (_) => VenueEditPage(venue: venue),
      ),
    );
    if (updated != null && mounted) {
      setState(() => _venue = updated);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AccountSettingsPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
            child:
                CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    final venue = _venue;
    final photoUrl = venue?.photo;
    final venueName =
        venue?.name ?? widget.activeVenueName ?? 'Venue account';
    final description = venue?.description;
    final address = venue?.address;
    final city = venue?.city;

    return Scaffold(
      body: Stack(
        children: [
          // Background
          Positioned.fill(
            child: photoUrl != null && photoUrl.isNotEmpty
                ? Image.network(
                    photoUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => _buildFallbackBg(theme),
                  )
                : _buildFallbackBg(theme),
          ),

          // Gradient overlay — full coverage so content is always legible
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.88),
                    Colors.black.withValues(alpha: 0.55),
                    Colors.black.withValues(alpha: 0.30),
                  ],
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top actions
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 48),
                      Row(
                        children: [
                          if (venue != null)
                            IconButton(
                              onPressed: _openEdit,
                              icon: const Icon(Icons.edit_outlined,
                                  color: Colors.white),
                              tooltip: 'Edit venue',
                            ),
                          IconButton(
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_outlined,
                                color: Colors.white),
                            tooltip: 'Settings',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Venue info
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 22, vertical: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venueName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (description != null && description.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          description,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            height: 1.5,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (address != null && address.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                color: Colors.white54, size: 14),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                [address, city]
                                    .where((s) => s != null && s.isNotEmpty)
                                    .join(', '),
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 20),
                      OutlinedButton.icon(
                        onPressed: venue != null ? _openEdit : null,
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        label: const Text('Edit venue profile'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color.fromARGB(255, 12, 0, 0),
                          disabledForegroundColor:
                              Colors.white.withValues(alpha: 0.40),
                          side: const BorderSide(color: Colors.white60, width: 1.2),
                          disabledMouseCursor: SystemMouseCursors.forbidden,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackBg(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.6),
            theme.colorScheme.primary.withValues(alpha: 0.2),
          ],
        ),
      ),
    );
  }
}
