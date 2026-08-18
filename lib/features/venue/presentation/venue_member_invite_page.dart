import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

class VenueMemberInvitePage extends StatefulWidget {
  final List<MemberVenue> pendingInvites;

  const VenueMemberInvitePage({super.key, required this.pendingInvites});

  @override
  State<VenueMemberInvitePage> createState() => _VenueMemberInvitePageState();
}

class _VenueMemberInvitePageState extends State<VenueMemberInvitePage>
    with TickerProviderStateMixin {
  final _repo = VenueMemberRepository();
  final Set<String> _loading = {};
  bool _accepted = false;
  MemberVenue? _acceptedInvite;

  late final AnimationController _spinCtrl;
  late final AnimationController _floatCtrl;
  late final AnimationController _successCtrl;
  late final Animation<double> _successScale;
  late final Animation<double> _successFade;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _floatCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
    _successCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _successScale = CurvedAnimation(parent: _successCtrl, curve: Curves.elasticOut);
    _successFade = CurvedAnimation(parent: _successCtrl, curve: Curves.easeIn);
  }

  @override
  void dispose() {
    _spinCtrl.dispose();
    _floatCtrl.dispose();
    _successCtrl.dispose();
    super.dispose();
  }

  String _roleName(String? role) {
    switch (role?.toUpperCase()) {
      case 'OWNER':
        return 'Owner';
      case 'ADMIN':
        return 'Admin';
      case 'STAFF':
        return 'Staff';
      default:
        return role ?? 'Member';
    }
  }

  IconData _roleIcon(String? role) {
    switch (role?.toUpperCase()) {
      case 'OWNER':
        return Icons.star_rounded;
      case 'ADMIN':
        return Icons.shield_rounded;
      default:
        return Icons.badge_rounded;
    }
  }

  Future<void> _accept(MemberVenue invite) async {
    final membershipId = invite.membershipId;
    if (membershipId == null) return;
    setState(() => _loading.add(membershipId));
    try {
      await _repo.acceptMemberInvite(invite.id, membershipId);
      if (!mounted) return;
      AuthRepository.invalidateMeCache();
      setState(() {
        _loading.remove(membershipId);
        _accepted = true;
        _acceptedInvite = invite;
      });
      _successCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading.remove(membershipId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _decline(MemberVenue invite) async {
    final membershipId = invite.membershipId;
    if (membershipId == null) return;
    setState(() => _loading.add(membershipId));
    try {
      await _repo.declineMemberInvite(invite.id, membershipId);
      if (!mounted) return;
      AuthRepository.invalidateMeCache();
      _goToNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading.remove(membershipId));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _goToNotifications() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
    } else {
      Navigator.pushNamedAndRemoveUntil(context, AuthRoutes.appShell, (r) => false);
    }
  }

  Future<void> _goToDashboard() async {
    final invite = _acceptedInvite;
    if (invite != null) {
      try {
        await AuthRepository().switchContext(
          lastActiveContext: 'VENUE',
          activeVenueId: invite.id,
        );
      } catch (_) {}
    }
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => AppShell(
          initialIsVenueContext: true,
          initialVenueId: invite?.id,
        ),
      ),
      (route) => false,
    );
  }

  double _floatOffset(double phase) {
    final t = (_floatCtrl.value + phase) % 1.0;
    return -14 * math.sin(t * math.pi);
  }

  @override
  Widget build(BuildContext context) {
    final invite =
        widget.pendingInvites.isNotEmpty ? widget.pendingInvites.first : null;

    if (_accepted && _acceptedInvite != null) {
      return _SuccessView(
        invite: _acceptedInvite!,
        roleName: _roleName(_acceptedInvite!.role),
        roleIcon: _roleIcon(_acceptedInvite!.role),
        scaleAnim: _successScale,
        fadeAnim: _successFade,
        onClose: _goToNotifications,
        onDashboard: _goToDashboard,
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF06091A),
      body: AnimatedBuilder(
        animation: _floatCtrl,
        builder: (_, __) => Stack(
          children: [
            // Orb 1 — pink top-left
            Positioned(
              top: -80 + _floatOffset(0),
              left: -60,
              child: _Orb(220, const Color(0xFFE020D8), 0.13),
            ),
            // Orb 2 — teal top-right
            Positioned(
              top: 30 + _floatOffset(2 / 6),
              right: -50,
              child: _Orb(180, const Color(0xFF1FD9A8), 0.09),
            ),
            // Orb 3 — orange bottom-right
            Positioned(
              bottom: 100 - _floatOffset(4 / 6),
              right: -30,
              child: _Orb(160, const Color(0xFFF08838), 0.07),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Later
                  Align(
                    alignment: Alignment.topRight,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 18, right: 22),
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: const Text(
                          'Later',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1FD9A8),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Hero
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      children: [
                        // Spinning gradient ring
                        AnimatedBuilder(
                          animation: _spinCtrl,
                          builder: (_, __) => SizedBox(
                            width: 84,
                            height: 84,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Transform.rotate(
                                  angle: _spinCtrl.value * 2 * math.pi,
                                  child: Container(
                                    width: 84,
                                    height: 84,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(28),
                                      gradient: const SweepGradient(colors: [
                                        Color(0xFFE020D8),
                                        Color(0xFF1FD9A8),
                                        Color(0xFF1A9FE8),
                                        Color(0xFFF08838),
                                        Color(0xFFE020D8),
                                      ]),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1525),
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: const Icon(
                                    Icons.storefront_rounded,
                                    size: 34,
                                    color: Color(0xFFE020D8),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),

                        // Eyebrow
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 18,
                              height: 2,
                              decoration: BoxDecoration(
                                color: const Color(0xFFE020D8),
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 7),
                            const Text(
                              'NEW INVITATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: Color(0xFFE020D8),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Headline
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.18,
                              letterSpacing: -0.6,
                            ),
                            children: [
                              const TextSpan(text: "You've been\ninvited to\n"),
                              TextSpan(
                                text: 'a venue.',
                                style: TextStyle(
                                  foreground: Paint()
                                    ..shader = const LinearGradient(
                                      colors: [
                                        Color(0xFFE020D8),
                                        Color(0xFF1A9FE8),
                                      ],
                                    ).createShader(
                                        const Rect.fromLTWH(0, 0, 220, 40)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Someone added you to their team.\nReview the details below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4A6280),
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom sheet
                  Expanded(
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Color(0xFF0B1322),
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(26)),
                        border: Border(
                          top: BorderSide(color: Color(0xFF162040)),
                        ),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                        child: Column(
                          children: [
                            // Handle
                            Container(
                              width: 32,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),

                            if (invite != null)
                              _InviteCard(
                                invite: invite,
                                roleName: _roleName(invite.role),
                                roleIcon: _roleIcon(invite.role),
                                isLoading: _loading
                                    .contains(invite.membershipId ?? ''),
                                onAccept:
                                    _loading.contains(invite.membershipId ?? '')
                                        ? null
                                        : () => _accept(invite),
                                onDecline:
                                    _loading.contains(invite.membershipId ?? '')
                                        ? null
                                        : () => _decline(invite),
                              ),

                            // Info box
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A9FE8)
                                    .withValues(alpha: 0.07),
                                border: Border.all(
                                  color: const Color(0xFF1A9FE8)
                                      .withValues(alpha: 0.15),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.info_outline_rounded,
                                      size: 14, color: Color(0xFF1A9FE8)),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: Color(0xFF4A6E90),
                                          height: 1.5,
                                        ),
                                        children: [
                                          const TextSpan(
                                            text:
                                                "Accepting gives you access to this venue's dashboard. You can ",
                                          ),
                                          TextSpan(
                                            text: 'leave anytime',
                                            style: TextStyle(
                                              color: const Color(0xFF1A9FE8),
                                              fontWeight: FontWeight.w600,
                                              shadows: [
                                                Shadow(
                                                  color: const Color(0xFF1A9FE8)
                                                      .withValues(alpha: 0.3),
                                                  blurRadius: 4,
                                                ),
                                              ],
                                            ),
                                          ),
                                          const TextSpan(
                                              text: ' from your profile.'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Invite Card ──────────────────────────────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final MemberVenue invite;
  final String roleName;
  final IconData roleIcon;
  final bool isLoading;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _InviteCard({
    required this.invite,
    required this.roleName,
    required this.roleIcon,
    required this.isLoading,
    this.onAccept,
    this.onDecline,
  });

  String get _inviterInitial {
    final name = invite.inviterName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'V';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1A30),
        border: Border.all(color: const Color(0xFF1E3060), width: 1.5),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: avatar + name + "2 min ago" style placeholder
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _VenueAvatar(photo: invite.photoUrl, name: invite.name),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFEEF2FF),
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: const [
                          Icon(Icons.storefront_outlined,
                              size: 12, color: Color(0xFF3A5070)),
                          SizedBox(width: 4),
                          Text(
                            'Venue',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF3A5070)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Text(
                  'Just now',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF2E4560)),
                ),
              ],
            ),
          ),

          // Role section
          Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE020D8).withValues(alpha: 0.08),
              border: Border.all(
                  color: const Color(0xFFE020D8).withValues(alpha: 0.20)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE020D8).withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(roleIcon, size: 17, color: const Color(0xFFE020D8)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'YOUR ROLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: Color(0xFF7A3060),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFF020D0),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Invited by
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF0A5090), Color(0xFF1A9FE8)],
                    ),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _inviterInitial,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF3A5070)),
                    children: [
                      const TextSpan(text: 'Invited by '),
                      TextSpan(
                        text: invite.inviterName ?? 'Venue Owner',
                        style: const TextStyle(
                          color: Color(0xFF7AA8D0),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const TextSpan(text: ' · Owner'),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Action buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
            child: Row(
              children: [
                Expanded(child: _DeclineButton(onPressed: onDecline, isLoading: isLoading)),
                const SizedBox(width: 10),
                Expanded(flex: 2, child: _AcceptButton(onPressed: onAccept, isLoading: isLoading)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Buttons ──────────────────────────────────────────────────────────────────

class _DeclineButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _DeclineButton({this.onPressed, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF1E3060)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFF5A7090)),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.close, size: 15, color: Color(0xFF5A7090)),
                  SizedBox(width: 6),
                  Text(
                    'Decline',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5A7090),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AcceptButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;

  const _AcceptButton({this.onPressed, required this.isLoading});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF1E3060)),
        ),
        child: isLoading
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check, size: 15, color: Colors.white),
                  SizedBox(width: 7),
                  Text(
                    'Accept invitation',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── Venue Avatar ─────────────────────────────────────────────────────────────

class _VenueAvatar extends StatelessWidget {
  final String? photo;
  final String name;

  const _VenueAvatar({required this.photo, required this.name});

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.network(photo!,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _placeholder()),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B10C0), Color(0xFFE020D8)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 28,
              decoration: const BoxDecoration(
                color: Color(0x1EFFFFFF),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(18)),
              ),
            ),
          ),
          Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Orb ──────────────────────────────────────────────────────────────────────

class _Orb extends StatelessWidget {
  final double size;
  final Color color;
  final double opacity;

  const _Orb(this.size, this.color, this.opacity);

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

// ─── Success View ─────────────────────────────────────────────────────────────

class _SuccessView extends StatelessWidget {
  final MemberVenue invite;
  final String roleName;
  final IconData roleIcon;
  final Animation<double> scaleAnim;
  final Animation<double> fadeAnim;
  final VoidCallback onClose;
  final VoidCallback onDashboard;

  const _SuccessView({
    required this.invite,
    required this.roleName,
    required this.roleIcon,
    required this.scaleAnim,
    required this.fadeAnim,
    required this.onClose,
    required this.onDashboard,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF06091A),
      body: Stack(
        children: [
          // Teal orb top-left
          Positioned(
            top: -60,
            left: -40,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x171FD9A8), Colors.transparent],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          // Green orb bottom-right
          Positioned(
            bottom: -40,
            right: -60,
            child: Container(
              width: 200,
              height: 200,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [Color(0x1200C896), Colors.transparent],
                  stops: [0.0, 0.7],
                ),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: fadeAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Animated check icon
                    ScaleTransition(
                      scale: scaleAnim,
                      child: Container(
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
                        child: const Icon(
                          Icons.check_rounded,
                          size: 44,
                          color: Color(0xFF1FD9A8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    const Text(
                      "You're in!",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Role + venue info
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
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
                            child: Icon(roleIcon,
                                size: 20, color: const Color(0xFF1FD9A8)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You are now',
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
                                        style: const TextStyle(
                                            color: Color(0xFF1FD9A8)),
                                      ),
                                      const TextSpan(text: ' at '),
                                      TextSpan(text: invite.name),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text(
                      'You now have access to the venue dashboard.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.35),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 36),

                    // Go to Dashboard
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: onDashboard,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1FD9A8),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.dashboard_rounded,
                                  size: 18, color: Color(0xFF06091A)),
                              SizedBox(width: 8),
                              Text(
                                'Go to Venue Dashboard',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF06091A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Close
                    SizedBox(
                      width: double.infinity,
                      child: GestureDetector(
                        onTap: onClose,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          decoration: BoxDecoration(
                            border: Border.all(color: const Color(0xFF1E3060)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text(
                            'Close',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF4A6280),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
