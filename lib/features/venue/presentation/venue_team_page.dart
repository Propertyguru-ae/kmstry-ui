import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'venue_permissions_page.dart';

class VenueTeamPage extends StatefulWidget {
  final String venueId;

  /// Caller's role — only OWNER can manage team members.
  final VenueMemberRole callerRole;

  const VenueTeamPage({
    super.key,
    required this.venueId,
    required this.callerRole,
  });

  @override
  State<VenueTeamPage> createState() => _VenueTeamPageState();
}

class _VenueTeamPageState extends State<VenueTeamPage> {
  final _repo = VenueMemberRepository();

  bool _loading = true;
  String? _error;
  List<VenueMember> _members = [];
  int _roleCount = 0;

  bool _pendingExpanded = true;
  bool _pastExpanded = false;

  bool get _isOwner => widget.callerRole == VenueMemberRole.owner;
  bool get _canManage => _isOwner || VenueSession.instance.can(VenuePermission.memberManage);
  bool get _canManageRoles => _isOwner || VenueSession.instance.can(VenuePermission.roleManage);
  bool get _canSeePending => _canManage;
  bool get _canAccessPermissions => _isOwner || VenueSession.instance.can(VenuePermission.roleManage);

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
      final results = await Future.wait([
        _repo.getMembers(widget.venueId),
        _repo.getRoles(widget.venueId),
      ]);
      if (!mounted) return;
      setState(() {
        _members = results[0] as List<VenueMember>;
        _roleCount = (results[1] as List<VenueRole>).length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load team.';
      });
    }
  }

  Future<void> _cleanPastInvites() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Past invites temizlensin mi?'),
        content: const Text('Reddedilen, iptal edilen ve süresi dolan davetler listeden kaldırılacak.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Temizle', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _repo.cleanPastInvites(widget.venueId);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Temizlenemedi: $e')),
      );
    }
  }

  Future<void> _openAddMember() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => VenueAddMemberPage(venueId: widget.venueId, repo: _repo),
      ),
    );
    if (added == true) _load();
  }

  Future<void> _openPermissions() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePermissionsPage(
          venueId: widget.venueId,
          callerRole: widget.callerRole,
        ),
      ),
    );
  }

  Future<void> _changeRole(VenueMember member) async {
    // Tüm rolleri önce çek (owner hariç)
    List<VenueRole> roles;
    try {
      final all = await _repo.getRoles(widget.venueId);
      roles = all.where((r) => !r.isOwnerRole).toList();
    } catch (_) {
      roles = [];
    }
    if (!mounted) return;

    final picked = await showModalBottomSheet<VenueRole>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _RolePickerSheet(
        current: member.role,
        currentVenueRoleId: member.venueRoleId,
        roles: roles,
      ),
    );
    if (picked == null) return;

    // System roles: id == 'ADMIN' | 'STAFF'; custom roles: UUID
    final enumRole = picked.id == 'ADMIN'
        ? VenueMemberRole.admin
        : VenueMemberRole.staff;
    final customId =
        (picked.id != 'ADMIN' && picked.id != 'STAFF') ? picked.id : null;

    // Aynı rol seçildiyse işlem yapma
    if (enumRole == member.role && customId == member.venueRoleId) return;

    try {
      await _repo.updateMemberRole(
        widget.venueId,
        member.id,
        enumRole,
        venueRoleId: customId,
      );
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to change role: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _editStaff(VenueMember member) async {
    final edited = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditStaffSheet(
        venueId: widget.venueId,
        member: member,
        repo: _repo,
      ),
    );
    if (edited == true) _load();
  }

  Future<void> _cancelInvite(VenueMember member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Invite'),
        content: Text(
            'Cancel the pending invite for ${member.user.displayName}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style:
                TextButton.styleFrom(foregroundColor: Colors.orange),
            child: const Text('Cancel Invite'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _repo.cancelMemberInvite(widget.venueId, member.id);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to cancel invite: $e')),
      );
    }
  }

  Future<void> _resendInvite(VenueMember member) async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 56, height: 56,
                decoration: BoxDecoration(
                  color: _TeamColors.mavi.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_outlined, color: _TeamColors.mavi, size: 26),
              ),
              const SizedBox(height: 16),
              Text(
                'Daveti Yeniden Gönder',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.onSurface),
              ),
              const SizedBox(height: 8),
              Text(
                '${member.user.displayName} adlı kullanıcıya davet yeniden gönderilecek.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: FilledButton.styleFrom(
                    backgroundColor: _TeamColors.mavi,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Gönder', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('İptal', style: TextStyle(color: colors.onSurface.withValues(alpha: 0.5))),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (confirmed != true) return;

    try {
      await _repo.addMember(widget.venueId, member.user.id, member.role);
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final colors = Theme.of(ctx).colorScheme;
          final isDark = Theme.of(ctx).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  width: 56, height: 56,
                  decoration: BoxDecoration(
                    color: _TeamColors.turkuaz.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle_outline_rounded, color: _TeamColors.turkuaz, size: 28),
                ),
                const SizedBox(height: 16),
                Text(
                  'Davet Gönderildi',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.onSurface),
                ),
                const SizedBox(height: 8),
                Text(
                  '${member.user.displayName} adlı kullanıcıya davet başarıyla yeniden gönderildi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: colors.onSurface.withValues(alpha: 0.6)),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: _TeamColors.turkuaz,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Tamam', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ],
            ),
          );
        },
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Davet gönderilemedi: $e')),
      );
    }
  }

  Future<void> _removeMember(VenueMember member) async {
    final isStaff =
        member.user.isStaff && member.user.staffVenueId == widget.venueId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text(isStaff ? 'Delete Staff' : 'Remove Member'),
          content: Text(
            isStaff
                ? '${member.user.displayName} will be removed from the team and their account will be permanently deleted.'
                : '${member.user.displayName} will be removed from the team. Their account will not be deleted.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.brandPrimary,
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(isStaff ? 'Delete' : 'Remove'),
                ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await _repo.removeMember(widget.venueId, member.id);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Action failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final bg = isDark ? const Color(0xFF06091A) : Colors.white;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: _NavBtn(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
          isDark: isDark,
        ),
        title: Text(
          _canManage || _canManageRoles ? 'Team Management' : 'Team',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: colors.onSurface),
        ),
        centerTitle: true,
        actions: const [],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(colors)
              : _buildList(colors, isDark),
    );
  }

  Widget _buildError(ColorScheme colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              size: 48, color: colors.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 12),
          Text(_error!,
              style:
                  TextStyle(color: colors.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colors, bool isDark) {
    final activeMembers  = _members.where((m) => m.status == VenueMemberStatus.active).toList();
    final pendingMembers = _members.where((m) => m.status == VenueMemberStatus.pending).toList();
    final terminalMembers = _members.where((m) => m.status.isTerminal).toList();
    // Free plan tek operatörlü — rol hiyerarşisi yok, sadece owner sayılır.
    final roleCount = VenueSession.instance.hasFeature(VenueFeature.roleLevels) ? _roleCount : 1;

    if (_members.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.group_outlined, size: 52, color: colors.onSurface.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    Text('No team members yet.',
                        style: TextStyle(fontSize: 16, color: colors.onSurface.withValues(alpha: 0.5))),
                    if (_canManage) ...[
                      const SizedBox(height: 12),
                      Text('Use "Add Member" to invite staff.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 13, color: colors.onSurface.withValues(alpha: 0.4))),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (_canManage) _buildAddMemberBar(colors, isDark),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              children: [
                // ── Stats strip ──────────────────────────────────────────
                _StatsStrip(
                  active: activeMembers.length,
                  pending: pendingMembers.length,
                  roles: roleCount,
                  isDark: isDark,
                  onRolesTap: _canAccessPermissions ? _openPermissions : null,
                ),
                const SizedBox(height: 20),

                // ── Active members ───────────────────────────────────────
                if (activeMembers.isNotEmpty) ...[
                  _SectionLabel(
                    label: 'Team Members',
                    badge: activeMembers.length,
                    badgeColor: _TeamColors.turkuaz,
                    badgeLabel: '${activeMembers.length} active',
                    colors: colors,
                  ),
                  const SizedBox(height: 10),
                  ...activeMembers.map((m) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildMemberCard(m, colors, isDark),
                      )),
                ],

                // ── Pending invites (collapsible) ────────────────────────
                if (_canSeePending) ...[
                  const SizedBox(height: 16),
                  _CollapsibleSection(
                    label: 'Pending Invites',
                    count: pendingMembers.length,
                    badgeColor: _TeamColors.turuncu,
                    expanded: _pendingExpanded,
                    colors: colors,
                    isDark: isDark,
                    onToggle: () => setState(() => _pendingExpanded = !_pendingExpanded),
                    emptyText: 'No pending invites',
                    children: pendingMembers.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildPendingCard(m, colors, isDark),
                    )).toList(),
                  ),
                ],

                // ── Past invites (collapsible) ───────────────────────────
                if (_isOwner || _canManage) ...[
                  const SizedBox(height: 8),
                  _CollapsibleSection(
                    label: 'Past Invites',
                    count: terminalMembers.length,
                    badgeColor: colors.onSurface.withValues(alpha: 0.4),
                    expanded: _pastExpanded,
                    colors: colors,
                    isDark: isDark,
                    onToggle: () => setState(() => _pastExpanded = !_pastExpanded),
                    emptyText: 'No past invites',
                    trailing: terminalMembers.isNotEmpty
                        ? TextButton.icon(
                            onPressed: _cleanPastInvites,
                            icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                            label: const Text('Clean'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.error,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                          )
                        : null,
                    children: terminalMembers.map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildTerminalCard(m, colors, isDark),
                    )).toList(),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_canManage) _buildAddMemberBar(colors, isDark),
      ],
    );
  }

  Widget _buildAddMemberBar(ColorScheme colors, bool isDark) {
    final bg = isDark ? const Color(0xFF06091A) : const Color(0xFFF7F8FA);
    final plan = VenueSession.instance.plan;
    final limit = plan.staffLimit; // null = sınırsız
    // Koltuğu dolduranlar: aktif + bekleyen üyeler (owner dahil).
    final used = _members.where((m) => m.status == VenueMemberStatus.active || m.status == VenueMemberStatus.pending).length;
    final atLimit = limit != null && used >= limit;

    return Container(
      color: bg,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Koltuk sayacı — deneyip hata almadan durumu göster.
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.groups_outlined, size: 15, color: colors.onSurface.withValues(alpha: 0.5)),
                const SizedBox(width: 6),
                Text(
                  limit == null
                      ? '$used staff · ${plan.label} plan (unlimited)'
                      : '$used / $limit ${limit == 1 ? 'seat' : 'seats'} used · ${plan.label} plan',
                  style: TextStyle(fontSize: 12.5, color: colors.onSurface.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
          if (atLimit)
            FilledButton.icon(
              onPressed: () => PlanGate.openPaywall(context, feature: null),
              icon: const Icon(Icons.lock_outline, size: 18),
              label: Text(
                limit == 1 ? 'Upgrade to add staff' : 'Upgrade for more seats',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: plan.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            )
          else
            FilledButton.icon(
              onPressed: _openAddMember,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: const Text(
                'Add Member',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: _TeamColors.turkuaz,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(VenueMember member, ColorScheme colors, bool isDark) {
    final isCurrentOwner = member.role == VenueMemberRole.owner;
    final canManage = _canManage && !isCurrentOwner;
    final isStaffAccount = member.user.isStaff && member.user.staffVenueId == widget.venueId;
    final roleLabel = (member.venueRoleName ?? member.role.label).toUpperCase();
    final roleColor = _TeamColors.forRole(member.role, member.venueRoleName);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1322) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outline.withValues(alpha: isDark ? 0.10 : 0.12)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _TeamAvatar(displayName: member.user.displayName, photo: member.user.photo, color: roleColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(roleLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: roleColor, letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(member.user.displayName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: colors.onSurface)),
                if (member.user.username != null)
                  Text('@${member.user.username}',
                      style: TextStyle(fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.45))),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, size: 20,
                  color: colors.onSurface.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              itemBuilder: (_) => [
                if (isStaffAccount && _isOwner)
                  const PopupMenuItem(value: 'edit',
                      child: Row(children: [
                        Icon(Icons.edit_outlined, size: 18), SizedBox(width: 10), Text('Edit'),
                      ])),
                const PopupMenuItem(value: 'role',
                    child: Row(children: [
                      Icon(Icons.manage_accounts_outlined, size: 18), SizedBox(width: 10), Text('Change Role'),
                    ])),
                PopupMenuItem(value: 'remove',
                    child: Row(children: [
                      Icon(isStaffAccount ? Icons.delete_outline : Icons.person_remove_outlined,
                          size: 18, color: Colors.red),
                      const SizedBox(width: 10),
                      Text(isStaffAccount ? 'Delete' : 'Remove',
                          style: const TextStyle(color: Colors.red)),
                    ])),
              ],
              onSelected: (action) {
                if (action == 'edit') _editStaff(member);
                if (action == 'role') _changeRole(member);
                if (action == 'remove') _removeMember(member);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildPendingCard(VenueMember member, ColorScheme colors, bool isDark) {
    final roleLabel = (member.venueRoleName ?? member.role.label).toUpperCase();
    final roleColor = _TeamColors.forRole(member.role, member.venueRoleName);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1322) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _TeamColors.turuncu.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _TeamAvatar(displayName: member.user.displayName, photo: member.user.photo, color: roleColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(roleLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                        color: roleColor, letterSpacing: 0.8)),
                const SizedBox(height: 2),
                Text(member.user.displayName,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                        color: colors.onSurface)),
                if (member.user.username != null)
                  Text('@${member.user.username}',
                      style: TextStyle(fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.45))),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _TeamColors.turuncu.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6,
                        decoration: const BoxDecoration(
                            color: _TeamColors.turuncu, shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    const Text('Awaiting',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                            color: _TeamColors.turuncu)),
                  ],
                ),
              ),
              if (_canManage)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20,
                      color: colors.onSurface.withValues(alpha: 0.45)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'cancel',
                        child: Row(children: [
                          Icon(Icons.cancel_outlined, size: 18, color: _TeamColors.turuncu),
                          SizedBox(width: 10),
                          Text('Cancel Invite',
                              style: TextStyle(color: _TeamColors.turuncu)),
                        ])),
                  ],
                  onSelected: (action) {
                    if (action == 'cancel') _cancelInvite(member);
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerminalCard(VenueMember member, ColorScheme colors, bool isDark) {
    Color statusColor;
    switch (member.status) {
      case VenueMemberStatus.rejected: statusColor = Colors.red;
      case VenueMemberStatus.expired: statusColor = colors.onSurface.withValues(alpha: 0.4);
      case VenueMemberStatus.cancelled: statusColor = _TeamColors.turuncu;
      default: statusColor = colors.onSurface.withValues(alpha: 0.4);
    }
    final roleColor = _TeamColors.forRole(member.role, member.venueRoleName);

    return Opacity(
      opacity: 0.55,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0B1322) : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outline.withValues(alpha: 0.08)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            _TeamAvatar(displayName: member.user.displayName, photo: member.user.photo, color: roleColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.user.displayName,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: colors.onSurface)),
                  if (member.user.username != null)
                    Text('@${member.user.username}',
                        style: TextStyle(fontSize: 12, color: colors.onSurface.withValues(alpha: 0.45))),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.25)),
                  ),
                  child: Text(member.status.label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor)),
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    icon: Icon(Icons.more_vert, size: 20,
                        color: colors.onSurface.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'resend',
                          child: Row(children: [
                            Icon(Icons.send_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Re-invite'),
                          ])),
                    ],
                    onSelected: (action) {
                      if (action == 'resend') _resendInvite(member);
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
} // end _VenueTeamPageState

