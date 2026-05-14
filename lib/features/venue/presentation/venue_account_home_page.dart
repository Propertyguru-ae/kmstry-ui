import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';

class VenueAccountHomePage extends StatefulWidget {
  final String? venueId;

  const VenueAccountHomePage({super.key, this.venueId});

  @override
  State<VenueAccountHomePage> createState() => _VenueAccountHomePageState();
}

class _VenueAccountHomePageState extends State<VenueAccountHomePage> {
  final _repo = VenueOwnerRepository();
  final _authRepo = AuthRepository();

  bool _loading = true;
  String? _error;
  VenueOwnerStatsResponse? _data;

  bool _bannerLoading = false;
  bool _showPersonalBanner = false;

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
        final me = await _authRepo.getMe();
        final ctx = MeContextModel.fromMe(me);
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) &&
            ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
        if (!mounted) return;
        setState(() => _showPersonalBanner = !ctx.hasPersonalProfile);
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
        _data = stats;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load venue stats. Tap to retry.';
      });
    }
  }

  Future<void> _startPersonalOnboarding() async {
    if (_bannerLoading) return;
    setState(() => _bannerLoading = true);
    try {
      await _authRepo.switchContext(lastActiveContext: 'PERSONAL');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UsernameOnboardingPage()),
      );
    } catch (_) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not start personal onboarding.',
      );
    } finally {
      if (mounted) setState(() => _bannerLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError(colors)
                : _buildDashboard(colors, isDark),
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
              _error ?? 'Error',
              style:
                  TextStyle(color: colors.onSurface.withValues(alpha: 0.6)),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboard(ColorScheme colors, bool isDark) {
    final d = _data!;
    final v = d.venue;
    final s = d.stats;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        children: [
          // Personal account banner
          if (_showPersonalBanner) ...[
            _buildPersonalBanner(colors),
            const SizedBox(height: 16),
          ],

          // Venue header
          _buildVenueHeader(v, colors, isDark),
          const SizedBox(height: 20),

          // Stats row
          _buildStatCards(s, colors, isDark),
          const SizedBox(height: 20),

          // Weekly trend
          _buildWeeklyTrend(s, colors, isDark),
          const SizedBox(height: 20),

          // Active guests
          if (d.activeGuests.isNotEmpty) ...[
            _buildActiveGuestsSection(d.activeGuests, colors),
          ],
        ],
      ),
    );
  }

  Widget _buildPersonalBanner(ColorScheme colors) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      color: colors.surface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Want to use Kmstry as a person too?',
                style: TextStyle(
                    color: colors.onSurface, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _bannerLoading ? null : _startPersonalOnboarding,
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVenueHeader(
      VenueOwnerStatsVenue v, ColorScheme colors, bool isDark) {
    return Row(
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: colors.primary.withValues(alpha: 0.10),
          ),
          clipBehavior: Clip.antiAlias,
          child: v.photo != null && v.photo!.isNotEmpty
              ? Image.network(v.photo!, fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Icon(
                        Icons.store_mall_directory_outlined,
                        color: colors.primary,
                        size: 28,
                      ))
              : Icon(Icons.store_mall_directory_outlined,
                  color: colors.primary, size: 28),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                v.name,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800),
              ),
              if (v.address != null && v.address!.isNotEmpty)
                Text(
                  v.address!,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCards(VenueOwnerStats s, ColorScheme colors, bool isDark) {
    final cards = [
      _StatCard(label: 'Here now', value: '${s.activeNow}',
          icon: Icons.people_alt_outlined),
      _StatCard(label: 'Today', value: '${s.todayTotal}',
          icon: Icons.today_outlined),
      _StatCard(label: 'All time', value: '${s.totalAllTime}',
          icon: Icons.bar_chart_outlined),
    ];

    return Row(
      children: cards.map((card) {
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? colors.surface
                    : colors.primary.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: colors.outline.withValues(alpha: 0.18)),
              ),
              child: Column(
                children: [
                  Icon(card.icon, color: colors.primary, size: 22),
                  const SizedBox(height: 6),
                  Text(
                    card.value,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    card.label,
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildWeeklyTrend(
      VenueOwnerStats s, ColorScheme colors, bool isDark) {
    final trend = s.weeklyTrend;
    if (trend.isEmpty) return const SizedBox.shrink();

    final maxCount = trend.map((p) => p.count).fold(0, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colors.surface
            : colors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 days',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 72,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.map((point) {
                final height =
                    maxCount == 0 ? 4.0 : (point.count / maxCount) * 60 + 4;
                final dayLabel = _shortDayLabel(point.date);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: point.count > 0
                                ? colors.primary
                                : colors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dayLabel,
                          style: TextStyle(
                            fontSize: 10,
                            color: colors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  String _shortDayLabel(String isoDate) {
    try {
      final parts = isoDate.split('-');
      if (parts.length < 3) return '';
      final d = DateTime(
          int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[(d.weekday - 1) % 7];
    } catch (_) {
      return '';
    }
  }

  Widget _buildActiveGuestsSection(
      List<VenueActiveGuest> guests, ColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Here right now',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${guests.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...guests.map((guest) => _buildGuestTile(guest, colors)),
      ],
    );
  }

  Widget _buildGuestTile(VenueActiveGuest guest, ColorScheme colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: colors.primary.withValues(alpha: 0.12),
            backgroundImage:
                guest.photo != null && guest.photo!.isNotEmpty
                    ? NetworkImage(guest.photo!)
                    : null,
            child: guest.photo == null || guest.photo!.isEmpty
                ? Icon(Icons.person_outline,
                    color: colors.primary, size: 20)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              guest.displayName,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w500),
            ),
          ),
          if (guest.gender != null)
            Icon(
              guest.gender == 'male' ? Icons.male : Icons.female,
              size: 16,
              color: colors.onSurface.withValues(alpha: 0.4),
            ),
        ],
      ),
    );
  }
}

class _StatCard {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard(
      {required this.label, required this.value, required this.icon});
}
