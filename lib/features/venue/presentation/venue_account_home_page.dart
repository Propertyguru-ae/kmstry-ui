import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_screen.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_claim_rejected_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_upload_docs_page.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_bell.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';

/// DEMO bayrağı — "Here right now" boşken tasarımı göstermek için sahte misafir
/// enjekte eder (patrona demo). Canlıya çıkmadan ÖNCE false yap.
const bool _kDemoHereNow = true;

class VenueAccountHomePage extends StatefulWidget {
  final String? venueId;
  const VenueAccountHomePage({super.key, this.venueId});

  @override
  State<VenueAccountHomePage> createState() => _VenueAccountHomePageState();
}

class _VenueAccountHomePageState extends State<VenueAccountHomePage> {
  final _repo     = VenueOwnerRepository();
  final _authRepo = AuthRepository();

  bool _loading  = true;
  String? _error;
  VenueOwnerStatsResponse? _data;

  bool _bannerLoading       = false;
  bool _showPersonalBanner  = false;
  bool _isPendingClaim      = false;
  bool _isRejectedClaim     = false;
  bool _pendingHasDocuments = false;
  MemberVenue? _pendingVenue;
  MemberVenue? _rejectedVenue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final me  = await _authRepo.getMe();
      final ctx = MeContextModel.fromMe(me);

      String? venueId = widget.venueId;
      if (venueId == null || venueId.isEmpty) {
        venueId = ctx.activeVenueId;
        if ((venueId == null || venueId.isEmpty) && ctx.memberVenues.isNotEmpty) {
          venueId = ctx.memberVenues.first.id;
        }
      }
      if (!mounted) return;

      final pendingVenue   = ctx.memberVenues.where((v) => v.isPendingOwnerClaim).firstOrNull;
      final rejectedVenue  = ctx.memberVenues.where((v) => v.isRejectedOwnerClaim).firstOrNull;
      final isPending      = ctx.nextAction == 'AWAIT_VENUE_APPROVAL' || pendingVenue != null;
      final isRejected     = ctx.nextAction == 'VENUE_CLAIM_REJECTED' || ctx.hasRejectedClaimOnly || rejectedVenue != null;

      setState(() {
        _showPersonalBanner  = !ctx.hasPersonalProfile && !isRejected;
        _isPendingClaim      = isPending;
        _isRejectedClaim     = isRejected && !isPending;
        _pendingHasDocuments = pendingVenue?.hasDocuments ?? false;
        _pendingVenue        = pendingVenue;
        _rejectedVenue       = rejectedVenue;
      });

      if (isPending || isRejected) { setState(() => _loading = false); return; }

      if (venueId == null || venueId.isEmpty) {
        setState(() { _loading = false; _error = 'No active venue found.'; });
        return;
      }
      final stats = await _repo.getOwnerStats(venueId);
      if (!mounted) return;
      setState(() { _data = stats; _loading = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Could not load venue stats. Tap to retry.'; });
    }
  }

