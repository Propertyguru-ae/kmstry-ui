import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/profile/presentation/blocked_users_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/notifications_settings_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_notifications_settings_page.dart';

class AccountDetailPage extends StatefulWidget {
  final String accountName;
  final bool isVenue;
  final String? venueId;

  const AccountDetailPage({
    super.key,
    required this.accountName,
    required this.isVenue,
    this.venueId,
  });

  @override
  State<AccountDetailPage> createState() => _AccountDetailPageState();
}

class _AccountDetailPageState extends State<AccountDetailPage> {
  bool _deleting = false;
  bool _isPremium = false;
  bool _isAnonymous = false;
  bool _togglingAnonymous = false;
  int _blockedCount = 0;
  VenuePlan? _venuePlan;
  // Bu venue'nin tek OWNER'ı benim mi → "Leave venue" yerine "Delete venue".
  bool _isSoleOwner = false;
  // Gates the plan card so it renders once — avoids a "Free → Premium" flip (or
  // a late-appearing venue plan banner) while the account data loads.
  bool _planLoaded = false;

  @override
  void initState() {
    super.initState();
    if (widget.isVenue) {
      _loadVenuePlan();
    } else {
      _loadPersonalFlags();
    }
  }

  Future<void> _loadVenuePlan() async {
    final id = widget.venueId;
    if (id == null || id.isEmpty) {
      if (mounted) setState(() => _planLoaded = true);
      return;
    }
    try {
      final access = await VenueMemberRepository().getMyPermissions(id);
      if (!mounted) return;
      setState(() {
        _venuePlan = access.plan;
        _isSoleOwner = access.isSoleOwner;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _planLoaded = true);
    }
  }

  Future<void> _loadPersonalFlags() async {
    try {
      final me = await AuthRepository().getMe();
      List<dynamic> blocked = const [];
      try {
        blocked = await MatchRepository().getBlockedUsers();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _isPremium = me['isPremium'] == true;
        _isAnonymous = me['isAnonymous'] == true;
        _blockedCount = blocked.length;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _planLoaded = true);
    }
  }

  Future<void> _setAnonymous(bool enabled) async {
    if (enabled && !_isPremium) {
      _showPremiumUpsell();
      return;
    }
    setState(() {
      _isAnonymous = enabled;
      _togglingAnonymous = true;
    });
    try {
      await AuthRepository().setAnonymous(enabled);
    } catch (_) {
      if (mounted) setState(() => _isAnonymous = !enabled);
    } finally {
      if (mounted) setState(() => _togglingAnonymous = false);
    }
  }

  void _showPremiumUpsell() {
    final colors = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(22, 26, 22, 22),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE020D8),
              ),
              child: const Icon(
                Icons.workspace_premium_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'KMSTRY+ access',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'KMSTRY+ is not enabled for this beta account. Access is assigned by the KMSTRY test team.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.4,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE020D8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text(
                  'Close',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    // Tek OWNER isem venue'den "ayrılamam" (backend son owner'ı reddeder);
    // bunun yerine mekanı silerim.
    final soleOwnerDelete = widget.isVenue && _isSoleOwner;

    final String title;
    final String message;
    final String confirmLabel;
    final IconData icon;
    if (soleOwnerDelete) {
      title = 'Delete venue profile?';
      message =
          'You are the only owner of ${widget.accountName}. Your ownership and '
          'this venue\'s KMSTRY profile (custom photo, offers, events, stories) '
          'will be removed, and other members lose access. The venue itself '
          'stays on the map as a public place and can be claimed again. Your '
          'KMSTRY account and other profiles stay active. This cannot be undone.';
      confirmLabel = 'Delete venue profile';
      icon = Icons.delete_forever_rounded;
    } else if (widget.isVenue) {
      title = 'Leave this venue?';
      message =
          'Your access to ${widget.accountName} will be removed. Your KMSTRY '
          'account and other profiles will stay active.';
      confirmLabel = 'Leave venue';
      icon = Icons.logout_rounded;
    } else {
      title = 'Delete personal profile?';
      message =
          'Only your personal profile will be deleted. Your KMSTRY account and '
          'any venue access will stay active.';
      confirmLabel = 'Delete personal profile';
      icon = Icons.person_remove_rounded;
    }

    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      icon: icon,
    );
    if (!confirmed || !mounted) return;

