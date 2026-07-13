import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

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
  VenuePlan? _venuePlan;

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
    if (id == null || id.isEmpty) return;
    try {
      final access = await VenueMemberRepository().getMyPermissions(id);
      if (!mounted) return;
      setState(() => _venuePlan = access.plan);
    } catch (_) {}
  }

  Future<void> _loadPersonalFlags() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _isPremium = me['isPremium'] == true;
        _isAnonymous = me['isAnonymous'] == true;
      });
    } catch (_) {}
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
        decoration: BoxDecoration(color: colors.surface, borderRadius: BorderRadius.circular(24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60, height: 60,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFE020D8)),
              child: const Icon(Icons.workspace_premium_rounded, color: Colors.white, size: 28),
            ),
            const SizedBox(height: 16),
            Text('Unlock KMSTRY+',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: colors.onSurface)),
            const SizedBox(height: 8),
            Text('Anonymous Mode, advanced filters, see who is interested and more — all with KMSTRY+.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, height: 1.4, color: colors.onSurface.withValues(alpha: 0.6))),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE020D8),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Coming soon', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteAccount() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          widget.isVenue ? 'Delete venue account?' : 'Delete personal account?',
        ),
        content: Text(
          widget.isVenue
              ? 'This will remove your access to ${widget.accountName}. Your root account stays active.'
              : 'This only removes your personal profile. Your account and any venue memberships stay active.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      if (widget.isVenue) {
        final venueId = widget.venueId;
        if (venueId == null || venueId.isEmpty) {
          throw Exception('Venue ID is missing');
        }
        await AuthRepository().deleteVenueContextMembership(venueId: venueId);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        await AuthRepository().deletePersonalContextProfile();
        if (!mounted) return;
        Navigator.of(context)
            .pushNamedAndRemoveUntil(AuthRoutes.authGate, (r) => false);
      }
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not delete account: '
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
      body: ListView(
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
                        widget.isVenue ? 'Venue Account' : 'Personal Account',
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
                  colors: [_venuePlan!.color.withValues(alpha: 0.18), _venuePlan!.color.withValues(alpha: 0.04)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: Border.all(color: _venuePlan!.color.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Icon(_venuePlan == VenuePlan.free ? Icons.workspace_premium_outlined : Icons.workspace_premium,
                      color: _venuePlan!.color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('${_venuePlan!.label} plan',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colors.onSurface)),
                            if (_venuePlan!.priceAed > 0) ...[
                              const SizedBox(width: 6),
                              Text('· AED ${_venuePlan!.priceAed}/mo',
                                  style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
                            ],
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text('Manage this plan from the venue dashboard',
                            style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
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
                      ? [const Color(0xFFE020D8).withValues(alpha: 0.18), const Color(0xFFE020D8).withValues(alpha: 0.04)]
                      : [colors.onSurface.withValues(alpha: 0.06), colors.onSurface.withValues(alpha: 0.02)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: _isPremium ? const Color(0xFFE020D8).withValues(alpha: 0.45) : colors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: Row(
                children: [
                  Icon(_isPremium ? Icons.workspace_premium_rounded : Icons.workspace_premium_outlined,
                      color: _isPremium ? const Color(0xFFE020D8) : colors.onSurface.withValues(alpha: 0.6)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_isPremium ? 'KMSTRY+ active' : 'Free plan',
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: colors.onSurface)),
                        const SizedBox(height: 2),
                        Text(_isPremium
                            ? 'Anonymous Mode, filters, and more are unlocked'
                            : 'Upgrade to KMSTRY+ to unlock premium features',
                            style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.6))),
                      ],
                    ),
                  ),
                  if (!_isPremium)
                    GestureDetector(
                      onTap: _showPremiumUpsell,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFE020D8), borderRadius: BorderRadius.circular(20)),
                        child: const Text('Upgrade',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
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
                border: Border.all(color: colors.primary.withValues(alpha: 0.12)),
              ),
              child: SwitchListTile(
                value: _isAnonymous,
                onChanged: _togglingAnonymous ? null : _setAnonymous,
                secondary: Icon(Icons.visibility_off_outlined, color: colors.onSurface.withValues(alpha: 0.7)),
                title: Row(
                  children: [
                    Flexible(
                      child: Text('Anonymous Mode',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600)),
                    ),
                    if (!_isPremium) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE020D8).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('KMSTRY+',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Color(0xFFE020D8))),
                      ),
                    ],
                  ],
                ),
                subtitle: Text(
                  _isAnonymous
                      ? 'You are invisible — check in without appearing to others'
                      : 'Check in and browse without appearing to others',
                  style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6), fontSize: 12),
                ),
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
                  : Icon(Icons.delete_forever_outlined, color: colors.error),
              title: Text(
                widget.isVenue
                    ? 'Delete Venue Account'
                    : 'Delete Personal Account',
                style: TextStyle(
                  color: colors.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                widget.isVenue
                    ? 'Removes your access to this venue. Root account stays active.'
                    : 'This only removes your personal profile. Venue memberships stay active.',
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