  Future<void> _startPersonalOnboarding() async {
    if (_bannerLoading) return;
    setState(() => _bannerLoading = true);
    try {
      await _authRepo.switchContext(lastActiveContext: 'PERSONAL');
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => UsernameOnboardingPage(onCancel: _cancelPersonalOnboarding),
      ));
    } catch (_) {
      if (!mounted) return;
      await showPremiumErrorDialog(context, message: 'Could not start personal onboarding.');
    } finally {
      if (mounted) setState(() => _bannerLoading = false);
    }
  }

  Future<void> _cancelPersonalOnboarding() async {
    try { await _authRepo.switchContext(lastActiveContext: 'VENUE'); } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final kBg    = isDark ? const Color(0xFF06091A) : Colors.white;
    final kBorder = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFD9E1EA);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const AppLogo(),
        title: Text(
          'Dashboard',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.onSurface),
        ),
        actions: const [
          NotificationBell(),
          SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: colors.primary))
          : _error != null
              ? _buildError(context)
              : _isPendingClaim
                  ? _buildPendingView(context)
                  : _isRejectedClaim
                      ? _buildRejectedView(context)
                      : _buildDashboard(context),
    );
  }

  // ── Error ─────────────────────────────────────────────────────────────────────

  Widget _buildError(BuildContext context) {
    final kDim = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: kDim),
            const SizedBox(height: 16),
            Text(_error ?? 'Error', style: TextStyle(color: kDim), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }

  // ── Normal dashboard ──────────────────────────────────────────────────────────

  Widget _buildDashboard(BuildContext context) {
    final d      = _data!;
    final s      = d.stats;
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      backgroundColor: kSheet,
      child: ListView(
        children: [
          // 1) Live pulse — "right now"
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _LivePulseCard(
              activeNow: s.activeNow,
              maleNow: s.maleNow,
              femaleNow: s.femaleNow,
            ),
          ),

          // 2) Today snapshot — delta'lı 3 mini KPI
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _TodaySnapshotRow(
              todayTotal: s.todayTotal,
              deltaPct: s.todayVsYesterdayPct,
              storyViews: s.storyViewsToday,
              followers: s.followerCount,
              // Story views yalnızca Stories özelliği olan planlarda anlamlı.
              showStoryViews: VenueSession.instance.hasFeature(VenueFeature.stories),
            ),
          ),

          // 3) Today's events — yalnızca Events özelliği olan planlarda göster.
          if (VenueSession.instance.hasFeature(VenueFeature.events)) ...[
            const SizedBox(height: 12),
            _buildTodaysEvents(context, d.venue),
          ],

          if (_showPersonalBanner) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildPersonalBanner(context),
            ),
          ],

          // 4) Live guests + stories (kimse yoksa bile göster)
          const SizedBox(height: 12),
          _buildGuestChips(context, d.activeGuests, s.anonymousNow),

          // 4) Mini haftalık trend → tam analytics'e giriş.
          // Advanced analytics (Live+) yoksa "See full analytics" gösterme,
          // kartı da tıklanamaz yap (geç 'failed to load' hatasını önler).
          const SizedBox(height: 12),
          if (VenueSession.instance.hasFeature(VenueFeature.advancedAnalytics) &&
              (VenueSession.instance.isOwner ||
                  VenueSession.instance.can(VenuePermission.viewAnalytics)))
            InkWell(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VenueAnalyticsScreen(
                  venueId: d.venue.id,
                  venueName: d.venue.name,
                ),
              )),
              child: Container(
                color: kSheet,
                child: Column(
                  children: [
                    _buildWeeklyTrend(context, s),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text('See full analytics',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.primary)),
                          Icon(Icons.chevron_right, size: 16, color: colors.primary),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            Container(
              color: kSheet,
              padding: const EdgeInsets.only(bottom: 14),
              child: _buildWeeklyTrend(context, s),
            ),

          SizedBox(
            height: 32 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight,
          ),
        ],
      ),
    );
  }

  // ── Pending view ──────────────────────────────────────────────────────────────

  Widget _buildPendingView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      backgroundColor: kSheet,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _buildClaimBanner(context),
            ),
            IgnorePointer(
              child: Opacity(
                opacity: 0.30,
                child: Column(
                  children: [
                    const SizedBox(height: 2),
                    _buildStatStripPlaceholder(context),
                    const SizedBox(height: 2),
                    _buildWeeklyTrendPlaceholder(context),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 32 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight,
            ),
          ],
        ),
      ),
    );
  }

  // ── Rejected view ─────────────────────────────────────────────────────────────

  Widget _buildRejectedView(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);

    return RefreshIndicator(
      onRefresh: _load,
      color: colors.primary,
      backgroundColor: kSheet,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: _buildRejectedBanner(context),
            ),
            IgnorePointer(
              child: Opacity(
                opacity: 0.25,
                child: Column(
                  children: [
                    const SizedBox(height: 2),
                    _buildStatStripPlaceholder(context),
                    const SizedBox(height: 2),
                    _buildWeeklyTrendPlaceholder(context),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 32 + MediaQuery.of(context).padding.bottom + kBottomNavigationBarHeight,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRejectedBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => VenueClaimRejectedPage(
            venueId: _rejectedVenue?.id ?? '',
            venueName: _rejectedVenue?.name ?? 'Venue',
          ),
        ));
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.error.withValues(alpha: 0.07),
          border: Border.all(color: colors.error.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.store_outlined, size: 18, color: colors.error),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Claim Not Approved',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                          color: colors.error)),
                  const SizedBox(height: 4),
                  Text(
                    'Your venue ownership claim was not approved. Tap for details and support options.',
                    style: TextStyle(fontSize: 11, color: kDim, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: colors.error.withValues(alpha: 0.60), size: 20),
          ],
        ),
      ),
    );
  }

  // ── Claim banner ──────────────────────────────────────────────────────────────

  Widget _buildClaimBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    if (!_pendingHasDocuments) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft, end: Alignment.bottomRight,
            colors: [
              const Color(0xFF00BFB3).withValues(alpha: 0.12),
              const Color(0xFF00D4C8).withValues(alpha: 0.07),
            ],
          ),
          border: Border.all(color: const Color(0xFF00BFB3).withValues(alpha: 0.28)),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFF00BFB3).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.file_copy_outlined, size: 19, color: Color(0xFF00D4C8)),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Documents Required',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                              color: Color(0xFF00D4C8))),
                      SizedBox(height: 2),
                      Text('Upload your documents to complete verification and unlock your account.',
                          style: TextStyle(fontSize: 11, color: Color(0xFF4A9090), height: 1.45)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Builder(builder: (_) {
              final uploaded = _pendingHasDocuments ? 2 : 0;
              final progress = uploaded / 2.0;
              return Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 4,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.06)
                            : const Color(0xFFD9E1EA),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFF00BFB3)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('$uploaded of 2 uploaded',
                      style: const TextStyle(fontSize: 10, color: Color(0xFF4A9090),
                          fontWeight: FontWeight.w600)),
                ],
              );
            }),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => VenueUploadDocsPage(
                    venueName: _pendingVenue?.name ?? 'Your Venue',
                  ),
                )).then((_) { if (mounted) _load(); });
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF00A89E),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_outlined, size: 14, color: Colors.white),
                    SizedBox(width: 7),
                    Text('Upload Documents',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border.all(color: colors.primary.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.hourglass_top_rounded, size: 18, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Claim Under Review',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                        color: colors.primary)),
                const SizedBox(height: 4),
                Text(
                  'Our team is reviewing your ownership claim. You\'ll be notified once approved.',
                  style: TextStyle(fontSize: 11, color: kDim, height: 1.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Stat strip ────────────────────────────────────────────────────────────────

  Widget _buildStatStripPlaceholder(BuildContext context) {
    return _StatStrip(children: [
      _StatCell(label: 'Today',     value: '0'),
      _StatDivider(),
      _StatCell(label: 'This Week', value: '0'),
      _StatDivider(),
      _StatCell(label: 'Followers', value: '0'),
    ]);
  }

  // ── Weekly trend ──────────────────────────────────────────────────────────────

  Widget _buildWeeklyTrend(BuildContext context, VenueOwnerStats s) {
    final trend = s.weeklyTrend;
    if (trend.isEmpty) return const SizedBox.shrink();
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final colors     = Theme.of(context).colorScheme;
    final kSheet     = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    final kText      = colors.onSurface;
    final kDim       = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final maxCount   = trend.map((p) => p.count).fold(0, (a, b) => a > b ? a : b);
    final totalWeek  = trend.fold(0, (sum, p) => sum + p.count);
    final todayIdx   = trend.length - 1;

    return Container(
      color: kSheet,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('This Week',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              Text('$totalWeek check-ins',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.primary)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: trend.asMap().entries.map((entry) {
                final i       = entry.key;
                final point   = entry.value;
                final isToday = i == todayIdx;
                final barH    = maxCount == 0 ? 4.0 : (point.count / maxCount) * 56 + 4;
                final label   = _shortDayLabel(point.date);
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 16,
                          child: isToday && point.count > 0
                              ? Text('${point.count}',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700,
                                      color: colors.primary))
                              : null,
                        ),
                        Container(
                          height: barH,
                          decoration: BoxDecoration(
                            color: isToday
                                ? colors.primary
                                : colors.primary.withValues(alpha: point.count > 0 ? 0.30 : 0.12),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(label,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: isToday ? FontWeight.w700 : FontWeight.w600,
                              color: isToday ? colors.primary : kDim,
                            )),
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

  Widget _buildWeeklyTrendPlaceholder(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final colors  = Theme.of(context).colorScheme;
    final kSheet  = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    final kText   = colors.onSurface;
    final kDim    = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    return Container(
      color: kSheet,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('This Week',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              Text('0 check-ins',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: colors.primary)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 64,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(7, (i) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: i == 6 ? 0.5 : 0.2),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(['Thu','Fri','Sat','Sun','Mon','Tue','Wed'][i],
                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                              color: i == 6 ? colors.primary : kDim)),
                    ],
                  ),
                ),
              )),
            ),
          ),
        ],
      ),
    );
  }

  // ── Today's events ────────────────────────────────────────────────────────────

  Widget _buildTodaysEvents(BuildContext context, VenueOwnerStatsVenue venue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    final kText  = colors.onSurface;
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    final now      = DateTime.now();
    final dayStart = DateTime(now.year, now.month, now.day);
    final dayEnd   = dayStart.add(const Duration(days: 1));
    // Bugün başlayan veya bugüne taşan (devam eden) event'ler
    final todays = venue.upcomingEvents.where((e) {
      final s = e.startAt.toLocal();
      final en = e.endAt.toLocal();
      return s.isBefore(dayEnd) && en.isAfter(dayStart);
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));

    return Container(
      color: kSheet,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.event_outlined, size: 17, color: kText),
              const SizedBox(width: 8),
              Text("Today's Events",
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
              if (todays.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${todays.length}',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colors.primary)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (todays.isEmpty)
            Row(
              children: [
                Icon(Icons.event_busy_outlined, size: 18, color: kDim.withValues(alpha: 0.7)),
                const SizedBox(width: 8),
                Text('No events today',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kDim)),
              ],
            )
          else
            ...todays.map((e) => Padding(
                  padding: EdgeInsets.only(bottom: e == todays.last ? 0 : 10),
                  child: _TodayEventCard(
                    event: e,
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => VenueEventDetailPage(event: e, venueId: venue.id, onChanged: _load),
                    )),
                  ),
                )),
        ],
      ),
    );
  }

  // ── Guest chips ───────────────────────────────────────────────────────────────

  Widget _buildGuestChips(BuildContext context, List<VenueActiveGuest> guests, int anonymousNow) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    final kText  = colors.onSurface;

    // DEMO: gerçek check-in yokken tasarımı göstermek için. Canlıya çıkmadan
    // _kDemoHereNow = false yap.
    if (_kDemoHereNow && guests.isEmpty && anonymousNow == 0) {
      guests = const [
        VenueActiveGuest(id: 'd1', fullName: 'dnzhtoo', gender: 'MALE', checkinId: 'c1'),
        VenueActiveGuest(id: 'd2', fullName: 'yanhtoo', gender: 'FEMALE', checkinId: 'c2'),
        VenueActiveGuest(id: 'd3', fullName: 'samchehab', gender: 'MALE', checkinId: 'c3'),
        VenueActiveGuest(id: 'd4', fullName: 'rachellem__', gender: 'FEMALE', checkinId: 'c4'),
      ];
      anonymousNow = 2;
    }

    final totalHere = guests.length + anonymousNow;

    return Container(
      color: kSheet,
      padding: const EdgeInsets.fromLTRB(18, 14, 0, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              children: [
                Text('Here right now',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$totalHere',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: colors.primary)),
                ),
                if (anonymousNow > 0) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.visibility_off_outlined, size: 13, color: kText.withValues(alpha: 0.45)),
                  const SizedBox(width: 4),
                  Text('$anonymousNow private',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600,
                          color: kText.withValues(alpha: 0.5))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (guests.isEmpty && anonymousNow == 0)
            Padding(
              padding: const EdgeInsets.only(right: 18, top: 6, bottom: 10),
              child: Row(
                children: [
                  Icon(Icons.people_outline, size: 18, color: kText.withValues(alpha: 0.35)),
                  const SizedBox(width: 8),
                  Text('No one here yet',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: kText.withValues(alpha: 0.5))),
                ],
              ),
            )
          else
            SizedBox(
              height: 88,
              // Görünür misafirler + (varsa) anonimleri temsil eden tek kesikli baloncuk
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(right: 18),
                itemCount: guests.length + (anonymousNow > 0 ? 1 : 0),
                separatorBuilder: (context, index) => const SizedBox(width: 10),
                itemBuilder: (_, i) => i < guests.length
                    ? _GuestChip(guest: guests[i])
                    : _AnonymousChip(count: anonymousNow),
              ),
            ),
        ],
      ),
    );
  }

  // ── Personal banner ───────────────────────────────────────────────────────────

  Widget _buildPersonalBanner(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kDim   = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.08),
        border: Border.all(color: colors.primary.withValues(alpha: 0.20)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.person_add_outlined, size: 17, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Want a personal profile too?',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700,
                        color: colors.onSurface)),
                const SizedBox(height: 2),
                Text('Discover venues as yourself',
                    style: TextStyle(fontSize: 11, color: kDim)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _bannerLoading ? null : _startPersonalOnboarding,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
              decoration: BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: _bannerLoading
                  ? const SizedBox(width: 14, height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Start',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                          color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────────

  String _shortDayLabel(String isoDate) {
    try {
      final parts = isoDate.split('-');
      if (parts.length < 3) return '';
      final d = DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return days[(d.weekday - 1) % 7];
    } catch (_) { return ''; }
  }
}

// ─── Stat strip ───────────────────────────────────────────────────────────────

class _StatStrip extends StatelessWidget {
  final List<Widget> children;
  const _StatStrip({required this.children});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    return Container(
      color: kSheet,
      child: IntrinsicHeight(child: Row(children: children)),
    );
  }
}