// ─── Brand colors ─────────────────────────────────────────────────────────────

class _TeamColors {
  static const magenta = Color(0xFFE020D8);
  static const turkuaz = Color(0xFF1FD9A8);
  static const mavi    = Color(0xFF1A9FE8);
  static const turuncu = Color(0xFFF08838);
  static const koruMor = Color(0xFF3D1F8C);

  static Color forRole(VenueMemberRole role, String? customName) {
    if (customName != null) return turuncu;
    return switch (role) {
      VenueMemberRole.owner => magenta,
      VenueMemberRole.admin => turkuaz,
      VenueMemberRole.staff => mavi,
    };
  }
}

// ─── Stats strip ──────────────────────────────────────────────────────────────

class _StatsStrip extends StatelessWidget {
  final int active;
  final int pending;
  final int roles;
  final bool isDark;
  final VoidCallback? onRolesTap;

  const _StatsStrip({
    required this.active,
    required this.pending,
    required this.roles,
    required this.isDark,
    this.onRolesTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0B1322) : const Color(0xFFF5F7FA);
    return Row(
      children: [
        _StatCard(value: '$active',  label: 'Active',  color: _TeamColors.turkuaz, bg: bg),
        const SizedBox(width: 10),
        _StatCard(value: '$pending', label: 'Pending', color: _TeamColors.turuncu, bg: bg),
        const SizedBox(width: 10),
        _StatCard(value: '$roles',   label: 'Roles',   color: _TeamColors.magenta, bg: bg, onTap: onRolesTap),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final Color bg;
  final VoidCallback? onTap;

  const _StatCard({required this.value, required this.label, required this.color, required this.bg, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: onTap != null
                ? Border.all(color: color.withValues(alpha: 0.25))
                : null,
          ),
          child: Column(
            children: [
              Text(value,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: color)),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                          color: colors.onSurface.withValues(alpha: 0.45))),
                  if (onTap != null) ...[
                    const SizedBox(width: 3),
                    Icon(Icons.chevron_right_rounded, size: 13,
                        color: colors.onSurface.withValues(alpha: 0.35)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ColorScheme colors;
  final int? badge;
  final Color? badgeColor;
  final String? badgeLabel;

  const _SectionLabel({
    required this.label,
    required this.colors,
    this.badge,
    this.badgeColor,
    this.badgeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
              letterSpacing: 1.1, color: colors.onSurface.withValues(alpha: 0.45)),
        ),
        const Spacer(),
        if (badge != null && badgeLabel != null)
          Text(
            badgeLabel!,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: badgeColor ?? colors.onSurface.withValues(alpha: 0.5)),
          ),
      ],
    );
  }
}

// ─── Collapsible section ──────────────────────────────────────────────────────

class _CollapsibleSection extends StatelessWidget {
  final String label;
  final int count;
  final Color badgeColor;
  final bool expanded;
  final ColorScheme colors;
  final bool isDark;
  final VoidCallback onToggle;
  final String emptyText;
  final List<Widget> children;
  final Widget? trailing;

