import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

/// Owner tarafından PENDING olarak eklenen kullanıcıya gösterilen davet ekranı.
/// Birden fazla bekleyen davet varsa hepsini sırayla listeler.
class VenueMemberInvitePage extends StatefulWidget {
  /// PENDING & role != OWNER olan üyelikler
  final List<MemberVenue> pendingInvites;

  const VenueMemberInvitePage({super.key, required this.pendingInvites});

  @override
  State<VenueMemberInvitePage> createState() => _VenueMemberInvitePageState();
}

class _VenueMemberInvitePageState extends State<VenueMemberInvitePage> {
  final _repo = VenueMemberRepository();
  final Set<String> _loading = {};

  String _roleName(String? role) {
    switch (role?.toUpperCase()) {
      case 'ADMIN':
        return 'Admin';
      case 'STAFF':
        return 'Staff';
      default:
        return role ?? 'Member';
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
      _navigateAfterAction();
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
      _navigateAfterAction();
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

  void _navigateAfterAction() {
    Navigator.pushNamedAndRemoveUntil(
      context,
      AuthRoutes.authGate,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 48),
            Icon(Icons.business_center_outlined,
                size: 56, color: colors.primary),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                widget.pendingInvites.length == 1
                    ? 'You\'ve been invited to a venue'
                    : 'You have ${widget.pendingInvites.length} venue invitations',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Review and respond to your invitations below.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: widget.pendingInvites.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, i) {
                  final invite = widget.pendingInvites[i];
                  final isLoading =
                      _loading.contains(invite.membershipId ?? '');
                  return _InviteCard(
                    invite: invite,
                    roleName: _roleName(invite.role),
                    isLoading: isLoading,
                    onAccept: isLoading ? null : () => _accept(invite),
                    onDecline: isLoading ? null : () => _decline(invite),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InviteCard extends StatelessWidget {
  final MemberVenue invite;
  final String roleName;
  final bool isLoading;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;

  const _InviteCard({
    required this.invite,
    required this.roleName,
    required this.isLoading,
    this.onAccept,
    this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Venue avatar
              _VenueAvatar(photo: invite.photoUrl, name: invite.name, colors: colors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invite.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.badge_outlined,
                            size: 14,
                            color: colors.onSurface.withValues(alpha: 0.5)),
                        const SizedBox(width: 4),
                        Text(
                          'Role: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface.withValues(alpha: 0.5),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: colors.primaryContainer,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            roleName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.onPrimaryContainer,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDecline,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Decline'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isLoading
                      ? const SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VenueAvatar extends StatelessWidget {
  final String? photo;
  final String name;
  final ColorScheme colors;

  const _VenueAvatar(
      {required this.photo, required this.name, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          photo!,
          width: 52,
          height: 52,
          fit: BoxFit.cover,
          errorBuilder: (ctx, err, stack) => _placeholder(),
        ),
      );
    }
    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: colors.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: colors.onPrimaryContainer,
        ),
      ),
    );
  }
}