// ─── Stat cell & divider ──────────────────────────────────────────────────────

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  const _StatCell({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme      = Theme.of(context);
    final isDark     = theme.brightness == Brightness.dark;
    final kDim       = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final valueColor = theme.colorScheme.onSurface;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: valueColor)),
            const SizedBox(height: 1),
            Text(label,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: kDim)),
          ],
        ),
      ),
    );
  }
}

class _StatDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color  = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFD9E1EA);
    return Container(width: 1, height: double.infinity, color: color);
  }
}

// ─── Guest chip ───────────────────────────────────────────────────────────────

/// Anonymous Mode misafirlerini temsil eden kesikli baloncuk (kimlik yok, sayı var).
class _AnonymousChip extends StatelessWidget {
  final int count;
  const _AnonymousChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final kDim = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4);
    return SizedBox(
      width: 52,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: kDim.withValues(alpha: 0.5), width: 1),
            ),
            child: Icon(Icons.visibility_off_outlined, size: 20, color: kDim),
          ),
          const SizedBox(height: 5),
          Text('+$count',
              style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: kDim)),
        ],
      ),
    );
  }
}

class _GuestChip extends StatefulWidget {
  final VenueActiveGuest guest;
  const _GuestChip({required this.guest});

  @override
  State<_GuestChip> createState() => _GuestChipState();
}

