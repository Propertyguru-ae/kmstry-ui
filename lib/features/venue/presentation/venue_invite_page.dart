import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';

class VenueInvitePage extends StatefulWidget {
  final String token;

  const VenueInvitePage({super.key, required this.token});

  @override
  State<VenueInvitePage> createState() => _VenueInvitePageState();
}

class _VenueInvitePageState extends State<VenueInvitePage> {
  final _repo = VenueInviteRepository();

  bool _loading = true;
  bool _accepting = false;
  bool _declined = false;
  String? _error;
  VenueInviteInfo? _invite;

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
      final info = await _repo.getInvite(widget.token);
      if (!mounted) return;
      setState(() {
        _invite = info;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Invite not found or has expired.';
      });
    }
  }

  Future<void> _accept() async {
    final token = await SecureStorage.getAccessToken();
    final isLoggedIn = token != null && token.isNotEmpty;
    if (!mounted) return;

    if (!isLoggedIn) {
      // Login sayfasına git — login sonrası /invites/pending check ile geri dönülür
      Navigator.pushReplacementNamed(context, AuthRoutes.login);
      return;
    }

    setState(() => _accepting = true);
    try {
      await _repo.acceptInvite(widget.token);
      if (!mounted) return;
      // Me cache'ini temizle — yeni venue membership yansısın
      AuthRepository.invalidateMeCache();
      _showSuccess();
    } catch (e) {
      if (!mounted) return;
      setState(() => _accepting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showSuccess() {
    final invite = _invite!;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('You\'re in!'),
        content: Text(
          'You\'ve joined ${invite.venue.name} as ${invite.roleName}.',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              // AuthGate'e göndererek venue context'ini aktifleştir
              Navigator.pushNamedAndRemoveUntil(
                context,
                AuthRoutes.authGate,
                (route) => false,
              );
            },
            child: const Text('Go to venue'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _declined
                ? _buildDeclined(colors)
                : _error != null
                    ? _buildError(colors)
                    : _buildContent(colors),
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
            Icon(Icons.link_off_rounded,
                size: 64, color: colors.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 20),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(AuthRoutes.login),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ColorScheme colors) {
    final invite = _invite!;

    if (invite.isUsed) {
      return _buildStatus(
        colors,
        icon: Icons.check_circle_outline,
        iconColor: colors.primary,
        title: 'Invite already used',
        subtitle: 'This invite link has already been accepted.',
      );
    }

    if (invite.isExpired) {
      return _buildStatus(
        colors,
        icon: Icons.timer_off_outlined,
        iconColor: colors.error,
        title: 'Invite expired',
        subtitle: 'This invite link is no longer valid. Ask the venue owner for a new one.',
      );
    }

    return Column(
      children: [
        const Spacer(),
        // Venue photo / icon
        _VenueAvatar(photo: invite.venue.photo, name: invite.venue.name, colors: colors),
        const SizedBox(height: 24),
        // Invite text
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              Text(
                'You\'ve been invited to',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                invite.venue.name,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (invite.venue.city != null) ...[
                const SizedBox(height: 4),
                Text(
                  invite.venue.city!,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              // Role badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.badge_outlined, size: 18, color: colors.onPrimaryContainer),
                    const SizedBox(width: 8),
                    Text(
                      invite.roleName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const Spacer(),
        // Accept button
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _accepting ? null : _accept,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _accepting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text(
                      'Accept Invitation',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                setState(() => _declined = true);
                try {
                  await _repo.declineInvite(widget.token);
                } catch (_) {
                  // Non-critical: even if the backend call fails, UI shows declined state.
                }
              },
              child: Text(
                'Decline',
                style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDeclined(ColorScheme colors) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colors.errorContainer.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.do_not_disturb_on_outlined,
                  size: 36, color: colors.error),
            ),
            const SizedBox(height: 24),
            const Text(
              'Invite Declined',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              'You have declined the venue invite. You can always ask for a new link later.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.6,
                color: colors.onSurface.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .pushReplacementNamed(AuthRoutes.login),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text(
                  'Go to Login',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: () => Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => UsernameOnboardingPage(
                    cancelRoute: AuthRoutes.login,
                  ),
                ),
              ),
              child: Text(
                'Want to create a personal account instead? →',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: colors.onSurface.withValues(alpha: 0.45),
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(
    ColorScheme colors, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: iconColor),
            const SizedBox(height: 20),
            Text(
              title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: colors.onSurface.withValues(alpha: 0.6),
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pushReplacementNamed(AuthRoutes.login),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _VenueAvatar extends StatelessWidget {
  final String? photo;
  final String name;
  final ColorScheme colors;

  const _VenueAvatar({
    required this.photo,
    required this.name,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Image.network(
          photo!,
          width: 100,
          height: 100,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.w800,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