  const _CollapsibleSection({
    required this.label,
    required this.count,
    required this.badgeColor,
    required this.expanded,
    required this.colors,
    required this.isDark,
    required this.onToggle,
    required this.emptyText,
    required this.children,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                      letterSpacing: 1.1, color: colors.onSurface.withValues(alpha: 0.45)),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: badgeColor),
                    ),
                  ),
                const Spacer(),
                if (trailing != null) trailing!,
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(Icons.keyboard_arrow_down_rounded,
                      size: 20, color: colors.onSurface.withValues(alpha: 0.4)),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: count == 0
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(emptyText,
                          style: TextStyle(fontSize: 13,
                              color: colors.onSurface.withValues(alpha: 0.35))),
                    ),
                  ]
                : [const SizedBox(height: 10), ...children],
          ),
          secondChild: const SizedBox.shrink(),
        ),
      ],
    );
  }
}

// ─── Team avatar (rounded square) ────────────────────────────────────────────

class _TeamAvatar extends StatelessWidget {
  final String displayName;
  final String? photo;
  final Color color;

  const _TeamAvatar({required this.displayName, required this.photo, required this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    if (photo != null && photo!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(photo!, width: 46, height: 46, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _InitialAvatar(initial: initial, color: color, isDark: isDark)),
      );
    }
    return _InitialAvatar(initial: initial, color: color, isDark: isDark);
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final bool isDark;

  const _InitialAvatar({required this.initial, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.25 : 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Center(
        child: Text(initial,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
      ),
    );
  }
}

// ─── AppBar nav button ────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  const _NavBtn({required this.icon, required this.onTap, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1520) : const Color(0xFFEEF0F8);
    final fg = isDark ? Colors.white.withValues(alpha: 0.85) : const Color(0xFF0B1322);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.all(8),
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
        child: Icon(icon, size: 18, color: fg),
      ),
    );
  }
}