class _GuestChipState extends State<_GuestChip> {
  static const _ringColors = [
    AppColors.magenta,
    AppColors.teal,
    AppColors.blue,
    AppColors.orange,
    AppColors.brand,
  ];

  late Set<String> _viewedIds;

  @override
  void initState() {
    super.initState();
    // Backend'den gelen user-specific viewed state — başka kullanıcıyla karışmaz
    _viewedIds = Set<String>.from(widget.guest.viewedStoryIds);
  }

  bool _isViewed(String id) => _viewedIds.contains(id);

  void _openStories() {
    final stories = widget.guest.stories;
    if (stories.isEmpty) return;

    final startIndex = stories.indexWhere((s) => !_isViewed(s.id));
    final initialIndex = startIndex == -1 ? 0 : startIndex;

    final group = StoryGroup(
      user: StoryUser(
        id: widget.guest.id,
        fullName: widget.guest.displayName,
        photo: widget.guest.photo,
      ),
      stories: stories,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [group],
          initialStoryIndex: initialIndex,
          onClose: (lastIndex, allFinished) {
            if (!mounted) return;
            setState(() {
              if (allFinished) {
                _viewedIds.addAll(stories.map((s) => s.id));
              } else {
                for (int i = 0; i <= lastIndex && i < stories.length; i++) {
                  _viewedIds.add(stories[i].id);
                }
              }
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final isDark    = theme.brightness == Brightness.dark;
    final colors    = theme.colorScheme;
    final kAvatarBg = isDark ? const Color(0xFF1A2A50) : const Color(0xFFF0F4FA);
    final kBorder   = isDark ? const Color(0xFF1E3A6A) : const Color(0xFFD9E1EA);
    final kDim      = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kBadgeBg  = isDark ? const Color(0xFF06091A) : Colors.white;

    final stories   = widget.guest.stories;
    final hasStory  = stories.isNotEmpty;
    final allSeen   = hasStory && stories.every((s) => _isViewed(s.id));
    final firstName = widget.guest.displayName.split(' ').first;
    final imageUrl  = (widget.guest.featuredPhoto?.isNotEmpty == true)
        ? widget.guest.featuredPhoto!
        : (widget.guest.photo?.isNotEmpty == true ? widget.guest.photo! : null);

    const avatarSize = 54.0;
    const ringPad    = 3.0;
    const ringWidth  = 2.2;
    const cornerRadius = 11.0;

    Widget avatar = ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: SizedBox(
        width: avatarSize,
        height: avatarSize,
        child: imageUrl != null
            ? Image.network(imageUrl, fit: BoxFit.cover)
            : ColoredBox(
                color: kAvatarBg,
                child: Center(
                  child: Text(
                    firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.primary),
                  ),
                ),
              ),
      ),
    );

    if (hasStory) {
      avatar = GestureDetector(
        onTap: _openStories,
        child: CustomPaint(
          painter: _SquareStoryRingPainter(
            colors: allSeen ? [Colors.grey.shade400, Colors.grey.shade400] : _ringColors,
            pad: ringPad,
            strokeWidth: ringWidth,
            radius: cornerRadius + ringPad + ringWidth,
          ),
          child: Padding(
            padding: const EdgeInsets.all(ringPad + ringWidth),
            child: avatar,
          ),
        ),
      );
    }

    return SizedBox(
      width: 56,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              if (widget.guest.gender != null)
                Positioned(
                  right: hasStory ? -2 : 0,
                  bottom: hasStory ? -2 : 0,
                  child: Container(
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      color: kBadgeBg,
                      border: Border.all(color: kBorder, width: 1.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.guest.gender == 'male' ? Icons.male : Icons.female,
                      size: 9, color: kDim,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            firstName,
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: kDim),
            maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _SquareStoryRingPainter extends CustomPainter {
  final List<Color> colors;
  final double pad;
  final double strokeWidth;
  final double radius;

  const _SquareStoryRingPainter({
    required this.colors,
    required this.pad,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final shader = SweepGradient(
      colors: [...colors, colors.first],
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SquareStoryRingPainter old) => old.colors != colors;
}

// ── Analytics glance card (dashboard → full analytics) ────────────────────────

// ── Dashboard: Live pulse ("right now") ─────────────────────────────────────────
class _LivePulseCard extends StatelessWidget {
  final int activeNow;
  final int maleNow;
  final int femaleNow;
  const _LivePulseCard({required this.activeNow, required this.maleNow, required this.femaleNow});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    const teal = Color(0xFF1FD9A8);
    final live = activeNow > 0;
    final accent = live ? teal : colors.onSurface.withValues(alpha: 0.4);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: live
              ? [teal.withValues(alpha: isDark ? 0.22 : 0.14), const Color(0xFF1A9FE8).withValues(alpha: isDark ? 0.16 : 0.08)]
              : [colors.onSurface.withValues(alpha: 0.06), colors.onSurface.withValues(alpha: 0.03)],
        ),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Text(live ? 'LIVE NOW' : 'QUIET',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.8, color: accent)),
              ]),
              const SizedBox(height: 6),
              Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                Text('$activeNow', style: TextStyle(fontSize: 40, fontWeight: FontWeight.w800, color: colors.onSurface, height: 1)),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(activeNow == 1 ? 'guest here' : 'guests here',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.6))),
                ),
              ]),
            ],
          ),
          const Spacer(),
          if (live)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _genderRow('♂', maleNow, const Color(0xFF1A9FE8)),
                const SizedBox(height: 8),
                _genderRow('♀', femaleNow, const Color(0xFFE020D8)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _genderRow(String symbol, int count, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(symbol, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(width: 6),
      Text('$count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
    ]);
  }
}

