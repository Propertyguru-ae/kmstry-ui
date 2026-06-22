import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';

/// Venue owner: live guest list tab.
/// Shows all currently active check-ins with name, photo, gender, and
/// a simple M/F count header.
class VenueOwnerGuestsPage extends StatefulWidget {
  final String? venueId;
  final bool isPendingClaim;

  const VenueOwnerGuestsPage({super.key, this.venueId, this.isPendingClaim = false});

  @override
  State<VenueOwnerGuestsPage> createState() => _VenueOwnerGuestsPageState();
}

class _VenueOwnerGuestsPageState extends State<VenueOwnerGuestsPage> {
  final _repo = VenueOwnerRepository();

  bool _loading = true;
  String? _error;
  List<VenueActiveGuest> _guests = [];
  int _maleCount = 0;
  int _femaleCount = 0;
  int _todayTotal = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
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
      if (venueId == null || venueId.isEmpty) {
        setState(() {
          _loading = false;
          _error = 'No active venue found.';
        });
        return;
      }
      final stats = await _repo.getOwnerStats(venueId);
      if (!mounted) return;
      setState(() {
        _guests = stats.activeGuests;
        _maleCount = stats.stats.maleNow;
        _femaleCount = stats.stats.femaleNow;
        _todayTotal = stats.stats.todayTotal;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load guests. Tap to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? theme.scaffoldBackgroundColor : Colors.white,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        leading: const AppLogo(),
        title: Text(
          'Guests',
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
      body: widget.isPendingClaim
          ? _buildPendingPlaceholder(colors)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? _buildError(colors)
                  : _buildContent(colors, isDark),
    );
  }

  Widget _buildPendingPlaceholder(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.people_outline,
                  size: 34, color: AppColors.blueDark),
            ),
            const SizedBox(height: 20),
            const Text(
              'Guest Management',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFFC8D8F0)),
            ),
            const SizedBox(height: 10),
            const Text(
              'Once your claim is approved, you\'ll be able to see and manage guests checking in to your venue in real time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: Color(0xFF5B6F8D), height: 1.55),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.blue.withValues(alpha: 0.08),
                border: Border.all(color: AppColors.blue.withValues(alpha: 0.20)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 15, color: AppColors.blueDark),
                  SizedBox(width: 8),
                  Text('Awaiting claim approval',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppColors.blueDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 48, color: colors.onSurface.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colors, bool isDark) {
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Summary chips
                  Row(
                    children: [
                      _buildChip(
                        label: '${_guests.length} here now',
                        icon: Icons.people_alt_outlined,
                        colors: colors,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildChip(
                        label: '$_maleCount M  ·  $_femaleCount F',
                        icon: Icons.wc_outlined,
                        colors: colors,
                        isDark: isDark,
                      ),
                      const SizedBox(width: 8),
                      _buildChip(
                        label: '$_todayTotal today',
                        icon: Icons.today_outlined,
                        colors: colors,
                        isDark: isDark,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          if (_guests.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_outline,
                        size: 64,
                        color: colors.onSurface.withValues(alpha: 0.25)),
                    const SizedBox(height: 12),
                    Text(
                      'No guests checked in right now.',
                      style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.5)),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final guest = _guests[i];
                  return _buildGuestTile(guest, colors);
                },
                childCount: _guests.length,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChip({
    required String label,
    required IconData icon,
    required ColorScheme colors,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surface
            : colors.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: colors.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGuestTile(VenueActiveGuest guest, ColorScheme colors) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: CircleAvatar(
        radius: 22,
        backgroundColor: colors.primary.withValues(alpha: 0.12),
        backgroundImage:
            guest.photo != null && guest.photo!.isNotEmpty
                ? NetworkImage(guest.photo!)
                : null,
        child: guest.photo == null || guest.photo!.isEmpty
            ? Icon(Icons.person_outline, color: colors.primary, size: 22)
            : null,
      ),
      title: Text(
        guest.displayName,
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: guest.username != null
          ? Text('@${guest.username}',
              style: TextStyle(
                  fontSize: 12,
                  color: colors.onSurface.withValues(alpha: 0.5)))
          : null,
      trailing: guest.gender != null
          ? Icon(
              guest.gender == 'male' ? Icons.male : Icons.female,
              size: 18,
              color: colors.onSurface.withValues(alpha: 0.4),
            )
          : null,
    );
  }
}
