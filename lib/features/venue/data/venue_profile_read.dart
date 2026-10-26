import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/data/registration_prefill.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_member_model.dart';
import 'venue_owner_stats_model.dart';

class VenueProfileContext {
  const VenueProfileContext({
    required this.me,
    required this.venueId,
    required this.member,
    required this.personalLabel,
    required this.registrationPrefill,
  });
  final MeContextModel me;
  final String? venueId;
  final MemberVenue? member;
  final String personalLabel;
  final RegistrationPrefill registrationPrefill;
  VenueMemberRole get role =>
      VenueMemberRoleExt.fromApi(member?.role ?? 'STAFF');
  bool get isClaimLocked =>
      member?.isPendingOwnerSetup == true ||
      member?.isRejectedOwnerClaim == true;

  factory VenueProfileContext.fromMe(
    Map<String, dynamic> me,
    String? requested,
  ) {
    final ctx = MeContextModel.fromMe(me);
    var id = requested;
    if (id == null || id.isEmpty) {
      id = ctx.activeVenueId;
      if ((id == null || id.isEmpty) && ctx.memberVenues.isNotEmpty) {
        id = ctx.memberVenues.first.id;
      }
    }
    final username = me['username']?.toString();
    final name = (me['fullName'] ?? me['full_name'])?.toString();
    return VenueProfileContext(
      me: ctx,
      registrationPrefill: RegistrationPrefill.fromMe(
        me,
        sessionRevision: SecureStorage.sessionRevision,
      ),
      venueId: id,
      member: ctx.memberVenues.where((v) => v.id == id).firstOrNull,
      personalLabel: username != null && username.isNotEmpty
          ? '@$username'
          : name != null && name.isNotEmpty
          ? name
          : 'Personal',
    );
  }
}

class VenueProfileReadResult {
  const VenueProfileReadResult(this.context, this.venue);
  final VenueProfileContext context;
  final VenueOwnerStatsVenue? venue;
}

class _IdentityAttempt {
  const _IdentityAttempt.success(this.venue) : error = null, stack = null;
  const _IdentityAttempt.failure(this.error, this.stack) : venue = null;
  final VenueOwnerStatsVenue? venue;
  final Object? error;
  final StackTrace? stack;
  VenueOwnerStatsVenue unwrap() {
    if (error != null) Error.throwWithStackTrace(error!, stack!);
    return venue!;
  }
}

/// Parallel identity/account confirmation with no additional result cache.
/// A speculative identity never overrides auth failure or pending/rejected
/// claim routing. Backend JWT/VIEW_STATS/media guards remain authoritative.
class VenueProfileRead {
  const VenueProfileRead({required this.readMe, required this.readIdentity});
  final Future<Map<String, dynamic>> Function(bool forceRefresh) readMe;
  final Future<VenueOwnerStatsVenue> Function(String venueId) readIdentity;
  Future<_IdentityAttempt> _identity(String id) =>
      Future.sync(() => readIdentity(id)).then(
        _IdentityAttempt.success,
        onError: (Object error, StackTrace stack) =>
            _IdentityAttempt.failure(error, stack),
      );

  Future<VenueProfileReadResult?> load({
    String? venueId,
    String? venueName,
    bool forceRefresh = false,
    required bool Function() isCurrent,
  }) async {
    if (!isCurrent()) return null;
    // Catch immediately: claim/auth routing can discard this future.
    final started = venueId != null && venueId.isNotEmpty
        ? _identity(venueId)
        : null;
    final me = await readMe(forceRefresh);
    if (!isCurrent()) return null;
    final ctx = VenueProfileContext.fromMe(me, venueId);
    final id = ctx.venueId;
    if (id == null || id.isEmpty) return VenueProfileReadResult(ctx, null);
    if (ctx.isClaimLocked) {
      return VenueProfileReadResult(
        ctx,
        VenueOwnerStatsVenue(
          id: id,
          name: ctx.member?.name ?? venueName ?? 'Venue',
          photo: ctx.member?.photoUrl,
          address: ctx.member?.address,
        ),
      );
    }
    final identity = await (started ?? _identity(id));
    if (!isCurrent()) return null;
    final venue = identity.unwrap();
    if (venue.id != id) {
      throw StateError('Profile identity does not match selected venue');
    }
    return VenueProfileReadResult(ctx, venue);
  }
}