// ── Dashboard: Today snapshot (delta'lı 3 KPI) ──────────────────────────────────
class _TodaySnapshotRow extends StatelessWidget {
  final int todayTotal;
  final int? deltaPct;
  final int storyViews;
  final int followers;
  final bool showStoryViews;
  const _TodaySnapshotRow({
    required this.todayTotal,
    required this.deltaPct,
    required this.storyViews,
    required this.followers,
    this.showStoryViews = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(child: _kpi(context, 'Check-ins today', '$todayTotal', delta: deltaPct)),
      if (showStoryViews) ...[
        const SizedBox(width: 10),
        Expanded(child: _kpi(context, 'Story views', _fmtCount(storyViews))),
      ],
      const SizedBox(width: 10),
      Expanded(child: _kpi(context, 'Followers', _fmtCount(followers))),
    ]);
  }

  Widget _kpi(BuildContext context, String label, String value, {int? delta}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final kSheet = isDark ? const Color(0xFF0B1322) : const Color(0xFFF7F8FA);
    Widget? deltaChip;
    if (delta != null && delta != 0) {
      final up = delta > 0;
      final c = up ? const Color(0xFF1FD9A8) : const Color(0xFFF08838);
      deltaChip = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 11, color: c),
        Text('${delta.abs()}%', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      ]);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(color: kSheet, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Flexible(child: Text(value, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: colors.onSurface))),
            if (deltaChip != null) ...[const SizedBox(width: 4), deltaChip],
          ]),
          const SizedBox(height: 4),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: colors.onSurface.withValues(alpha: 0.55))),
        ],
      ),
    );
  }
}