// ─── Üye Ekleme Bottom Sheet (iki sekme) ─────────────────────────────────────

// ─── Add Member Page ──────────────────────────────────────────────────────────

class VenueAddMemberPage extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;

  const VenueAddMemberPage({super.key, required this.venueId, required this.repo});

  @override
  State<VenueAddMemberPage> createState() => _VenueAddMemberPageState();
}

class _VenueAddMemberPageState extends State<VenueAddMemberPage> {
  bool _showInviteLink = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B1322) : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: _NavBtn(
          icon: Icons.arrow_back_ios_new_rounded,
          onTap: () => Navigator.pop(context),
          isDark: isDark,
        ),
        title: const Text('Add Member',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // ── Toggle ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: _ModeToggle(
              showInviteLink: _showInviteLink,
              isDark: isDark,
              onChanged: (v) => setState(() => _showInviteLink = v),
            ),
          ),
          // ── Content ───────────────────────────────────────────────────
          Expanded(
            child: _showInviteLink
                ? _InviteLinkTab(venueId: widget.venueId, venueRoles: const [])
                : _UsernameSearchTab(venueId: widget.venueId, repo: widget.repo),
          ),
        ],
      ),
    );
  }
}

// ─── Mode Toggle (segmented control) ─────────────────────────────────────────

