import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

/// Bir davet için süren işlem; yalnızca o butonda yükleniyor göstergesi çıkar.
enum _InviteAction { accept, decline }

class VenueMemberInvitePage extends StatefulWidget {
  final List<MemberVenue> pendingInvites;
  final VenueMemberRepository? repository;

  const VenueMemberInvitePage({
    super.key,
    required this.pendingInvites,
    this.repository,
  });

  @override
  State<VenueMemberInvitePage> createState() => _VenueMemberInvitePageState();
}

class _VenueMemberInvitePageState extends State<VenueMemberInvitePage>
    with TickerProviderStateMixin {
  late final VenueMemberRepository _repo =
      widget.repository ?? VenueMemberRepository();
  final Map<String, _InviteAction> _busy = {};
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
    setState(() => _busy[membershipId] = _InviteAction.accept);
    try {
      await _repo.acceptMemberInvite(invite.id, membershipId);
      if (!mounted) return;
      AuthRepository.invalidateMeCache();
      setState(() {
        _busy.remove(membershipId);
        _accepted = true;
        _acceptedInvite = invite;
      });
      _successCtrl.forward();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(membershipId));
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
    setState(() => _busy[membershipId] = _InviteAction.decline);
    try {
      await _repo.declineMemberInvite(invite.id, membershipId);
      if (!mounted) return;
      AuthRepository.invalidateMeCache();
      _goToNotifications();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy.remove(membershipId));
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

    final palette = _InvitePalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
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
                        child: Text(
                          'Later',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: palette.teal,
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
                                    color: palette.ringCenter,
                                    borderRadius: BorderRadius.circular(24),
                                  ),
                                  child: Icon(
                                    Icons.storefront_rounded,
                                    size: 34,
                                    color: palette.magenta,
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
                                color: palette.magenta,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 7),
                            Text(
                              'NEW INVITATION',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: palette.magenta,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Headline
                        RichText(
                          textAlign: TextAlign.center,
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: palette.textPrimary,
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
                        Text(
                          'Someone added you to their team.\nReview the details below.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: palette.textSecondary,
                            height: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Bottom sheet
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: palette.sheet,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(26)),
                        border: Border(
                          top: BorderSide(color: palette.sheetBorder),
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
                                color: palette.handle,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),

                            if (invite != null)
                              _InviteCard(
                                invite: invite,
                                roleName: _roleName(invite.role),
                                roleIcon: _roleIcon(invite.role),
                                busyAction: _busy[invite.membershipId ?? ''],
                                // İşlem sürerken iki buton da kilitli; gösterge
                                // yalnızca basılan butonda.
                                onAccept: _busy.containsKey(
                                        invite.membershipId ?? '')
                                    ? null
                                    : () => _accept(invite),
                                onDecline: _busy.containsKey(
                                        invite.membershipId ?? '')
                                    ? null
                                    : () => _decline(invite),
                              ),

                            // Info box
                            Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                color: palette.blue.withValues(alpha: 0.08),
                                border: Border.all(
                                  color: palette.blue.withValues(alpha: 0.25),
                                ),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 15, color: palette.blue),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: palette.textSecondary,
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
                                              color: palette.blue,
                                              fontWeight: FontWeight.w700,
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
  final _InviteAction? busyAction;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _InviteCard({
    required this.invite,
    required this.roleName,
    required this.roleIcon,
    required this.busyAction,
    this.onAccept,
    this.onDecline,
  });

  String get _inviterInitial {
    final name = invite.inviterName ?? '';
    return name.isNotEmpty ? name[0].toUpperCase() : 'V';
  }

  @override
  Widget build(BuildContext context) {
    final palette = _InvitePalette.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: palette.card,
        border: Border.all(color: palette.cardBorder, width: 1.5),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.storefront_outlined,
                              size: 13, color: palette.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Venue',
                            style: TextStyle(
                                fontSize: 12, color: palette.textMuted),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  'Just now',
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              ],
            ),
          ),

          // Role section
          Container(
            margin: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: palette.magenta.withValues(alpha: 0.08),
              border: Border.all(
                  color: palette.magenta.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: palette.magenta.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(roleIcon, size: 17, color: palette.magenta),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'YOUR ROLE',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: palette.roleLabel,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        roleName,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: palette.magenta,
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
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                          fontSize: 12.5, color: palette.textSecondary),
                      children: [
                        const TextSpan(text: 'Invited by '),
                        TextSpan(
                          text: invite.inviterName ?? 'Venue Owner',
                          style: TextStyle(
                            color: palette.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const TextSpan(text: ' · Owner'),
                      ],
                    ),
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
                Expanded(
                  child: _DeclineButton(
                    onPressed: onDecline,
                    isLoading: busyAction == _InviteAction.decline,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: _AcceptButton(
                    onPressed: onAccept,
                    isLoading: busyAction == _InviteAction.accept,
                  ),
                ),
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
    final palette = _InvitePalette.of(context);
    return GestureDetector(
      onTap: onPressed,
      child: Opacity(
        // Diğer işlem sürerken kilitli olduğu belli olsun.
        opacity: onPressed == null && !isLoading ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: palette.cardBorder, width: 1.2),
            borderRadius: BorderRadius.circular(14),
          ),
          child: isLoading
              ? Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: palette.textSecondary),
                  ),
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.close, size: 15, color: palette.textSecondary),
                    const SizedBox(width: 6),
                    // Büyük yazı boyutunda butondan taşmasın.
                    Flexible(
                      child: Text(
                        'Decline',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
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
      child: Opacity(
        opacity: onPressed == null && !isLoading ? 0.45 : 1,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 13),
          // Uygulamanın standart birincil butonu (düz mavi).
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: AppColors.blue,
            boxShadow: [
              BoxShadow(
                color: AppColors.blue.withValues(alpha: 0.30),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
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
                    Flexible(
                      child: Text(
                        'Accept invitation',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
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
    final palette = _InvitePalette.of(context);
    return Scaffold(
      backgroundColor: palette.background,
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
                          color: palette.teal.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: palette.teal.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 44,
                          color: palette.teal,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    Text(
                      "You're in!",
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: palette.textPrimary,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Role + venue info
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 16),
                      decoration: BoxDecoration(
                        color: palette.sheet,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: palette.cardBorder),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: palette.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: palette.teal.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Icon(roleIcon,
                                size: 20, color: palette.teal),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'You are now',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: palette.textMuted,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: palette.textPrimary,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: roleName,
                                        style: TextStyle(color: palette.teal),
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
                        color: palette.textSecondary,
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
                            border: Border.all(color: palette.cardBorder),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            'Close',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: palette.textSecondary,
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

// ─── Palette ──────────────────────────────────────────────────────────────────

/// Davet sayfasının açık / koyu tema renkleri. Eski sabit koyu tonların çoğu
/// (#2E4560, #3A5070, #4A6280 …) zemine çok yakındı ve okunmuyordu.
class _InvitePalette {
  const _InvitePalette._(this.isDark);
  final bool isDark;

  static _InvitePalette of(BuildContext context) =>
      _InvitePalette._(Theme.of(context).brightness == Brightness.dark);

  Color get background => isDark ? AppColors.darkBg : const Color(0xFFF5F7FB);
  Color get sheet => isDark ? AppColors.darkSurface : Colors.white;
  Color get sheetBorder =>
      isDark ? const Color(0xFF1E2A48) : const Color(0xFFE3E8F0);
  Color get card => isDark ? const Color(0xFF0D1A30) : const Color(0xFFF8FAFD);
  Color get cardBorder =>
      isDark ? const Color(0xFF26386A) : const Color(0xFFDCE3EE);
  Color get handle => isDark
      ? Colors.white.withValues(alpha: 0.16)
      : Colors.black.withValues(alpha: 0.12);
  Color get ringCenter => isDark ? const Color(0xFF0D1525) : Colors.white;

  Color get textPrimary =>
      isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary;
  Color get textSecondary =>
      isDark ? const Color(0xFFB4C2D8) : AppColors.lightTextSecondary;
  Color get textMuted =>
      isDark ? const Color(0xFF8A9BB4) : const Color(0xFF6B7889);

  Color get magenta => isDark ? AppColors.magentaDark : const Color(0xFFB0129F);
  Color get roleLabel =>
      isDark ? const Color(0xFFE79BE3) : const Color(0xFF9A1489);
  Color get blue => isDark ? AppColors.blueDark : AppColors.blueLight;
  Color get teal => isDark ? AppColors.teal : const Color(0xFF087D61);
}
