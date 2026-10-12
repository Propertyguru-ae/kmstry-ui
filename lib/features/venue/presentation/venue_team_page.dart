import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/performance/performance_diagnostics.dart';
import 'package:kmstry_frontend/core/venue/visible_venue_read.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'venue_permissions_page.dart';

/// Plan koltuk sınırına takılan ekleme / davet denemesi.
bool _isSeatLimitError(Object error) =>
    error is ApiException && error.data['error'] == 'PLAN_MEMBER_LIMIT_REACHED';

/// Koltuk dolu: standart popup + yükseltme seçeneği.
Future<void> _showSeatLimitPopup(BuildContext context, Object error) async {
  final limit = error is ApiException ? error.data['limit'] : null;
  final message = limit is num
      ? 'Your plan allows up to ${limit.toInt()} team ${limit == 1 ? 'account' : 'accounts'}, including pending invites. Upgrade your plan or cancel a pending invite to add someone new.'
      : 'Your plan has no free team seats, including pending invites. Upgrade your plan or cancel a pending invite to add someone new.';
  final upgrade = await showPremiumPromptDialog(
    context,
    icon: Icons.lock_outline_rounded,
    title: 'No seats left',
    message: message,
    confirmLabel: 'Upgrade',
    cancelLabel: 'Not now',
  );
  if (upgrade && context.mounted) await PlanGate.openPaywall(context);
}

class VenueTeamPage extends StatefulWidget {
  final String venueId;

  /// Caller's role; management also requires the current venue permissions.
  final VenueMemberRole callerRole;

  const VenueTeamPage({
    super.key,
    required this.venueId,
    required this.callerRole,
    this.repository,
    this.inviteRepository,
  });
  final VenueMemberRepository? repository;
  final VenueInviteRepository? inviteRepository;

  @override
  State<VenueTeamPage> createState() => _VenueTeamPageState();
}

class _VenueTeamPageState extends State<VenueTeamPage> {
  late final _repo = widget.repository ?? VenueMemberRepository();
  late final _inviteRepo = widget.inviteRepository ?? VenueInviteRepository();
  int _revision = 0;
  bool _hasMembers = false;
  late final _read = VisibleVenueRead(
    isVisible: () => mounted,
    read: () => PerformanceDiagnostics.pageLoad(
      PerformancePage.team,
      _readTeam,
      isMounted: () => mounted,
    ),
  );

  bool _loading = true;
  String? _error;
  List<VenueMember> _members = [];
  int? _roleCount;

  /// Hesabı olmayan e-postalara gönderilmiş, henüz kullanılmamış davet linkleri.
  List<CreatedInvite> _linkInvites = [];

  bool _pendingExpanded = true;
  bool _pastExpanded = false;

  bool get _isOwner => widget.callerRole == VenueMemberRole.owner;
  bool get _canManage =>
      _isOwner || VenueSession.instance.can(VenuePermission.memberManage);
  bool get _canManageRoles =>
      _isOwner || VenueSession.instance.can(VenuePermission.roleManage);
  bool get _canSeePending => _canManage;
  bool get _canAccessPermissions =>
      _isOwner || VenueSession.instance.can(VenuePermission.roleManage);