String _fmtCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
  return '$n';
}

// ── Dashboard: Today's event card (full details) ────────────────────────────────
class _TodayEventCard extends StatelessWidget {
  final VenueUpcomingEvent event;
  final VoidCallback onTap;
  const _TodayEventCard({required this.event, required this.onTap});

  String _time(DateTime d) {
    final l = d.toLocal();
    final h = l.hour.toString().padLeft(2, '0');
    final m = l.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final kText  = colors.onSurface;
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    const teal   = Color(0xFF1FD9A8);
    const orange = Color(0xFFF08838);

    final cover = event.photo ?? (event.photos.isNotEmpty ? event.photos.first : null);

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: cover != null
                        ? Image.network(cover, width: 54, height: 54, fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _placeholder(colors))
                        : _placeholder(colors),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(event.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: kText)),
                            ),
                            if (event.isRecurring) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.repeat, size: 14, color: kDim),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.schedule, size: 13, color: kDim),
                          const SizedBox(width: 4),
                          Text('${_time(event.startAt)} – ${_time(event.endAt)}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kDim)),
                        ]),
                        if (event.description != null && event.description!.trim().isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(event.description!, maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: kDim, height: 1.3)),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _chip(Icons.people_alt_outlined,
                      event.capacity != null ? '${event.rsvpCount}/${event.capacity} RSVP' : '${event.rsvpCount} RSVP',
                      colors.primary),
                  if (event.priceAed != null && event.priceAed! > 0)
                    _chip(Icons.sell_outlined, '${event.priceAed} ${event.currency}', teal),
                  if (event.hasOffer)
                    _chip(Icons.local_offer_outlined, event.offerTypeLabel!, orange),
                  if (event.partnershipCount > 0)
                    _chip(Icons.handshake_outlined,
                        '${event.partnershipCount} partner${event.partnershipCount > 1 ? 's' : ''}',
                        const Color(0xFF1A9FE8)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(ColorScheme colors) => Container(
        width: 54, height: 54,
        color: colors.primary.withValues(alpha: 0.10),
        child: Icon(Icons.event, color: colors.primary.withValues(alpha: 0.7), size: 24),
      );

  Widget _chip(IconData icon, String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
        ]),
      );
}
