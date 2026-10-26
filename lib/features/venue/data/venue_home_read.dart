import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';

import 'venue_owner_stats_model.dart';

/// Preserves Home's selected-venue claim routing, including the fallback when
/// a claim has not produced an active venue yet. Another venue's pending claim
/// must not hide an already-approved dashboard.
class VenueHomeContext {
  const VenueHomeContext({
    required this.venueId,
    required this.showPersonalBanner,
    required this.isPendingClaim,
    required this.isRejectedClaim,
    required this.pendingVenue,
    required this.rejectedVenue,
  });

  final String? venueId;
  final bool showPersonalBanner;
  final bool isPendingClaim;
  final bool isRejectedClaim;
  final MemberVenue? pendingVenue;
  final MemberVenue? rejectedVenue;

  bool get hasClaimView => isPendingClaim || isRejectedClaim;
  bool get hasVenue => venueId != null && venueId!.isNotEmpty;
  bool get pendingHasDocuments => pendingVenue?.hasDocuments ?? false;

  factory VenueHomeContext.fromMe(
    Map<String, dynamic> me, {
    String? requestedVenueId,
  }) {
    final ctx = MeContextModel.fromMe(me);
    var venueId = requestedVenueId;
    if (venueId == null || venueId.isEmpty) {
      venueId = ctx.activeVenueId;
      if ((venueId == null || venueId.isEmpty) && ctx.memberVenues.isNotEmpty) {
        venueId = ctx.memberVenues.first.id;
      }
    }
    final activeVenue = ctx.memberVenues
        .where((v) => v.id == venueId)
        .firstOrNull;
    final pendingVenue = (activeVenue?.isPendingOwnerSetup ?? false)
        ? activeVenue
        : (activeVenue == null
              ? ctx.memberVenues.where((v) => v.isPendingOwnerSetup).firstOrNull
              : null);
    final rejectedVenue = (activeVenue?.isRejectedOwnerClaim ?? false)
        ? activeVenue
        : (activeVenue == null
              ? ctx.memberVenues
                    .where((v) => v.isRejectedOwnerClaim)
                    .firstOrNull
              : null);
    final isPending =
        pendingVenue != null ||
        (activeVenue == null && ctx.nextAction == 'AWAIT_VENUE_APPROVAL');
    final isRejected =
        rejectedVenue != null ||
        (activeVenue == null &&
            (ctx.nextAction == 'VENUE_CLAIM_REJECTED' ||
                ctx.hasRejectedClaimOnly));
    return VenueHomeContext(
      venueId: venueId,
      showPersonalBanner: !ctx.hasPersonalProfile && !isRejected,
      isPendingClaim: isPending,
      isRejectedClaim: isRejected && !isPending,
      pendingVenue: pendingVenue,
      rejectedVenue: rejectedVenue,
    );
  }
}

class VenueHomeReadResult {
  const VenueHomeReadResult({required this.context, this.dashboard});
  final VenueHomeContext context;
  final VenueOwnerStatsResponse? dashboard;
}

class _DashboardAttempt {
  const _DashboardAttempt.success(this.data) : error = null, stack = null;
  const _DashboardAttempt.failure(this.error, this.stack) : data = null;
  final VenueOwnerStatsResponse? data;
  final Object? error;
  final StackTrace? stack;

  VenueOwnerStatsResponse unwrap() {
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return data!;
  }
}

/// No additional response/approval cache. With an explicit venue ID, account
/// and dashboard reads run concurrently. Never render a speculative dashboard
/// until getMe confirms the existing claim flow. Backend VIEW_STATS/JWT/media
/// guards still authorize every dashboard read independently.
class VenueHomeRead {
  const VenueHomeRead({required this.readMe, required this.readDashboard});

  final Future<Map<String, dynamic>> Function() readMe;
  final Future<VenueOwnerStatsResponse> Function(String venueId) readDashboard;

  Future<_DashboardAttempt> _dashboard(String venueId) =>
      Future.sync(() => readDashboard(venueId)).then(
        _DashboardAttempt.success,
        onError: (Object error, StackTrace stack) =>
            _DashboardAttempt.failure(error, stack),
      );

  Future<VenueHomeReadResult?> load({
    String? venueId,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    // Consume errors immediately, even if getMe fails or this turns out to be a
    // pending/rejected claim. An ignored speculative read must never produce an
    // unhandled Future error or replace a valid claim view with an error page.
    final started = venueId != null && venueId.isNotEmpty
        ? _dashboard(venueId)
        : null;
    final me = await readMe();
    if (!isCurrent()) return null;
    final context = VenueHomeContext.fromMe(me, requestedVenueId: venueId);
    if (context.hasClaimView || !context.hasVenue) {
      return VenueHomeReadResult(context: context);
    }
    final attempt = await (started ?? _dashboard(context.venueId!));
    if (!isCurrent()) return null;
    final dashboard = attempt.unwrap();
    if (dashboard.venue.id != context.venueId) {
      throw StateError('Dashboard venue does not match the selected context');
    }
    return VenueHomeReadResult(context: context, dashboard: dashboard);
  }
}