class _ModeToggle extends StatelessWidget {
  final bool showInviteLink;
  final bool isDark;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.showInviteLink,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF0F1520) : const Color(0xFFEEF0F8);
    final activeBg = isDark ? const Color(0xFF1C2A3A) : Colors.white;
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          _ToggleTab(
            label: 'Find by Username',
            icon: Icons.person_search_outlined,
            isActive: !showInviteLink,
            activeBg: activeBg,
            activeColor: _TeamColors.turkuaz,
            inactiveColor: colors.onSurface.withValues(alpha: 0.45),
            onTap: () => onChanged(false),
          ),
          _ToggleTab(
            label: 'Invite Link',
            icon: Icons.link_rounded,
            isActive: showInviteLink,
            activeBg: activeBg,
            activeColor: _TeamColors.mavi,
            inactiveColor: colors.onSurface.withValues(alpha: 0.45),
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }
}

class _ToggleTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final Color activeBg;
  final Color activeColor;
  final Color inactiveColor;
  final VoidCallback onTap;

  const _ToggleTab({
    required this.label,
    required this.icon,
    required this.isActive,
    required this.activeBg,
    required this.activeColor,
    required this.inactiveColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? activeBg : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: isActive
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 6, offset: const Offset(0, 2))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? activeColor : inactiveColor),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? activeColor : inactiveColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Username Search Tab ──────────────────────────────────────────────────────

class _UsernameSearchTab extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;

  const _UsernameSearchTab({required this.venueId, required this.repo});

  @override
  State<_UsernameSearchTab> createState() => _UsernameSearchTabState();
}

