import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_screen.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_offers_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_events_list_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';

/// Manage hub — venue yönetim bölümlerinin tek menüsü (mobil "sidebar").
class VenueManagePage extends StatefulWidget {
  final String? venueId;

  const VenueManagePage({super.key, required this.venueId});

  @override
  State<VenueManagePage> createState() => _VenueManagePageState();
}

class _VenueManagePageState extends State<VenueManagePage> {
  final _repo = VenueOwnerRepository();
  VenueOwnerStatsVenue? _venue;

  @override
  void initState() {
    super.initState();
    VenueSession.instance.addListener(_onSession);
    _load();
    _ensureSession();
  }

  @override
  void dispose() {
    VenueSession.instance.removeListener(_onSession);
    super.dispose();
  }

  void _onSession() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final id = widget.venueId;
    if (id == null) return;
    try {
      final stats = await _repo.getOwnerStats(id);
      if (!mounted) return;
      setState(() => _venue = stats.venue);
    } catch (_) {}
  }

  /// Manage'e Profile'a uğramadan gelinirse VenueSession boş olur (default staff),
  /// bu da yetki gate'li satırları gizler. Burada oturumu garanti altına alıyoruz.
  Future<void> _ensureSession() async {
    final session = VenueSession.instance;
    if ((session.loaded && session.venueId != null) || session.loading) return;
    try {
      final me = await AuthRepository().getMe();
      final ctx = MeContextModel.fromMe(me);
      var id = widget.venueId;
      if (id == null || id.isEmpty) {
        id = ctx.activeVenueId;
        if ((id == null || id.isEmpty) && ctx.memberVenues.isNotEmpty) {
          id = ctx.memberVenues.first.id;
        }
      }
      if (id == null || id.isEmpty) return;
      final memberVenue = ctx.memberVenues.where((v) => v.id == id).firstOrNull;
      final role = VenueMemberRoleExt.fromApi(memberVenue?.role ?? 'STAFF');
      await session.load(id, role);
    } catch (_) {}
  }

  bool _can(VenuePermission p) =>
      VenueSession.instance.isOwner || VenueSession.instance.can(p);

  /// Rol izni var ama venue planı bu özelliği açmıyor mu?
  bool _locked(VenueFeature f) => !VenueSession.instance.hasFeature(f);

  /// Plan açıksa [open]'ı çalıştırır, kapalıysa Paywall'a yönlendirir.
  void _openOrPaywall(VenueFeature f, VoidCallback open) {
    if (_locked(f)) {
      PlanGate.openPaywall(context, feature: f);
    } else {
      open();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kBg = isDark ? const Color(0xFF06091A) : Colors.white;
    final kBorder = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFD9E1EA);
    final id = widget.venueId;
    final venueName = _venue?.name ?? '';

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const AppLogo(),
        title: Text(
          'Manage',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colors.onSurface),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: kBorder, height: 1),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            // İzinler yüklenene kadar skeleton göster — gate'li satırların "pat" diye
            // eklenmesini (pop-in) önler.
            if (VenueSession.instance.loadFailed &&
                !VenueSession.instance.loaded) ...[
              _AccessLoadError(onRetry: VenueSession.instance.retry),
            ] else if (!VenueSession.instance.loaded) ...[
              for (var i = 0; i < 5; i++) const _ManageTileSkeleton(),
            ] else ...[

            _PlanCard(
              plan: VenueSession.instance.plan,
            ),
            const SizedBox(height: 4),

            if (_can(VenuePermission.viewAnalytics))
              _ManageTile(
                icon: Icons.insights_outlined,
                color: const Color(0xFF1A9FE8),
                title: 'Analytics',
                subtitle: 'Check-in trends, demographics, reports',
                trailingText: _locked(VenueFeature.advancedAnalytics) ? 'Locked' : null,
                onTap: id == null
                    ? null
                    : () => _openOrPaywall(
                          VenueFeature.advancedAnalytics,
                          () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => VenueAnalyticsScreen(venueId: id, venueName: venueName),
                          )),
                        ),
              ),

            if (_can(VenuePermission.eventManage))
              _ManageTile(
                icon: Icons.event_outlined,
                color: const Color(0xFF1FD9A8),
                title: 'Events',
                subtitle: 'Create & manage events, RSVPs',
                trailingText: _locked(VenueFeature.events) ? 'Locked' : null,
                onTap: id == null
                    ? null
                    : () => _openOrPaywall(
                          VenueFeature.events,
                          () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => VenueEventsListPage(
                              venueId: id,
                              events: _venue?.upcomingEvents ?? const [],
                              onRefresh: _load,
                            ),
                          )),
                        ),
              ),

            if (_can(VenuePermission.partnershipManage))
              _ManageTile(
                icon: Icons.local_offer_outlined,
                color: const Color(0xFFF08838),
                title: 'Offers',
                subtitle: 'Promotions & external partnerships',
                trailingText: _locked(VenueFeature.offers) ? 'Locked' : null,
                onTap: id == null
                    ? null
                    : () => _openOrPaywall(
                          VenueFeature.offers,
                          () => Navigator.push(context, MaterialPageRoute(
                            builder: (_) => VenueOffersPage(venueId: id, venueName: venueName),
                          )),
                        ),
              ),

            if (_can(VenuePermission.memberManage) || _can(VenuePermission.roleManage))
              _ManageTile(
                icon: Icons.groups_outlined,
                color: const Color(0xFF3D1F8C),
                title: 'Team & Roles',
                subtitle: 'Staff, invites, permissions',
                onTap: id == null
                    ? null
                    : () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => VenueTeamPage(
                            venueId: id,
                            callerRole: VenueSession.instance.role,
                          ),
                        )),
              ),

            _ManageTile(
              icon: Icons.settings_outlined,
              color: colors.onSurface.withValues(alpha: 0.7),
              title: 'Settings',
              subtitle: 'Account & activity',
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => const SettingsPage(),
              )),
            ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Manage üstündeki abonelik kartı — mevcut kademe + yükseltme girişi.
