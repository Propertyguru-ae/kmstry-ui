import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_member_invite_page.dart';

/// Bildirime basılınca açılan router sayfası.
/// Backend'den gerçek durumu çeker, sonra uygun view'ı gösterir:
///   PENDING   → Invite (accept/decline)
///   ACTIVE    → Joined (success)
///   REJECTED  → Declined
///   diğer     → Notifications'a yönlendir
class VenueMemberStatusPage extends StatefulWidget {
  final String venueId;
  final String memberId;
  final String venueName;
  final String? role;
  final String? inviterName;

  const VenueMemberStatusPage({
    super.key,
    required this.venueId,
    required this.memberId,
    required this.venueName,
    this.role,
    this.inviterName,
  });

  @override
  State<VenueMemberStatusPage> createState() => _VenueMemberStatusPageState();
}

class _VenueMemberStatusPageState extends State<VenueMemberStatusPage> {
  final _repo = VenueMemberRepository();
  _ViewState _state = _ViewState.loading;
  String _role = '';
  String _venueName = '';

  @override
  void initState() {
    super.initState();
    _venueName = widget.venueName.isNotEmpty ? widget.venueName : 'Venue';
    _role = widget.role ?? '';
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final result = await _repo.getMemberStatus(widget.venueId, widget.memberId);
      if (!mounted) return;
      final status = result['status'] ?? 'PENDING';
      if (result['venueName']?.isNotEmpty == true) _venueName = result['venueName']!;
      if (result['role']?.isNotEmpty == true) _role = result['role']!;
      setState(() {
        switch (status.toUpperCase()) {
          case 'ACTIVE':
            _state = _ViewState.joined;
          case 'REJECTED':
            _state = _ViewState.declined;
          case 'PENDING':
            _state = _ViewState.pending;
          default:
            _state = _ViewState.other;
        }
      });
      // CANCELLED / EXPIRED / unknown → notifications'a gönder
      if (_state == _ViewState.other && mounted) {
        Navigator.pushReplacementNamed(context, AuthRoutes.notifications);
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.notifications);
    }
  }

  String _roleName(String raw) {
    switch (raw.toUpperCase()) {
      case 'OWNER':
        return 'Owner';
      case 'ADMIN':
        return 'Admin';
      case 'STAFF':
        return 'Staff';
      default:
        return raw.isNotEmpty ? raw : 'Member';
    }
  }

  IconData _roleIcon(String raw) {
    switch (raw.toUpperCase()) {
      case 'OWNER':
        return Icons.star_rounded;
      case 'ADMIN':
        return Icons.shield_rounded;
      default:
        return Icons.badge_rounded;
    }
  }

  Future<void> _goToDashboard() async {
    try {
      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: widget.venueId,
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AppShell(
          initialIsVenueContext: true,
          initialVenueId: widget.venueId,
        ),
      ),
      (route) => false,
    );
  }

  void _goToNotifications() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, AuthRoutes.appShell, (r) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _ViewState.loading:
        return const Scaffold(
          backgroundColor: Color(0xFF06091A),
          body: Center(
            child: CircularProgressIndicator(color: Color(0xFF1FD9A8)),
          ),
        );

      case _ViewState.pending:
        final invite = MemberVenue(
          id: widget.venueId,
          membershipId: widget.memberId,
          name: _venueName,
          role: _role.isNotEmpty ? _role : widget.role,
          status: 'PENDING',
          inviterName: widget.inviterName,
        );
        return VenueMemberInvitePage(pendingInvites: [invite]);

      case _ViewState.joined:
        return _JoinedView(
          venueName: _venueName,
          roleName: _roleName(_role),
          roleIcon: _roleIcon(_role),
          onDashboard: _goToDashboard,
          onClose: _goToNotifications,
        );

      case _ViewState.declined:
        return _DeclinedView(
          venueName: _venueName,
          onClose: _goToNotifications,
        );

      case _ViewState.other:
        return const Scaffold(backgroundColor: Color(0xFF06091A));
    }
  }
}

enum _ViewState { loading, pending, joined, declined, other }

// ─── Joined View ──────────────────────────────────────────────────────────────

class _JoinedView extends StatelessWidget {
  final String venueName;
  final String roleName;
  final IconData roleIcon;
  final Future<void> Function() onDashboard;
  final VoidCallback onClose;

  const _JoinedView({
    required this.venueName,
    required this.roleName,
    required this.roleIcon,
    required this.onDashboard,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06091A),
      body: Stack(
        children: [
          Positioned(
            top: -60, left: -40,
            child: _Blob(240, const Color(0xFF1FD9A8), 0.10),
          ),
          Positioned(
            bottom: -40, right: -60,
            child: _Blob(200, const Color(0xFF1FD9A8), 0.07),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1FD9A8).withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF1FD9A8).withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.check_rounded, size: 44, color: Color(0xFF1FD9A8)),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    "You're already a member!",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0B1322),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF162040)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: const Color(0xFF1FD9A8).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: const Color(0xFF1FD9A8).withValues(alpha: 0.25),
                            ),
                          ),
                          child: Icon(roleIcon, size: 20, color: const Color(0xFF1FD9A8)),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'You accepted this invitation',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.4),
                                ),
                              ),
                              const SizedBox(height: 2),
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: roleName,
                                      style: const TextStyle(color: Color(0xFF1FD9A8)),
                                    ),
                                    const TextSpan(text: ' at '),
                                    TextSpan(text: venueName),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 36),
                  _ActionButton(
                    label: 'Go to Venue Dashboard',
                    icon: Icons.dashboard_rounded,
                    color: const Color(0xFF1FD9A8),
                    textColor: const Color(0xFF06091A),
                    onTap: onDashboard,
                  ),
                  const SizedBox(height: 12),
                  _ActionButton(
                    label: 'Close',
                    onTap: onClose,
                    outlined: true,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Declined View ────────────────────────────────────────────────────────────

class _DeclinedView extends StatelessWidget {
  final String venueName;
  final VoidCallback onClose;

  const _DeclinedView({required this.venueName, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06091A),
      body: Stack(
        children: [
          Positioned(
            top: -60, left: -40,
            child: _Blob(240, const Color(0xFF5A7090), 0.08),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
                    decoration: BoxDecoration(
                      color: const Color(0xFF5A7090).withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF5A7090).withValues(alpha: 0.25),
                        width: 1.5,
                      ),
                    ),
                    child: const Icon(Icons.close_rounded, size: 44, color: Color(0xFF5A7090)),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Invitation declined',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'You declined the invitation to join $venueName.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.35),
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _ActionButton(label: 'Close', onTap: onClose, outlined: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared widgets ───────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color color;
  final Color textColor;
  final bool outlined;
  final VoidCallback onTap;

  const _ActionButton({
    required this.label,
    required this.onTap,
    this.icon,
    this.color = const Color(0xFF1E3060),
    this.textColor = const Color(0xFF4A6280),
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 15),
          decoration: BoxDecoration(
            color: outlined ? Colors.transparent : color,
            borderRadius: BorderRadius.circular(16),
            border: outlined ? Border.all(color: const Color(0xFF1E3060)) : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 18, color: outlined ? textColor : textColor),
                const SizedBox(width: 8),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: outlined ? const Color(0xFF4A6280) : textColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;
  const _Blob(this.size, this.color, this.opacity);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), Colors.transparent],
          stops: const [0.0, 0.7],
        ),
      ),
    );
  }
}