  bool _canManageMember(VenueMember member) =>
      _canManage &&
      member.isActive &&
      member.isSelf == false &&
      member.role != VenueMemberRole.owner;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VenueTeamPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.venueId != oldWidget.venueId ||
        widget.callerRole != oldWidget.callerRole) {
      _revision++;
      _members = [];
      _roleCount = null;
      _linkInvites = [];
      _hasMembers = false;
      _read.reset();
      _load();
    }
  }

  @override
  void dispose() {
    _revision++;
    _read.dispose();
    super.dispose();
  }

  Future<void> _load() => _read.invalidate();

  Future<bool> _readTeam() async {
    final revision = ++_revision;
    final venueId = widget.venueId;
    final session = PendingPublicMediaService.instance.sessionGeneration;
    bool denied = false;
    bool current() =>
        mounted &&
        revision == _revision &&
        venueId == widget.venueId &&
        PendingPublicMediaService.instance.isCurrentSession(session);
    void failed(Object error) {
      if (!current()) return;
      denied =
          denied ||
          (error is ApiException && [401, 403, 404].contains(error.statusCode));
      setState(() {
        if (denied) {
          _members = [];
          _roleCount = null;
          _linkInvites = [];
          _hasMembers = false;
        }
        _loading = false;
        _error = 'Failed to load team.';
      });
    }

    setState(() {
      _loading = !_hasMembers;
      _error = null;
    });
    // Link davetleri ek bilgi: ekip listesini bekletmez, alınamazsa liste
    // yine açılır.
    if (_canSeePending) {
      unawaited(
        _inviteRepo
            .listInvites(venueId)
            .then((invites) {
              if (current() && !denied) {
                setState(() => _linkInvites = invites);
              }
            })
            .catchError((Object _) {}),
      );
    }
    final results = await Future.wait([
      () async {
        try {
          final members = await _repo.getMembers(venueId);
          if (!current() || denied) return false;
          setState(() {
            _members = members;
            _hasMembers = true;
            _loading = false;
          });
          return true;
        } catch (error) {
          failed(error);
          return false;
        }
      }(),
      () async {
        try {
          final roles = await _repo.getRoles(venueId);
          if (!current() || denied) return false;
          setState(() => _roleCount = roles.length);
          return true;
        } catch (error) {
          failed(error);
          return false;
        }
      }(),
    ]);
    return results.every((success) => success);
  }

  Future<void> _cleanPastInvites() async {
    final confirmed = await showPremiumPromptDialog(
      context,
      icon: Icons.cleaning_services_rounded,
      title: 'Clear past invites?',
      message:
          'Declined, cancelled and expired invites will be removed from this list.',
      confirmLabel: 'Clear',
      cancelLabel: 'Cancel',
    );
    if (!confirmed || !mounted) return;
    try {
      await _repo.cleanPastInvites(widget.venueId);
      _load();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        message: 'Could not clear past invites. Please try again.',
      );
    }
  }

  Future<void> _openAddMember() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VenueAddMemberPage(venueId: widget.venueId, repo: _repo),
      ),
    );
    // Davet gönderilip geri dönüldüğünde de bekleyen davet listede görünsün.
    if (mounted) _load();
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
    if (mounted) await _load();
  }

  Future<void> _changeRole(VenueMember member) async {
    if (!_canManageMember(member)) return;
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
    final customId = (picked.id != 'ADMIN' && picked.id != 'STAFF')
        ? picked.id
        : null;

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
      builder: (_) =>
          _EditStaffSheet(venueId: widget.venueId, member: member, repo: _repo),
    );
    if (edited == true) _load();
  }

  Future<void> _cancelInvite(VenueMember member) async {
    final confirmed = await showPremiumPromptDialog(
      context,
      icon: Icons.cancel_schedule_send_rounded,
      title: 'Cancel invite?',
      message:
          'The pending invite for ${member.user.displayName} will be cancelled. You can invite them again later.',
      confirmLabel: 'Cancel invite',
      cancelLabel: 'Keep invite',
    );
    if (!confirmed || !mounted) return;
    try {
      await _repo.cancelMemberInvite(widget.venueId, member.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        message: 'Could not cancel the invite. Please try again.',
      );
    }
  }

  Future<void> _resendInvite(VenueMember member) async {
    final name = member.user.displayName;
    final confirmed = await showPremiumPromptDialog(
      context,
      icon: Icons.send_rounded,
      title: 'Resend invite?',
      message: '$name will get a new invite to join your team.',
      confirmLabel: 'Resend',
      cancelLabel: 'Cancel',
    );
    if (!confirmed || !mounted) return;

    try {
      await _repo.addMember(widget.venueId, member.user.id, member.role);
      if (!mounted) return;
      await showPremiumPromptDialog(
        context,
        icon: Icons.mark_email_read_rounded,
        title: 'Invite sent',
        message:
            '$name will get a notification and join your team once they accept.',
        confirmLabel: 'Done',
        showCancel: false,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      if (_isSeatLimitError(e)) {
        await _showSeatLimitPopup(context, e);
        return;
      }
      showErrorToast(
        context,
        message: 'Could not resend the invite. Please try again.',
      );
    }
  }

  Future<void> _removeMember(VenueMember member) async {
    if (!_canManageMember(member)) return;
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
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          _canManage || _canManageRoles ? 'Team Management' : 'Team',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        centerTitle: true,
        actions: const [],
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
          Icon(
            Icons.error_outline,
            size: 48,
            color: colors.onSurface.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme colors, bool isDark) {
    final activeMembers = _members
        .where((m) => m.status == VenueMemberStatus.active)
        .toList();
    final pendingMembers = _members
        .where((m) => m.status == VenueMemberStatus.pending)
        .toList();
    final terminalMembers = _members.where((m) => m.status.isTerminal).toList();
    final linkInvites = _canSeePending ? _linkInvites : const <CreatedInvite>[];
    final pendingCount = pendingMembers.length + linkInvites.length;
    // Free plan tek operatörlü — rol hiyerarşisi yok, sadece owner sayılır.
    final roleCount = VenueSession.instance.hasFeature(VenueFeature.roleLevels)
        ? _roleCount
        : 1;

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
                    Icon(
                      Icons.group_outlined,
                      size: 52,
                      color: colors.onSurface.withValues(alpha: 0.3),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No team members yet.',
                      style: TextStyle(
                        fontSize: 16,
                        color: colors.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    if (_canManage) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Use "Add Member" to invite staff.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
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
                  pending: pendingCount,
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
                  ...activeMembers.map(
                    (m) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildMemberCard(m, colors, isDark),
                    ),
                  ),
                ],

                // ── Pending invites (collapsible) ────────────────────────
                if (_canSeePending) ...[
                  const SizedBox(height: 16),
                  _CollapsibleSection(
                    label: 'Pending Invites',
                    count: pendingCount,
                    badgeColor: _TeamColors.turuncu,
                    expanded: _pendingExpanded,
                    colors: colors,
                    isDark: isDark,
                    onToggle: () =>
                        setState(() => _pendingExpanded = !_pendingExpanded),
                    emptyText: 'No pending invites',
                    children: [
                      ...pendingMembers.map(
                        (m) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildPendingCard(m, colors, isDark),
                        ),
                      ),
                      ...linkInvites.map(
                        (invite) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _buildLinkInviteCard(invite, colors, isDark),
                        ),
                      ),
                    ],
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
                    onToggle: () =>
                        setState(() => _pastExpanded = !_pastExpanded),
                    emptyText: 'No past invites',
                    trailing: terminalMembers.isNotEmpty
                        ? TextButton.icon(
                            onPressed: _cleanPastInvites,
                            icon: const Icon(
                              Icons.delete_sweep_outlined,
                              size: 16,
                            ),
                            label: const Text('Clean'),
                            style: TextButton.styleFrom(
                              foregroundColor: colors.error,
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                          )
                        : null,
                    children: terminalMembers
                        .map(
                          (m) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildTerminalCard(m, colors, isDark),
                          ),
                        )
                        .toList(),
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
    // Koltuğu dolduranlar: aktif + bekleyen üyeler (owner dahil) ve bekleyen
    // davet linkleri — backend de aynı şekilde sayar.
    final used =
        _members
            .where(
              (m) =>
                  m.status == VenueMemberStatus.active ||
                  m.status == VenueMemberStatus.pending,
            )
            .length +
        (_canSeePending ? _linkInvites.length : 0);
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
                Icon(
                  Icons.groups_outlined,
                  size: 15,
                  color: colors.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 6),
                // Büyük yazı boyutunda taşmasın, gerekirse alt satıra geçsin.
                Flexible(
                  child: Text(
                    limit == null
                        ? '$used staff · ${plan.label} plan (unlimited)'
                        : '$used / $limit ${limit == 1 ? 'seat' : 'seats'} used · ${plan.label} plan',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: plan.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            )
          else
            PrimaryButton(label: 'Add Member', onPressed: _openAddMember),
        ],
      ),
    );
  }

  Widget _buildMemberCard(VenueMember member, ColorScheme colors, bool isDark) {
    final canManage = _canManageMember(member);
    final isStaffAccount =
        member.user.isStaff && member.user.staffVenueId == widget.venueId;
    final roleLabel = (member.venueRoleName ?? member.role.label).toUpperCase();
    final roleColor = _TeamColors.forRole(member.role, member.venueRoleName);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1322) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colors.outline.withValues(alpha: isDark ? 0.10 : 0.12),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _TeamAvatar(
            displayName: member.user.displayName,
            photo: member.user.photo,
            color: roleColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: roleColor,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.user.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (member.user.username != null)
                  Text(
                    '@${member.user.username}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
              ],
            ),
          ),
          if (canManage)
            PopupMenuButton<String>(
              key: ValueKey('team-member-actions-${member.id}'),
              tooltip: 'Member options',
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: colors.onSurface.withValues(alpha: 0.45),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (_) => [
                if (isStaffAccount && _isOwner)
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 10),
                        Text('Edit'),
                      ],
                    ),
                  ),
                const PopupMenuItem(
                  value: 'role',
                  child: Row(
                    children: [
                      Icon(Icons.manage_accounts_outlined, size: 18),
                      SizedBox(width: 10),
                      Text('Change Role'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(
                        isStaffAccount
                            ? Icons.delete_outline
                            : Icons.person_remove_outlined,
                        size: 18,
                        color: Colors.red,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isStaffAccount ? 'Delete' : 'Remove',
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
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

  Widget _buildPendingCard(
    VenueMember member,
    ColorScheme colors,
    bool isDark,
  ) {
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
          _TeamAvatar(
            displayName: member.user.displayName,
            photo: member.user.photo,
            color: roleColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: roleColor,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  member.user.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                if (member.user.username != null)
                  Text(
                    '@${member.user.username}',
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                // Uygulama içi istek: link yok, kişi bildirimden kabul eder.
                Text(
                  'In-app request',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_canManage)
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                      value: 'cancel',
                      child: Row(
                        children: [
                          Icon(
                            Icons.cancel_outlined,
                            size: 18,
                            color: _TeamColors.turuncu,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Cancel Invite',
                            style: TextStyle(color: _TeamColors.turuncu),
                          ),
                        ],
                      ),
                    ),
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

  // Hesabı olmayan e-postaya gönderilmiş davet linki: linki tekrar kopyala
  // ya da iptal et.
  Widget _buildLinkInviteCard(
    CreatedInvite invite,
    ColorScheme colors,
    bool isDark,
  ) {
    final role = invite.role.toUpperCase() == 'ADMIN'
        ? VenueMemberRole.admin
        : VenueMemberRole.staff;
    final roleLabel = (invite.venueRoleName ?? role.label).toUpperCase();
    final roleColor = _TeamColors.forRole(role, invite.venueRoleName);
    final email = invite.email ?? 'Invite link';

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1322) : colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _TeamColors.turuncu.withValues(alpha: 0.25)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          _TeamAvatar(displayName: email, photo: null, color: roleColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  roleLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: roleColor,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colors.onSurface,
                  ),
                ),
                Text(
                  'Invite link · ${_expiryLabel(invite.expiresAt)}',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          if (_canManage)
            PopupMenuButton<String>(
              tooltip: 'Invite options',
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: colors.onSurface.withValues(alpha: 0.55),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'copy',
                  child: Row(
                    children: [
                      Icon(
                        Icons.copy_rounded,
                        size: 18,
                        color: _TeamColors.accent(isDark),
                      ),
                      const SizedBox(width: 10),
                      const Text('Copy link'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'cancel',
                  child: Row(
                    children: [
                      Icon(
                        Icons.cancel_outlined,
                        size: 18,
                        color: _TeamColors.turuncu,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Cancel invite',
                        style: TextStyle(color: _TeamColors.turuncu),
                      ),
                    ],
                  ),
                ),
              ],
              onSelected: (action) {
                if (action == 'copy') _copyInviteLink(invite);
                if (action == 'cancel') _revokeLinkInvite(invite);
              },
            ),
        ],
      ),
    );
  }

  String _expiryLabel(String expiresAt) {
    final expires = DateTime.tryParse(expiresAt);
    if (expires == null) return 'pending';
    final days = expires.difference(DateTime.now()).inHours / 24;
    if (days < 1) return 'expires today';
    final whole = days.ceil();
    return 'expires in $whole ${whole == 1 ? 'day' : 'days'}';
  }

  void _copyInviteLink(CreatedInvite invite) {
    if (invite.inviteUrl.isEmpty) return;
    Clipboard.setData(ClipboardData(text: invite.inviteUrl));
    showSuccessSnackBar(context, message: 'Link copied');
  }

  Future<void> _revokeLinkInvite(CreatedInvite invite) async {
    final who = invite.email ?? 'this person';
    final confirmed = await showPremiumPromptDialog(
      context,
      icon: Icons.cancel_schedule_send_rounded,
      title: 'Cancel invite?',
      message:
          'The invite link for $who will stop working. You can invite them again later.',
      confirmLabel: 'Cancel invite',
      cancelLabel: 'Keep invite',
    );
    if (!confirmed || !mounted) return;
    try {
      await _inviteRepo.revokeInvite(widget.venueId, invite.id);
      await _load();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        message: 'Could not cancel the invite. Please try again.',
      );
    }
  }

  Widget _buildTerminalCard(
    VenueMember member,
    ColorScheme colors,
    bool isDark,
  ) {
    Color statusColor;
    switch (member.status) {
      case VenueMemberStatus.rejected:
        statusColor = Colors.red;
      case VenueMemberStatus.expired:
        statusColor = colors.onSurface.withValues(alpha: 0.4);
      case VenueMemberStatus.cancelled:
        statusColor = _TeamColors.turuncu;
      default:
        statusColor = colors.onSurface.withValues(alpha: 0.4);
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
            _TeamAvatar(
              displayName: member.user.displayName,
              photo: member.user.photo,
              color: roleColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.user.displayName,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: colors.onSurface,
                    ),
                  ),
                  if (member.user.username != null)
                    Text(
                      '@${member.user.username}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                ],
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    member.status.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
                if (_canManage)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_vert,
                      size: 20,
                      color: colors.onSurface.withValues(alpha: 0.4),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                        value: 'resend',
                        child: Row(
                          children: [
                            Icon(Icons.send_outlined, size: 18),
                            SizedBox(width: 10),
                            Text('Re-invite'),
                          ],
                        ),
                      ),
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
  /// Butonlarla aynı mavi; yazı/ikon olarak kullanılırken zeminde okunur ton.
  static Color accent(bool isDark) =>
      isDark ? AppColors.blueDark : AppColors.blueLight;

  static const magenta = Color(0xFFE020D8);
  static const turkuaz = Color(0xFF1FD9A8);
  static const mavi = Color(0xFF1A9FE8);
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
  final int? roles;
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
        _StatCard(
          value: '$active',
          label: 'Active',
          color: _TeamColors.turkuaz,
          bg: bg,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: '$pending',
          label: 'Pending',
          color: _TeamColors.turuncu,
          bg: bg,
        ),
        const SizedBox(width: 10),
        _StatCard(
          value: roles?.toString() ?? '—',
          label: 'Roles',
          color: _TeamColors.magenta,
          bg: bg,
          onTap: onRolesTap,
        ),
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

  const _StatCard({
    required this.value,
    required this.label,
    required this.color,
    required this.bg,
    this.onTap,
  });

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
              Text(
                value,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                  if (onTap != null) ...[
                    const SizedBox(width: 3),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 13,
                      color: colors.onSurface.withValues(alpha: 0.35),
                    ),
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
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: colors.onSurface.withValues(alpha: 0.45),
          ),
        ),
        const Spacer(),
        if (badge != null && badgeLabel != null)
          Text(
            badgeLabel!,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: badgeColor ?? colors.onSurface.withValues(alpha: 0.5),
            ),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: colors.onSurface.withValues(alpha: 0.45),
                  ),
                ),
                const SizedBox(width: 8),
                if (count > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: badgeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeColor,
                      ),
                    ),
                  ),
                const Spacer(),
                if (trailing != null) trailing!,
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 220),
          crossFadeState: expanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: count == 0
                ? [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        emptyText,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
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

  const _TeamAvatar({
    required this.displayName,
    required this.photo,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initial = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';

    if (photo != null && photo!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          photo!,
          width: 46,
          height: 46,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              _InitialAvatar(initial: initial, color: color, isDark: isDark),
        ),
      );
    }
    return _InitialAvatar(initial: initial, color: color, isDark: isDark);
  }
}