class _PlanCard extends StatelessWidget {
  final VenuePlan plan;

  const _PlanCard({required this.plan});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kText = isDark ? Colors.white : const Color(0xFF0B1020);
    final kDim = kText.withValues(alpha: 0.6);
    final isFree = plan == VenuePlan.free;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: LinearGradient(
                colors: [plan.color.withValues(alpha: 0.18), plan.color.withValues(alpha: 0.04)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              border: Border.all(color: plan.color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Icon(isFree ? Icons.workspace_premium_outlined : Icons.workspace_premium, color: plan.color),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text('${plan.label} plan',
                              style: TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 15)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isFree
                            ? 'Limited feature access for this beta account'
                            : '${plan.label} access enabled for this beta account',
                        style: TextStyle(color: kDim, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: plan.color, borderRadius: BorderRadius.circular(20)),
                  child: const Text('Current',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                ),
              ],
            ),
          ),
    );
  }
}

class _ManageTileSkeleton extends StatelessWidget {
  const _ManageTileSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final base = colors.onSurface.withValues(alpha: 0.06);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(11)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(width: 110, height: 13, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(4))),
                  const SizedBox(height: 8),
                  Container(width: 170, height: 11, decoration: BoxDecoration(color: base, borderRadius: BorderRadius.circular(4))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccessLoadError extends StatelessWidget {
  final Future<void> Function() onRetry;

  const _AccessLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_outlined, color: colors.onSurfaceVariant),
          const SizedBox(height: 10),
          Text(
            'Plan access could not be loaded',
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _ManageTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String? trailingText;
  final VoidCallback? onTap;

  const _ManageTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailingText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final disabled = onTap == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Opacity(
            opacity: disabled ? 0.55 : 1,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(icon, color: color, size: 21),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.55))),
                      ],
                    ),
                  ),
                  if (trailingText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(trailingText!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: colors.onSurface.withValues(alpha: 0.5))),
                    )
                  else
                    Icon(Icons.chevron_right, color: colors.onSurface.withValues(alpha: 0.35)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