class _UsernameSearchTabState extends State<_UsernameSearchTab> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;

  List<VenueRole> _roles = [];
  bool _loadingRoles = true;

  bool _searching = false;
  List<UserSearchResult> _results = [];
  UserSearchResult? _selected;
  VenueRole? _selectedRole;
  bool _adding = false;
  bool _roleDropdownOpen = false;

  @override
  void initState() {
    super.initState();
    _loadRoles();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await widget.repo.getRoles(widget.venueId);
      if (!mounted) return;
      final filtered = roles.where((r) => !r.isOwnerRole).toList();
      setState(() {
        _roles = filtered;
        _selectedRole = filtered.isNotEmpty
            ? filtered.firstWhere((r) => r.id == 'ADMIN', orElse: () => filtered.first)
            : null;
        _loadingRoles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
    }
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    if (v.trim().isEmpty) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 380), () => _search(v));
  }

  Future<void> _search(String q) async {
    setState(() => _searching = true);
    try {
      final r = await widget.repo.searchUsers(widget.venueId, q);
      if (!mounted) return;
      setState(() { _results = r; _searching = false; });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _add() async {
    final user = _selected;
    final role = _selectedRole;
    if (user == null || role == null || _adding) return;
    setState(() => _adding = true);
    try {
      final enumRole = role.id == 'ADMIN' ? VenueMemberRole.admin : VenueMemberRole.staff;
      final customId = (role.id != 'ADMIN' && role.id != 'STAFF') ? role.id : null;
      await widget.repo.addMember(widget.venueId, user.id, enumRole, venueRoleId: customId);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add: $e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    if (_loadingRoles) {
      return const Center(child: CircularProgressIndicator(color: _TeamColors.turkuaz));
    }

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Search ─────────────────────────────────────
                TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Search by username…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: _TeamColors.turkuaz)),
                          )
                        : (_searchCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () => setState(() {
                                  _searchCtrl.clear();
                                  _results = [];
                                  _selected = null;
                                }),
                              )
                            : null),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: colors.outline.withValues(alpha: 0.3)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: _TeamColors.turkuaz, width: 1.5),
                    ),
                  ),
                ),

                // ── Search results ──────────────────────────────
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F1520) : colors.surface,
                      border: Border.all(color: colors.outline.withValues(alpha: 0.18)),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: colors.outline.withValues(alpha: 0.12)),
                      itemBuilder: (_, i) {
                        final u = _results[i];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: _TeamColors.turkuaz.withValues(alpha: 0.14),
                            backgroundImage: u.photo != null && u.photo!.isNotEmpty
                                ? NetworkImage(u.photo!) : null,
                            child: u.photo == null || u.photo!.isEmpty
                                ? Text(
                                    u.displayName.isNotEmpty ? u.displayName[0].toUpperCase() : '?',
                                    style: const TextStyle(color: _TeamColors.turkuaz,
                                        fontSize: 13, fontWeight: FontWeight.w700),
                                  )
                                : null,
                          ),
                          title: Text(u.displayName,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: u.username != null
                              ? Text('@${u.username}',
                                  style: TextStyle(fontSize: 12,
                                      color: colors.onSurface.withValues(alpha: 0.5)))
                              : null,
                          onTap: () {
                            _searchFocus.unfocus();
                            setState(() {
                              _selected = u;
                              _results = [];
                              _searchCtrl.clear();
                            });
                          },
                        );
                      },
                    ),
                  ),
                ],

                // ── Selected user card ──────────────────────────
                if (_selected != null && _results.isEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Selected User',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: _TeamColors.turkuaz.withValues(alpha: 0.08),
                      border: Border.all(color: _TeamColors.turkuaz.withValues(alpha: 0.28)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: _TeamColors.turkuaz.withValues(alpha: 0.2),
                          backgroundImage: _selected!.photo != null && _selected!.photo!.isNotEmpty
                              ? NetworkImage(_selected!.photo!) : null,
                          child: _selected!.photo == null || _selected!.photo!.isEmpty
                              ? Text(
                                  _selected!.displayName.isNotEmpty
                                      ? _selected!.displayName[0].toUpperCase() : '?',
                                  style: const TextStyle(color: _TeamColors.turkuaz,
                                      fontSize: 15, fontWeight: FontWeight.w800),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_selected!.displayName,
                                  style: const TextStyle(fontSize: 14,
                                      fontWeight: FontWeight.w700, color: _TeamColors.turkuaz)),
                              if (_selected!.username != null)
                                Text('@${_selected!.username}',
                                    style: TextStyle(fontSize: 12,
                                        color: _TeamColors.turkuaz.withValues(alpha: 0.65))),
                            ],
                          ),
                        ),
                        GestureDetector(
                          onTap: () => setState(() => _selected = null),
                          child: Icon(Icons.close_rounded, size: 18,
                              color: _TeamColors.turkuaz.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Role selector ───────────────────────────────
                if (_roles.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('Role',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.5))),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () => setState(() => _roleDropdownOpen = !_roleDropdownOpen),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F1520) : colors.surface,
                        border: Border.all(
                          color: _roleDropdownOpen
                              ? _TeamColors.mavi
                              : _TeamColors.mavi.withValues(alpha: 0.4),
                          width: _roleDropdownOpen ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(_roleDropdownOpen ? 0 : 12),
                          bottomRight: Radius.circular(_roleDropdownOpen ? 0 : 12),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedRole?.name ?? 'Select a role',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: _selectedRole != null
                                    ? colors.onSurface
                                    : colors.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                          AnimatedRotation(
                            turns: _roleDropdownOpen ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: Icon(Icons.keyboard_arrow_down_rounded,
                                color: _TeamColors.mavi.withValues(alpha: 0.8), size: 22),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_roleDropdownOpen)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0F1520) : colors.surface,
                        border: Border(
                          left: BorderSide(color: _TeamColors.mavi, width: 1.5),
                          right: BorderSide(color: _TeamColors.mavi, width: 1.5),
                          bottom: BorderSide(color: _TeamColors.mavi, width: 1.5),
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Column(
                        children: _roles.map((role) {
                          final isSelected = _selectedRole?.id == role.id;
                          return InkWell(
                            onTap: () => setState(() {
                              _selectedRole = role;
                              _roleDropdownOpen = false;
                            }),
                            borderRadius: role == _roles.last
                                ? const BorderRadius.only(
                                    bottomLeft: Radius.circular(12),
                                    bottomRight: Radius.circular(12),
                                  )
                                : null,
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _TeamColors.mavi.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                border: role != _roles.last
                                    ? Border(bottom: BorderSide(
                                        color: _TeamColors.mavi.withValues(alpha: 0.15)))
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      role.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                        color: isSelected
                                            ? _TeamColors.mavi
                                            : colors.onSurface.withValues(alpha: 0.85),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    const Icon(Icons.check_rounded,
                                        color: _TeamColors.mavi, size: 18),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),

        // ── Bottom Add button ─────────────────────────────────────────
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _selected == null || _adding ? null : _add,
                style: FilledButton.styleFrom(
                  backgroundColor: _TeamColors.turkuaz,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: _TeamColors.turkuaz.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _adding
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _selected == null
                            ? 'Select a user first'
                            : 'Add as ${_selectedRole?.name ?? 'Member'}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Davet linki sheet loader (roles'u sheet açıkken fetch eder) ──────────────

class _InviteLinkSheetLoader extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;
  const _InviteLinkSheetLoader({required this.venueId, required this.repo});

  @override
  State<_InviteLinkSheetLoader> createState() => _InviteLinkSheetLoaderState();
}

class _InviteLinkSheetLoaderState extends State<_InviteLinkSheetLoader> {
  List<VenueRole>? _roles;

  @override
  void initState() {
    super.initState();
    widget.repo.getRoles(widget.venueId).then((roles) {
      if (mounted) setState(() => _roles = roles);
    }).catchError((_) {
      if (mounted) setState(() => _roles = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_roles == null) {
      return Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: colors.onSurface.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _InviteLinkTab(venueId: widget.venueId, venueRoles: _roles!),
          ],
        ),
      ),
    );
  }
}

// ─── Davet linki sekmesi ──────────────────────────────────────────────────────

class _InviteLinkTab extends StatefulWidget {
  final String venueId;
  final List<VenueRole> venueRoles;

  const _InviteLinkTab({required this.venueId, required this.venueRoles});

  @override
  State<_InviteLinkTab> createState() => _InviteLinkTabState();
}

class _InviteLinkTabState extends State<_InviteLinkTab> {
  final _inviteRepo = VenueInviteRepository();
  final _memberRepo = VenueMemberRepository();
  final _emailCtrl = TextEditingController();
  VenueRole? _selectedRole;
  bool _generating = false;
  bool _loadingRoles = false;
  List<VenueRole> _roles = [];
  InviteResult? _result;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    if (widget.venueRoles.isNotEmpty) {
      _roles = widget.venueRoles;
      _selectedRole = widget.venueRoles.firstWhere(
        (r) => r.id == 'STAFF',
        orElse: () => widget.venueRoles.last,
      );
    } else {
      _loadRoles();
    }
  }

  Future<void> _loadRoles() async {
    setState(() => _loadingRoles = true);
    try {
      final roles = await _memberRepo.getRoles(widget.venueId);
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _selectedRole = roles.firstWhere(
          (r) => r.id == 'STAFF',
          orElse: () => roles.isNotEmpty ? roles.last : roles.first,
        );
        _loadingRoles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
    }
  }

  bool _isValidEmail(String v) {
    final s = v.trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s);
  }

  Future<void> _generate() async {
    final role = _selectedRole;
    if (role == null || _generating) return;

    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid email address'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _generating = true);
    try {
      final enumRole =
          role.id == 'ADMIN' ? VenueMemberRole.admin : VenueMemberRole.staff;
      final customId =
          (role.id != 'ADMIN' && role.id != 'STAFF') ? role.id : null;

      final result = await _inviteRepo.createInvite(
        venueId: widget.venueId,
        email: email,
        role: enumRole,
        venueRoleId: customId,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyLink() {
    final url = _result?.inviteUrl;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    if (_loadingRoles) {
      return const Center(child: CircularProgressIndicator(color: _TeamColors.mavi));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: colors.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enter the person\'s email and pick a role. If they already have '
                    'a KMSTRY account, a join request is sent to them. If not, a '
                    'registration link is created to share via WhatsApp, SMS or any channel.',
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurface.withValues(alpha: 0.75),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Email
          TextField(
            controller: _emailCtrl,
            enabled: _result == null,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textCapitalization: TextCapitalization.none,
            onChanged: (_) {
              if (_result != null) setState(() => _result = null);
            },
            decoration: InputDecoration(
              labelText: 'Email',
              hintText: 'person@example.com',
              prefixIcon: const Icon(Icons.mail_outline, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Role picker
          if (_roles.isNotEmpty) ...[
            _VenueRolePicker(
              roles: _roles,
              selected: _selectedRole,
              onChanged: (r) => setState(() {
                _selectedRole = r;
                _result = null; // rol değişince eski sonucu sıfırla
              }),
            ),
            const SizedBox(height: 20),
          ],

          // Generate button
          if (_result == null)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _generating ? null : _generate,
                icon: _generating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 18),
                label: Text(
                  _generating ? 'Sending...' : 'Send Invite',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),

          // Result card
          if (_result != null) ...[
            switch (_result!.type) {
              InviteResultType.linkCreated => _buildLinkResult(colors),
              InviteResultType.existingUserRequestSent => _buildInfoResult(
                  colors,
                  icon: Icons.mark_email_read_outlined,
                  title: 'Request sent',
                  message:
                      '${_result!.email} already has a KMSTRY account. A join request '
                      'was sent — they\'ll get a notification and appear in the team '
                      'list once they accept.',
                ),
              InviteResultType.alreadyMember => _buildInfoResult(
                  colors,
                  icon: Icons.group_rounded,
                  title: 'Already a member',
                  message:
                      '${_result!.email} is already an active member of this venue.',
                ),
              InviteResultType.alreadyInvited => _buildInfoResult(
                  colors,
                  icon: Icons.hourglass_top_rounded,
                  title: 'Invite pending',
                  message:
                      '${_result!.email} already has a pending invite for this venue. '
                      'They just need to accept it.',
                ),
            },
          ],
        ],
      ),
    );
  }

  // Yeni kişi: paylaşılacak kayıt linki
  Widget _buildLinkResult(ColorScheme colors) {
    final r = _result!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: colors.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                'Invite link ready',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            r.inviteUrl ?? '',
            style: TextStyle(
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.6),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${r.email}  ·  Expires in 7 days',
            style: TextStyle(
              fontSize: 11,
              color: colors.onSurface.withValues(alpha: 0.45),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _copyLink,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('Copy Link'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() {
                    _result = null;
                    _emailCtrl.clear();
                  }),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('New'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Bilgi kartı: istek gönderildi / zaten üye / davet bekliyor
  Widget _buildInfoResult(
    ColorScheme colors, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: colors.primary.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              fontSize: 13,
              height: 1.5,
              color: colors.onSurface.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => setState(() {
                _result = null;
                _emailCtrl.clear();
              }),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Send another'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Staff Düzenleme Bottom Sheet ─────────────────────────────────────────────

class _EditStaffSheet extends StatefulWidget {
  final String venueId;
  final VenueMember member;
  final VenueMemberRepository repo;

  const _EditStaffSheet({
    required this.venueId,
    required this.member,
    required this.repo,
  });

  @override
  State<_EditStaffSheet> createState() => _EditStaffSheetState();
}

class _EditStaffSheetState extends State<_EditStaffSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _usernameCtrl;
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl =
        TextEditingController(text: widget.member.user.fullName ?? '');
    _usernameCtrl =
        TextEditingController(text: widget.member.user.username ?? '');
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);

    try {
      await widget.repo.updateStaffUser(
        venueId: widget.venueId,
        memberId: widget.member.id,
        fullName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : null,
        username: _usernameCtrl.text.trim().isNotEmpty
            ? _usernameCtrl.text.trim().toLowerCase()
            : null,
        newPassword: _passwordCtrl.text.isNotEmpty
            ? _passwordCtrl.text
            : null,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to update: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              '${widget.member.user.displayName} — Edit',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: const Icon(Icons.badge_outlined),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().length < 2) {
                        return 'At least 2 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _usernameCtrl,
                    autocorrect: false,
                    decoration: InputDecoration(
                      labelText: 'Username',
                      prefixIcon: const Icon(Icons.alternate_email),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      final x = (v ?? '').trim();
                      if (x.isNotEmpty && x.length < 3) {
                        return 'At least 3 characters';
                      }
                      if (x.isNotEmpty &&
                          !RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(x)) {
                        return 'Only letters, numbers and underscores';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password (optional)',
                      hintText: 'Leave blank to keep current',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                        icon: Icon(_obscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                      ),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      if (v != null &&
                          v.isNotEmpty &&
                          v.length < 6) {
                        return 'At least 6 characters';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Role Select Bottom Sheet ─────────────────────────────────────────────────

class _RoleSelectSheet extends StatelessWidget {
  final List<VenueRole> roles;
  final VenueRole? selected;

  const _RoleSelectSheet({required this.roles, required this.selected});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1322) : colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: colors.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Select Role',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                    color: colors.onSurface)),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: roles.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: colors.outline.withValues(alpha: 0.1)),
            itemBuilder: (_, i) {
              final role = roles[i];
              final isSelected = selected?.id == role.id;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                title: Text(role.name,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? _TeamColors.mavi : colors.onSurface,
                    )),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: _TeamColors.mavi, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, role),
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Venue Role Picker (supports all venue roles) ─────────────────────────────

class _VenueRolePicker extends StatelessWidget {
  final List<VenueRole> roles;
  final VenueRole? selected;
  final ValueChanged<VenueRole> onChanged;

  const _VenueRolePicker({
    required this.roles,
    required this.selected,
    required this.onChanged,
  });

  IconData _iconFor(VenueRole role) {
    switch (role.id) {
      case 'ADMIN':
        return Icons.shield_outlined;
      case 'STAFF':
        return Icons.badge_outlined;
      default:
        return Icons.star_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<VenueRole>(
      value: selected,
      decoration: InputDecoration(
        labelText: 'Role',
        labelStyle: const TextStyle(color: _TeamColors.mavi),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _TeamColors.mavi),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _TeamColors.mavi.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _TeamColors.mavi, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      dropdownColor: null,
      iconEnabledColor: _TeamColors.mavi,
      items: roles.map((role) {
        return DropdownMenuItem<VenueRole>(
          value: role,
          child: Row(
            children: [
              Icon(_iconFor(role), size: 18, color: _TeamColors.mavi),
              const SizedBox(width: 10),
              Text(role.name,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            ],
          ),
        );
      }).toList(),
      onChanged: (r) {
        if (r != null) onChanged(r);
      },
    );
  }
}

// ─── Rol Değiştirme Bottom Sheet ──────────────────────────────────────────────

class _RolePickerSheet extends StatelessWidget {
  final VenueMemberRole current;
  final String? currentVenueRoleId;
  final List<VenueRole> roles;

  const _RolePickerSheet({
    required this.current,
    required this.currentVenueRoleId,
    required this.roles,
  });

  bool _isCurrent(VenueRole role) {
    if (role.id == 'ADMIN') return current == VenueMemberRole.admin && currentVenueRoleId == null;
    if (role.id == 'STAFF') return current == VenueMemberRole.staff && currentVenueRoleId == null;
    return currentVenueRoleId == role.id;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Change Role',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (roles.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'No roles available.',
                  style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.5)),
                ),
              ),
            )
          else
            ...roles.map((role) {
              final isCurrent = _isCurrent(role);
              final isSystem = role.id == 'ADMIN' || role.id == 'STAFF';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _TeamColors.mavi.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _TeamColors.mavi,
                    ),
                  ),
                ),
                title: Text(
                  role.name,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  isSystem
                      ? (role.id == 'ADMIN'
                          ? 'System role · Full access'
                          : 'System role · Limited access')
                      : 'Custom role',
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                trailing: isCurrent
                    ? const Icon(Icons.check_circle, color: _TeamColors.mavi, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, role),
              );
            }),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