    setState(() => _deleting = true);
    try {
      if (widget.isVenue) {
        final venueId = widget.venueId;
        if (venueId == null || venueId.isEmpty) {
          throw Exception('Venue ID is missing');
        }
        if (soleOwnerDelete) {
          await VenueMemberRepository().deleteVenue(venueId);
        } else {
          await AuthRepository().deleteVenueContextMembership(venueId: venueId);
        }
        // Sunucu context'i (active_venue_id / last_active_context) zaten
        // sıfırladı. Önbelleği temizleyip AuthGate'e dön → gate taze /auth/me
        // ile personal home'a, hesap türü seçimine ya da (hiç hesap yoksa)
        // login'e yönlendirir. Aksi halde silinen venue hesabı açık kalıyordu.
        AuthRepository.invalidateMeCache();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AuthRoutes.authGate, (r) => false);
      } else {
        await AuthRepository().deletePersonalContextProfile();
        if (!mounted) return;
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(AuthRoutes.authGate, (r) => false);
      }
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message:
            'Could not delete account: '
            '${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
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
      body: !_planLoaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Account info card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          widget.isVenue
                              ? Icons.business_outlined
                              : Icons.person_outline,
                          color: colors.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.accountName,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              widget.isVenue
                                  ? 'Venue Account'
                                  : 'Personal Account',
                              style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.55),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Venue: plan (read-only; managed in venue dashboard) ─────
                if (widget.isVenue && _venuePlan != null) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: [
                          _venuePlan!.color.withValues(alpha: 0.18),
                          _venuePlan!.color.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _venuePlan!.color.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _venuePlan == VenuePlan.free
                              ? Icons.workspace_premium_outlined
                              : Icons.workspace_premium,
                          color: _venuePlan!.color,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${_venuePlan!.label} plan',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_venuePlan!.label} access is enabled for this beta account',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Personal: KMSTRY+ subscription + Privacy ─────────
                if (!widget.isVenue) ...[
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: LinearGradient(
                        colors: _isPremium
                            ? [
                                const Color(0xFFE020D8).withValues(alpha: 0.18),
                                const Color(0xFFE020D8).withValues(alpha: 0.04),
                              ]
                            : [
                                colors.onSurface.withValues(alpha: 0.06),
                                colors.onSurface.withValues(alpha: 0.02),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      border: Border.all(
                        color: _isPremium
                            ? const Color(0xFFE020D8).withValues(alpha: 0.45)
                            : colors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _isPremium
                              ? Icons.workspace_premium_rounded
                              : Icons.workspace_premium_outlined,
                          color: _isPremium
                              ? const Color(0xFFE020D8)
                              : colors.onSurface.withValues(alpha: 0.6),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isPremium ? 'KMSTRY+ active' : 'Standard access',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 15,
                                  color: colors.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _isPremium
                                    ? 'Anonymous Mode, filters, and more are unlocked'
                                    : 'KMSTRY+ is not enabled for this beta account',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.onSurface.withValues(
                                    alpha: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!_isPremium)
                          GestureDetector(
                            onTap: _showPremiumUpsell,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE020D8),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'Locked',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: SwitchListTile(
                      value: _isAnonymous,
                      onChanged: _togglingAnonymous ? null : _setAnonymous,
                      secondary: Icon(
                        Icons.visibility_off_outlined,
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              'Anonymous Mode',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (!_isPremium) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFFE020D8,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'KMSTRY+',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFE020D8),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        _isAnonymous
                            ? 'You are invisible — check in without appearing to others'
                            : 'Check in and browse without appearing to others',
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 8),

                // ── Notifications for THIS account ──
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.12),
                    ),
                  ),
                  child: ListTile(
                    leading: Icon(
                      Icons.notifications_none_rounded,
                      color: colors.primary,
                    ),
                    title: Text(
                      'Notifications',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      widget.isVenue
                          ? 'Team updates and event activity'
                          : 'Messages, invites and venue updates',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      final venueId = widget.venueId;
                      if (widget.isVenue &&
                          venueId != null &&
                          venueId.isNotEmpty) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => VenueNotificationsSettingsPage(
                              venueId: venueId,
                              venueName: widget.accountName,
                            ),
                          ),
                        );
                      } else {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsSettingsPage(),
                          ),
                        );
                      }
                    },
                  ),
                ),

                // ── Blocked (personal only) ──
                if (!widget.isVenue) ...[
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: colors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.12),
                      ),
                    ),
                    child: ListTile(
                      leading: Icon(
                        Icons.block_outlined,
                        color: colors.onSurface.withValues(alpha: 0.7),
                      ),
                      title: Text(
                        'Blocked',
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$_blockedCount',
                            style: TextStyle(
                              fontSize: 15,
                              color: colors.onSurface.withValues(alpha: 0.8),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BlockedUsersPage(),
                          ),
                        );
                        if (!mounted) return;
                        try {
                          final blocked =
                              await MatchRepository().getBlockedUsers();
                          if (mounted) {
                            setState(() => _blockedCount = blocked.length);
                          }
                        } catch (_) {}
                      },
                    ),
                  ),
                ],

                const SizedBox(height: 32),

                // Delete button
                Container(
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: colors.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: ListTile(
                    onTap: _deleting ? null : _deleteAccount,
                    leading: _deleting
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colors.error,
                            ),
                          )
                        : Icon(
                            Icons.delete_forever_outlined,
                            color: colors.error,
                          ),
                    title: Text(
                      !widget.isVenue
                          ? 'Delete Personal Account'
                          : _isSoleOwner
                              ? 'Delete Venue Profile'
                              : 'Leave Venue',
                      style: TextStyle(
                        color: colors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      !widget.isVenue
                          ? 'This only removes your personal profile. Venue memberships stay active.'
                          : _isSoleOwner
                              ? 'You are the only owner. Removes ownership and the venue profile; the place stays on the map. Your account stays active.'
                              : 'Removes your access to this venue. Your account stays active.',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

}