class _InitialAvatar extends StatelessWidget {
  final String initial;
  final Color color;
  final bool isDark;

  const _InitialAvatar({
    required this.initial,
    required this.color,
    required this.isDark,
  });

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
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ─── Üye Ekleme Bottom Sheet (iki sekme) ─────────────────────────────────────

// ─── Add Member Page ──────────────────────────────────────────────────────────

class VenueAddMemberPage extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;
  final VenueInviteRepository? inviteRepository;

  const VenueAddMemberPage({
    super.key,
    required this.venueId,
    required this.repo,
    this.inviteRepository,
  });

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
    final bg = theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      // Uygulamanın standart sayfa başlığı (Team Management ile aynı).
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          'Add Member',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
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
                ? _InviteLinkTab(
                    venueId: widget.venueId,
                    venueRoles: const [],
                    memberRepo: widget.repo,
                    inviteRepo: widget.inviteRepository,
                  )
                : _UsernameSearchTab(
                    venueId: widget.venueId,
                    repo: widget.repo,
                  ),
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
    final accent = _TeamColors.accent(isDark);
    final inactive = colors.onSurface.withValues(alpha: 0.6);

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          _ToggleTab(
            label: 'Find by Username',
            icon: Icons.person_search_outlined,
            isActive: !showInviteLink,
            activeBg: activeBg,
            activeColor: accent,
            inactiveColor: inactive,
            onTap: () => onChanged(false),
          ),
          _ToggleTab(
            label: 'Invite Link',
            icon: Icons.link_rounded,
            isActive: showInviteLink,
            activeBg: activeBg,
            activeColor: accent,
            inactiveColor: inactive,
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
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isActive ? activeColor : inactiveColor,
              ),
              const SizedBox(width: 6),
              // Büyük yazı boyutunda sekmeden taşmasın.
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: isActive ? activeColor : inactiveColor,
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
            ? filtered.firstWhere(
                (r) => r.id == 'ADMIN',
                orElse: () => filtered.first,
              )
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
      setState(() {
        _results = r;
        _searching = false;
      });
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
      final enumRole = role.id == 'ADMIN'
          ? VenueMemberRole.admin
          : VenueMemberRole.staff;
      final customId = (role.id != 'ADMIN' && role.id != 'STAFF')
          ? role.id
          : null;
      await widget.repo.addMember(
        widget.venueId,
        user.id,
        enumRole,
        venueRoleId: customId,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _adding = false);
      if (_isSeatLimitError(e)) {
        await _showSeatLimitPopup(context, e);
        return;
      }
      showErrorToast(
        context,
        message: 'Could not add this member. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final accent = _TeamColors.accent(isDark);

    if (_loadingRoles) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
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
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: AppColors.blue,
                              ),
                            ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: colors.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.blue,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),

                // ── Search results ──────────────────────────────
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0F1520) : colors.surface,
                      border: Border.all(
                        color: colors.outline.withValues(alpha: 0.18),
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemCount: _results.length,
                      separatorBuilder: (_, __) => Divider(
                        height: 1,
                        color: colors.outline.withValues(alpha: 0.12),
                      ),
                      itemBuilder: (_, i) {
                        final u = _results[i];
                        return ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 2,
                          ),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.blue.withValues(
                              alpha: 0.14,
                            ),
                            backgroundImage:
                                u.photo != null && u.photo!.isNotEmpty
                                ? NetworkImage(u.photo!)
                                : null,
                            child: u.photo == null || u.photo!.isEmpty
                                ? Text(
                                    u.displayName.isNotEmpty
                                        ? u.displayName[0].toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      color: accent,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  )
                                : null,
                          ),
                          title: Text(
                            u.displayName,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: u.username != null
                              ? Text(
                                  '@${u.username}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: colors.onSurface.withValues(
                                      alpha: 0.6,
                                    ),
                                  ),
                                )
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
                  Text(
                    'Selected User',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.blue.withValues(alpha: 0.08),
                      border: Border.all(
                        color: AppColors.blue.withValues(alpha: 0.35),
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.blue.withValues(
                            alpha: 0.18,
                          ),
                          backgroundImage:
                              _selected!.photo != null &&
                                  _selected!.photo!.isNotEmpty
                              ? NetworkImage(_selected!.photo!)
                              : null,
                          child:
                              _selected!.photo == null ||
                                  _selected!.photo!.isEmpty
                              ? Text(
                                  _selected!.displayName.isNotEmpty
                                      ? _selected!.displayName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    color: accent,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _selected!.displayName,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: colors.onSurface,
                                ),
                              ),
                              if (_selected!.username != null)
                                Text(
                                  '@${_selected!.username}',
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
                        GestureDetector(
                          onTap: () => setState(() => _selected = null),
                          child: Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: colors.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                // ── Role selector ───────────────────────────────
                if (_roles.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Role',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _roleDropdownOpen = !_roleDropdownOpen),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 15,
                      ),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F1520)
                            : colors.surface,
                        border: Border.all(
                          color: _roleDropdownOpen
                              ? _TeamColors.mavi
                              : _TeamColors.mavi.withValues(alpha: 0.4),
                          width: _roleDropdownOpen ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.only(
                          topLeft: const Radius.circular(12),
                          topRight: const Radius.circular(12),
                          bottomLeft: Radius.circular(
                            _roleDropdownOpen ? 0 : 12,
                          ),
                          bottomRight: Radius.circular(
                            _roleDropdownOpen ? 0 : 12,
                          ),
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
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: _TeamColors.mavi.withValues(alpha: 0.8),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_roleDropdownOpen)
                    Container(
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0F1520)
                            : colors.surface,
                        border: Border(
                          left: BorderSide(color: _TeamColors.mavi, width: 1.5),
                          right: BorderSide(
                            color: _TeamColors.mavi,
                            width: 1.5,
                          ),
                          bottom: BorderSide(
                            color: _TeamColors.mavi,
                            width: 1.5,
                          ),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? _TeamColors.mavi.withValues(alpha: 0.12)
                                    : Colors.transparent,
                                border: role != _roles.last
                                    ? Border(
                                        bottom: BorderSide(
                                          color: _TeamColors.mavi.withValues(
                                            alpha: 0.15,
                                          ),
                                        ),
                                      )
                                    : null,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      role.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? accent
                                            : colors.onSurface.withValues(
                                                alpha: 0.85,
                                              ),
                                      ),
                                    ),
                                  ),
                                  if (isSelected)
                                    Icon(
                                      Icons.check_rounded,
                                      color: accent,
                                      size: 18,
                                    ),
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
              child: PrimaryButton(
                label: _selected == null
                    ? 'Select a user first'
                    : 'Add as ${_selectedRole?.name ?? 'Member'}',
                loading: _adding,
                onPressed: _selected == null ? null : _add,
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
    widget.repo
        .getRoles(widget.venueId)
        .then((roles) {
          if (mounted) setState(() => _roles = roles);
        })
        .catchError((_) {
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
              width: 40,
              height: 4,
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
                width: 40,
                height: 4,
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
  final VenueMemberRepository? memberRepo;
  final VenueInviteRepository? inviteRepo;

  const _InviteLinkTab({
    required this.venueId,
    required this.venueRoles,
    this.memberRepo,
    this.inviteRepo,
  });

  @override
  State<_InviteLinkTab> createState() => _InviteLinkTabState();
}

class _InviteLinkTabState extends State<_InviteLinkTab> {
  /// Davet linki sonucu yalnızca popup'ta gösterilir; sayfadaki kart şimdilik
  /// kapalı (popup ile aynı bilgiyi tekrarlıyordu).
  static const _showInlineLinkCard = false;

  late final VenueInviteRepository _inviteRepo =
      widget.inviteRepo ?? VenueInviteRepository();
  late final VenueMemberRepository _memberRepo =
      widget.memberRepo ?? VenueMemberRepository();
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
      _setAssignableRoles(widget.venueRoles);
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
        _setAssignableRoles(roles);
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

  void _setAssignableRoles(List<VenueRole> roles) {
    _roles = roles.where((r) => !r.isOwnerRole && r.id != 'OWNER').toList();
    _selectedRole = _roles.isEmpty
        ? null
        : _roles.firstWhere((r) => r.id == 'STAFF', orElse: () => _roles.last);
  }

  Future<void> _generate() async {
    final role = _selectedRole;
    if (role == null || role.isOwnerRole || role.id == 'OWNER' || _generating) {
      return;
    }

    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      showErrorToast(context, message: 'Please enter a valid email address.');
      return;
    }

    setState(() => _generating = true);
    try {
      final enumRole = role.id == 'ADMIN'
          ? VenueMemberRole.admin
          : VenueMemberRole.staff;
      final customId = (role.id != 'ADMIN' && role.id != 'STAFF')
          ? role.id
          : null;

      final result = await _inviteRepo.createInvite(
        venueId: widget.venueId,
        email: email,
        role: enumRole,
        venueRoleId: customId,
      );
      if (!mounted) return;
      setState(() => _generating = false);
      await _showResult(result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      if (_isSeatLimitError(e)) {
        await _showSeatLimitPopup(context, e);
        return;
      }
      showErrorToast(
        context,
        message: 'Could not send the invite. Please try again.',
      );
    }
  }

  /// Davet gönderildikten sonra sonucu uygulamanın standart popup'ında gösterir.
  Future<void> _showResult(InviteResult result) async {
    if (result.type == InviteResultType.linkCreated) {
      final url = result.inviteUrl ?? '';
      final copy = await showPremiumPromptDialog(
        context,
        icon: Icons.link_rounded,
        title: 'Invite link ready',
        message:
            "${result.email} doesn't have a KMSTRY account yet. Share this link with them. It expires in 7 days.",
        content: _InviteLinkBox(url: url),
        confirmLabel: 'Copy link',
        confirmIcon: Icons.copy_rounded,
        cancelLabel: 'Done',
      );
      if (!mounted) return;
      if (copy) _copyLink(url);
      // Sayfadaki link kartı şimdilik gizli: sonuç yalnızca popup'ta. Kopyalanmadan
      // kapatılırsa aynı e-postaya tekrar gönderilebilir; backend yeni link üretir.
      setState(() {
        _result = _showInlineLinkCard ? result : null;
        if (!_showInlineLinkCard) _emailCtrl.clear();
      });
      return;
    }

    final (icon, title, message) = switch (result.type) {
      InviteResultType.existingUserRequestSent => (
        Icons.mark_email_read_rounded,
        'Request sent',
        "${result.email} already has a KMSTRY account. They'll get a notification and join your team once they accept.",
      ),
      InviteResultType.alreadyMember => (
        Icons.group_rounded,
        'Already a member',
        '${result.email} is already an active member of this venue.',
      ),
      _ => (
        Icons.hourglass_top_rounded,
        'Invite pending',
        '${result.email} already has a pending invite for this venue. They just need to accept it.',
      ),
    };
    await showPremiumPromptDialog(
      context,
      icon: icon,
      title: title,
      message: message,
      confirmLabel: 'Done',
      showCancel: false,
    );
    if (!mounted) return;
    // Yeni bir davet için formu sıfırla.
    setState(() {
      _result = null;
      _emailCtrl.clear();
    });
  }

  void _copyLink([String? link]) {
    final url = link ?? _result?.inviteUrl;
    if (url == null || url.isEmpty) return;
    Clipboard.setData(ClipboardData(text: url));
    showSuccessSnackBar(context, message: 'Link copied');
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _TeamColors.accent(
      Theme.of(context).brightness == Brightness.dark,
    );

    if (_loadingRoles) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.blue),
      );
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
              color: AppColors.blue.withValues(alpha: 0.08),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.22)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline, size: 18, color: accent),
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
              child: PrimaryButton(
                label: 'Send Invite',
                loading: _generating,
                onPressed: _generate,
              ),
            ),

          // Link sonucu kartı (şimdilik gizli, bkz. _showInlineLinkCard).
          if (_showInlineLinkCard &&
              _result?.type == InviteResultType.linkCreated)
            _buildLinkResult(colors, accent),
        ],
      ),
    );
  }

  // Yeni kişi: paylaşılacak kayıt linki
  Widget _buildLinkResult(ColorScheme colors, Color accent) {
    final r = _result!;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.blue.withValues(alpha: 0.35),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Invite link ready',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: accent,
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
              fontSize: 11.5,
              color: colors.onSurface.withValues(alpha: 0.6),
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
                    backgroundColor: AppColors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
                    foregroundColor: accent,
                    side: BorderSide(
                      color: AppColors.blue.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
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
}

/// Davet popup'ında paylaşılacak link; uzun linkler kutu içinde kırılır.
class _InviteLinkBox extends StatelessWidget {
  const _InviteLinkBox({required this.url});
  final String url;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFF5F7FA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 18, color: _TeamColors.accent(isDark)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              url,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
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
    _nameCtrl = TextEditingController(text: widget.member.user.fullName ?? '');
    _usernameCtrl = TextEditingController(
      text: widget.member.user.username ?? '',
    );
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
        newPassword: _passwordCtrl.text.isNotEmpty ? _passwordCtrl.text : null,
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) {
                      final x = (v ?? '').trim();
                      if (x.isNotEmpty && x.length < 3) {
                        return 'At least 3 characters';
                      }
                      if (x.isNotEmpty &&
                          !RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(x)) {
                        return 'Only letters, numbers, dots and underscores';
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
                        onPressed: () => setState(() => _obscure = !_obscure),
                        icon: Icon(
                          _obscure ? Icons.visibility_off : Icons.visibility,
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) {
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
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Save',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
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
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.outline.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Select Role',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: roles.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: colors.outline.withValues(alpha: 0.1),
            ),
            itemBuilder: (_, i) {
              final role = roles[i];
              final isSelected = selected?.id == role.id;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                title: Text(
                  role.name,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? _TeamColors.mavi : colors.onSurface,
                  ),
                ),
                trailing: isSelected
                    ? const Icon(
                        Icons.check_rounded,
                        color: _TeamColors.mavi,
                        size: 20,
                      )
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
        labelStyle: TextStyle(
          color: _TeamColors.accent(
            Theme.of(context).brightness == Brightness.dark,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _TeamColors.mavi),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: _TeamColors.mavi.withValues(alpha: 0.4),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _TeamColors.mavi, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
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
              Text(
                role.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
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
    if (role.id == 'ADMIN')
      return current == VenueMemberRole.admin && currentVenueRoleId == null;
    if (role.id == 'STAFF')
      return current == VenueMemberRole.staff && currentVenueRoleId == null;
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
                    color: colors.onSurface.withValues(alpha: 0.5),
                  ),
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
                    ? const Icon(
                        Icons.check_circle,
                        color: _TeamColors.mavi,
                        size: 20,
                      )
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
