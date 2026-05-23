import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';

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
  MeContextModel? _meContext;

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
      final me = await _authRepo.getMe();
      final ctx = MeContextModel.fromMe(me);

      String? venueId = widget.venueId;
      if (venueId == null || venueId.isEmpty) {
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) &&
            ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
      }
      if (!mounted) return;
      setState(() {
        _meContext = ctx;
        _showPersonalBanner = !ctx.hasPersonalProfile;
      });

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

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colors.surfaceContainerLow,
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: colors.primary))
          : _error != null
              ? SafeArea(child: _buildError(colors))
              : _buildDashboard(colors),
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

  Widget _buildDashboard(ColorScheme colors) {
    final d = _data!;
    final v = d.venue;
    final s = d.stats;

    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        slivers: [
          // ── Hero ────────────────────────────────────────────────────────
          SliverAppBar(
            automaticallyImplyLeading: false,
            expandedHeight: 220,
            pinned: true,
            elevation: 0,
            backgroundColor: colors.primary,
            flexibleSpace: FlexibleSpaceBar(
              collapseMode: CollapseMode.pin,
              background: _buildHero(v, s),
            ),
          ),

          // ── Personal banner (if no personal profile) ────────────────────
          if (_showPersonalBanner)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _buildPersonalBanner(colors),
              ),
            ),

          // ── Secondary stats (Today / All Time) ─────────────────────────
          SliverToBoxAdapter(child: _buildSecondaryStats(s, colors)),

          const SliverToBoxAdapter(child: SizedBox(height: 2)),

          // ── Weekly trend ────────────────────────────────────────────────
          SliverToBoxAdapter(child: _buildWeeklyTrend(s, colors)),

          const SliverToBoxAdapter(child: SizedBox(height: 2)),

          // ── Quick actions ───────────────────────────────────────────────
          SliverToBoxAdapter(
              child: _buildQuickActions(d.venue.id, colors)),

          // ── Guest chips ─────────────────────────────────────────────────
          if (d.activeGuests.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SizedBox(height: 2)),
            SliverToBoxAdapter(
                child: _buildGuestChips(d.activeGuests, colors)),
          ],

          // ── Bottom padding ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: SizedBox(
              height: 32 +
                  MediaQuery.of(context).padding.bottom +
                  kBottomNavigationBarHeight,
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero ─────────────────────────────────────────────────────────────────────

  Widget _buildHero(VenueOwnerStatsVenue v, VenueOwnerStats s) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Background: venue photo or gradient
        if (v.photo != null && v.photo!.isNotEmpty)
          Image.network(
            v.photo!,
            fit: BoxFit.cover,
            errorBuilder: (ctx, e, st) => _HeroGradient(venue: v),
          )
        else
          _HeroGradient(venue: v),

        // Dark overlay for legibility
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0x55000000),
                Color(0xCC000000),
              ],
            ),
          ),
        ),

        // Content
        Positioned(
          left: 20,
          right: 20,
          bottom: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Venue name
              Text(
                v.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                ),
              ),
              if (v.address != null && v.address!.isNotEmpty) ...[
                const SizedBox(height: 3),
                Row(
                  children: [
                    const Icon(Icons.location_on_outlined,
                        size: 12, color: Colors.white54),
                    const SizedBox(width: 3),
                    Flexible(
                      child: Text(
                        v.address!,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),

              // Live badge + big number
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Live badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _LiveDot(),
                        SizedBox(width: 5),
                        Text(
                          'LIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Spacer(),

                  // Big count
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${s.activeNow}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 54,
                          fontWeight: FontWeight.w900,
                          height: 0.9,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'here right now',
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Secondary stats ───────────────────────────────────────────────────────────

  Widget _buildSecondaryStats(VenueOwnerStats s, ColorScheme colors) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: IntrinsicHeight(
        child: Row(
          children: [
            _SecondaryStatCell(
              label: 'Today',
              value: '${s.todayTotal}',
              colors: colors,
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colors.outline.withValues(alpha: 0.15),
            ),
            _SecondaryStatCell(
              label: 'All Time',
              value: _formatCount(s.totalAllTime),
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }

  static String _formatCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }

  // ── Weekly trend ──────────────────────────────────────────────────────────────

  Widget _buildWeeklyTrend(VenueOwnerStats s, ColorScheme colors) {
    final trend = s.weeklyTrend;
    if (trend.isEmpty) return const SizedBox.shrink();

    final maxCount =
        trend.map((p) => p.count).fold(0, (a, b) => a > b ? a : b);
    final totalWeek = trend.fold(0, (sum, p) => sum + p.count);
    final todayIndex = trend.length - 1;

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'This Week',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurface,
                ),
              ),
              Text(
                '$totalWeek check-ins',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 88,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.asMap().entries.map((entry) {
                final i = entry.key;
                final point = entry.value;
                final isToday = i == todayIndex;
                final barH = maxCount == 0
                    ? 4.0
                    : (point.count / maxCount) * 56 + 4;
                final label = _shortDayLabel(point.date);

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Count label above today's bar
                        SizedBox(
                          height: 18,
                          child: isToday && point.count > 0
                              ? Text(
                                  '${point.count}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: colors.primary,
                                  ),
                                )
                              : null,
                        ),
                        // Bar
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: isToday
                                ? colors.primary
                                : (point.count > 0
                                    ? colors.primaryContainer
                                    : colors.primaryContainer
                                        .withValues(alpha: 0.35)),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Day label
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isToday
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isToday
                                ? colors.primary
                                : colors.onSurface
                                    .withValues(alpha: 0.4),
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

  // ── Quick actions ─────────────────────────────────────────────────────────────

  Widget _buildQuickActions(String venueId, ColorScheme colors) {
    final memberVenue =
        _meContext?.memberVenues.where((v) => v.id == venueId).firstOrNull;
    final callerRole =
        VenueMemberRoleExt.fromApi(memberVenue?.role ?? 'STAFF');

    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          Row(
            children: [
              _ActionCard(
                icon: Icons.group_outlined,
                label: 'Team',
                subtitle: 'Members & roles',
                colors: colors,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VenueTeamPage(
                      venueId: venueId,
                      callerRole: callerRole,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _ActionCard(
                icon: Icons.campaign_outlined,
                label: 'Notify Nearby',
                subtitle: 'Push to users within 2km',
                colors: colors,
                comingSoon: true,
                onTap: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Guest chips ───────────────────────────────────────────────────────────────

  Widget _buildGuestChips(
      List<VenueActiveGuest> guests, ColorScheme colors) {
    return Container(
      color: colors.surface,
      padding: const EdgeInsets.fromLTRB(20, 16, 0, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Row(
              children: [
                Text(
                  'Here right now',
                  style: TextStyle(
                    fontSize: 15,
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
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 82,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(right: 20),
              itemCount: guests.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, i) {
                final guest = guests[i];
                return _GuestChip(guest: guest, colors: colors);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Personal banner ───────────────────────────────────────────────────────────

  Widget _buildPersonalBanner(ColorScheme colors) {
    return Material(
      elevation: 1,
      borderRadius: BorderRadius.circular(14),
      color: colors.surface,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: colors.primary.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Want to use Kmstry as a person too?',
                style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(80, 44),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed:
                  _bannerLoading ? null : _startPersonalOnboarding,
              child: const Text('Start'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Notify nearby bottom sheet ────────────────────────────────────────────────

  Future<void> _showNotifyBottomSheet() async {
    final venueId = _data?.venue.id;
    if (venueId == null) return;

    final titleCtrl = TextEditingController();
    final msgCtrl = TextEditingController();
    bool sending = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(ctx).scaffoldBackgroundColor,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                padding:
                    const EdgeInsets.fromLTRB(20, 16, 20, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Notify Nearby Users',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Send a push notification to users within 2km of your venue.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: titleCtrl,
                      decoration: InputDecoration(
                        labelText: 'Title',
                        hintText: "e.g. We're packed tonight!",
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 60,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: msgCtrl,
                      decoration: InputDecoration(
                        labelText: 'Message',
                        hintText:
                            'Come join us, doors open till 2am!',
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLength: 120,
                      maxLines: 3,
                      minLines: 2,
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: sending
                            ? null
                            : () async {
                                final t = titleCtrl.text.trim();
                                final m = msgCtrl.text.trim();
                                if (t.isEmpty || m.isEmpty) return;
                                setModalState(() => sending = true);
                                try {
                                  final result =
                                      await _repo.notifyNearby(
                                          venueId!, t, m);
                                  if (!ctx.mounted) return;
                                  Navigator.pop(ctx);
                                  final rateLimited =
                                      result['rateLimited'] == true;
                                  final sent =
                                      result['sent'] as int? ?? 0;
                                  if (!mounted) return;
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        rateLimited
                                            ? 'Rate limit reached — try again tomorrow.'
                                            : 'Notification sent to $sent nearby user${sent == 1 ? '' : 's'}!',
                                      ),
                                      behavior:
                                          SnackBarBehavior.floating,
                                    ),
                                  );
                                } catch (e) {
                                  setModalState(
                                      () => sending = false);
                                  if (!ctx.mounted) return;
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    SnackBar(
                                      content: Text('Error: $e'),
                                      behavior:
                                          SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              },
                        style: FilledButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(14)),
                        ),
                        child: sending
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : const Text('Send Notification',
                                style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    msgCtrl.dispose();
  }
}

// ─── Hero gradient background ─────────────────────────────────────────────────

class _HeroGradient extends StatelessWidget {
  final VenueOwnerStatsVenue venue;
  const _HeroGradient({required this.venue});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary,
            colors.secondary,
          ],
        ),
      ),
    );
  }
}

// ─── Pulsing live dot ─────────────────────────────────────────────────────────

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          color: const Color(0xFF4CAF50).withValues(alpha: _anim.value),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

// ─── Secondary stat cell ──────────────────────────────────────────────────────

class _SecondaryStatCell extends StatelessWidget {
  final String label;
  final String value;
  final ColorScheme colors;

  const _SecondaryStatCell({
    required this.label,
    required this.value,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: colors.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colors.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Quick action card ────────────────────────────────────────────────────────

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final ColorScheme colors;
  final VoidCallback onTap;
  final bool comingSoon;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.colors,
    required this.onTap,
    this.comingSoon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Opacity(
          opacity: comingSoon ? 0.55 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.outline.withValues(alpha: 0.12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: colors.primary, size: 22),
                    if (comingSoon) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.outline.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'Soon',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface.withValues(alpha: 0.5),
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Guest chip ───────────────────────────────────────────────────────────────

class _GuestChip extends StatelessWidget {
  final VenueActiveGuest guest;
  final ColorScheme colors;

  const _GuestChip({required this.guest, required this.colors});

  @override
  Widget build(BuildContext context) {
    final firstName = guest.displayName.split(' ').first;
    final imageUrl = (guest.featuredPhoto?.isNotEmpty == true)
        ? guest.featuredPhoto!
        : (guest.photo?.isNotEmpty == true ? guest.photo! : null);

    return SizedBox(
      width: 56,
      child: Column(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor:
                    colors.primary.withValues(alpha: 0.12),
                backgroundImage:
                    imageUrl != null ? NetworkImage(imageUrl) : null,
                child: imageUrl == null
                    ? Icon(Icons.person_outline,
                        color: colors.primary, size: 22)
                    : null,
              ),
              if (guest.gender != null)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: colors.outline.withValues(alpha: 0.15)),
                    ),
                    child: Icon(
                      guest.gender == 'male'
                          ? Icons.male
                          : Icons.female,
                      size: 11,
                      color: colors.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            firstName,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: colors.onSurface.withValues(alpha: 0.65),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
