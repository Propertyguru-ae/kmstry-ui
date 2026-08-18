import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/venue/plan_gate.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

// ─── Brand colors ─────────────────────────────────────────────────────────────

class _PC {
  static const magenta = Color(0xFFE020D8);
  static const turkuaz = Color(0xFF1FD9A8);
  static const mavi    = Color(0xFF1A9FE8);
  static const turuncu = Color(0xFFF08838);

  static Color forRole(VenueRole role) {
    if (role.isOwnerRole)  return magenta;
    if (role.id == 'ADMIN') return turkuaz;
    if (role.id == 'STAFF') return mavi;
    return turuncu;
  }
}

// ─── Permission meta ──────────────────────────────────────────────────────────

class _PermMeta {
  final IconData icon;
  final Color color;
  const _PermMeta(this.icon, this.color);
}

const _permMeta = <VenuePermission, _PermMeta>{
  VenuePermission.eventManage:   _PermMeta(Icons.event_outlined,         _PC.turkuaz),
  VenuePermission.eventAttendeesView: _PermMeta(Icons.groups_outlined,    _PC.mavi),
  VenuePermission.storyManage:     _PermMeta(Icons.auto_stories_outlined,  _PC.turkuaz),
  VenuePermission.postCreate:    _PermMeta(Icons.edit_outlined,          _PC.mavi),
  VenuePermission.venueEdit:     _PermMeta(Icons.tune_outlined,          _PC.mavi),
  VenuePermission.viewGuests:    _PermMeta(Icons.people_outline,         _PC.mavi),
  VenuePermission.reportGuest:   _PermMeta(Icons.flag_outlined,          _PC.turuncu),
  VenuePermission.blockGuest:    _PermMeta(Icons.block_outlined,         _PC.turuncu),
  VenuePermission.sendPush:      _PermMeta(Icons.campaign_outlined,      _PC.turkuaz),
  VenuePermission.viewStats:     _PermMeta(Icons.bar_chart_outlined,     _PC.mavi),
  VenuePermission.viewAnalytics: _PermMeta(Icons.insights_outlined,      _PC.mavi),
  VenuePermission.memberManage:  _PermMeta(Icons.manage_accounts_outlined, _PC.magenta),
  VenuePermission.roleManage:    _PermMeta(Icons.shield_outlined,        _PC.magenta),
  VenuePermission.partnershipManage: _PermMeta(Icons.handshake_outlined,  _PC.turkuaz),
};

// ─── Page ─────────────────────────────────────────────────────────────────────

class VenuePermissionsPage extends StatefulWidget {
  final String venueId;
  final VenueMemberRole callerRole;

  const VenuePermissionsPage({
    super.key,
    required this.venueId,
    this.callerRole = VenueMemberRole.owner,
  });

  @override
  State<VenuePermissionsPage> createState() => _VenuePermissionsPageState();
}

class _VenuePermissionsPageState extends State<VenuePermissionsPage> {
  final _repo = VenueMemberRepository();

  bool get _isOwner => widget.callerRole == VenueMemberRole.owner;
  bool get _canManageRoles =>
      _isOwner || VenueSession.instance.can(VenuePermission.roleManage);

  bool _loading = true;
  String? _error;
  List<_RoleState> _roles = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final roles = await _repo.getRoles(widget.venueId);
      if (!mounted) return;
      setState(() {
        _roles = roles.map((r) => _RoleState(role: r)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Failed to load roles.'; });
    }
  }

  Future<void> _saveRole(_RoleState rs) async {
    if (rs.saving || !rs.isDirty) return;
    setState(() => rs.saving = true);
    try {
      await _repo.updateRolePerms(widget.venueId, rs.role.id, rs.pendingPerms.toList());
      if (!mounted) return;
      setState(() { rs.originalPerms = Set.from(rs.pendingPerms); rs.saving = false; });
      showSuccessSnackBar(context, message: '${rs.role.name} permissions saved.');
    } catch (_) {
      if (!mounted) return;
      setState(() => rs.saving = false);
      showErrorToast(context, message: 'Failed to save permissions.');
    }
  }

  Future<void> _addRole() async {
    final result = await showModalBottomSheet<VenueRole>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRoleSheet(venueId: widget.venueId, repo: _repo),
    );
    if (result != null) setState(() => _roles.add(_RoleState(role: result)));
  }

  Future<void> _deleteRole(_RoleState rs) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: Text('Delete "${rs.role.name}"?'),
          content: Text(
            rs.role.memberCount > 0
                ? 'This role has ${rs.role.memberCount} member(s). Reassign them before deleting.'
                : 'This role will be permanently deleted.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(children: [
              TextButton(
                style: TextButton.styleFrom(foregroundColor: AppTheme.brandPrimary),
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              const Spacer(),
              if (rs.role.memberCount == 0)
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Delete'),
                ),
            ]),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _repo.deleteRole(widget.venueId, rs.role.id);
      if (!mounted) return;
      setState(() => _roles.remove(rs));
      showSuccessSnackBar(context, message: '"${rs.role.name}" deleted.');
    } catch (_) {
      if (!mounted) return;
      showErrorToast(context, message: 'Failed to delete role.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF06091A) : theme.scaffoldBackgroundColor;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 12),
          child: AppBackButton(),
        ),
        title: Text('Roles & Permissions',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: colors.onSurface)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200],
              height: 1),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _PC.turkuaz))
          : _error != null
              ? _buildError(colors)
              : _buildBody(colors, isDark),
    );
  }

  Widget _buildError(ColorScheme colors) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.error_outline, size: 48, color: colors.onSurface.withValues(alpha: 0.4)),
        const SizedBox(height: 12),
        Text(_error!, style: TextStyle(color: colors.onSurface.withValues(alpha: 0.6))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry')),
      ]),
    );
  }

  Widget _buildBody(ColorScheme colors, bool isDark) {
    // Free plan'da rol hiyerarşisi (Admin/Manager/Staff + custom) kapalı — Social+.
    final planLocked = !VenueSession.instance.hasFeature(VenueFeature.roleLevels);
    final canEdit = _canManageRoles && !planLocked;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              // Free plan: rol hiyerarşisi kapalı — sadece kilit banner göster,
              // Admin/Staff/custom rol kartlarını hiç listeleme.
              if (planLocked)
                _buildPlanLockBanner(colors)
              else ...[
              // ── Info banner ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: _PC.mavi.withValues(alpha: 0.08),
                  border: Border.all(color: _PC.mavi.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 15, color: _PC.mavi),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text.rich(
                        TextSpan(children: [
                          TextSpan(text: 'Owner ',
                              style: TextStyle(color: _PC.mavi, fontWeight: FontWeight.w600, fontSize: 12)),
                          TextSpan(
                            text: _canManageRoles
                                ? 'always has full access. Customize which features each role can use.'
                                : 'always has full access. You have read-only access.',
                            style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.55), fontSize: 12, height: 1.5)),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Role cards ───────────────────────────────────────────────
              ...List.generate(_roles.length, (i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _RoleCard(
                  rs: _roles[i],
                  canManage: canEdit,
                  isDark: isDark,
                  onSave: () => _saveRole(_roles[i]),
                  onDelete: () => _deleteRole(_roles[i]),
                  onPermChanged: (perm, value) => setState(() {
                    if (value) _roles[i].pendingPerms.add(perm);
                    else _roles[i].pendingPerms.remove(perm);
                  }),
                  onToggleExpand: () => setState(() => _roles[i].expanded = !_roles[i].expanded),
                ),
              )),
              ],
            ],
          ),
        ),

        // ── Add Role button ──────────────────────────────────────────────
        if (_canManageRoles)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: planLocked
                    ? FilledButton.icon(
                        onPressed: () => PlanGate.openPaywall(context),
                        icon: const Icon(Icons.lock_outline, size: 18),
                        label: const Text('Upgrade to unlock roles',
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                        style: FilledButton.styleFrom(
                          backgroundColor: VenuePlan.social.color,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          elevation: 0,
                        ),
                      )
                    : PrimaryButton(label: 'Add Role', onPressed: _addRole),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPlanLockBanner(ColorScheme colors) {
    final c = VenuePlan.social.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => PlanGate.openPaywall(context),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.1),
            border: Border.all(color: c.withValues(alpha: 0.4)),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.lock_outline, size: 18, color: c),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Role levels are a Social plan feature. On Free, your venue is single-operator (owner only). '
                  'Upgrade to assign Admin, Manager & Staff roles.',
                  style: TextStyle(color: colors.onSurface.withValues(alpha: 0.75), fontSize: 12.5, height: 1.4),
                ),
              ),
              Icon(Icons.chevron_right, color: c),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Role state ───────────────────────────────────────────────────────────────

class _RoleState {
  final VenueRole role;
  Set<VenuePermission> originalPerms;
  Set<VenuePermission> pendingPerms;
  bool expanded;
  bool saving;

  _RoleState({required this.role})
      : originalPerms = Set.from(role.permissions),
        pendingPerms = Set.from(role.permissions),
        expanded = false,
        saving = false;

  bool get isDirty => !_setEqual(pendingPerms, originalPerms);
  static bool _setEqual(Set<VenuePermission> a, Set<VenuePermission> b) =>
      a.length == b.length && a.containsAll(b);
}

// ─── Role card ────────────────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final _RoleState rs;
  final bool canManage;
  final bool isDark;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final void Function(VenuePermission, bool) onPermChanged;
  final VoidCallback onToggleExpand;

  const _RoleCard({
    required this.rs,
    required this.canManage,
    required this.isDark,
    required this.onSave,
    required this.onDelete,
    required this.onPermChanged,
    required this.onToggleExpand,
  });

  bool get _canEdit => canManage && !rs.role.isOwnerRole;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final roleColor = _PC.forRole(rs.role);
    final cardBg    = isDark ? const Color(0xFF0D1525) : colors.surface;
    final borderCol = rs.expanded
        ? roleColor
        : (isDark ? const Color(0xFF162040) : colors.outline.withValues(alpha: 0.18));

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          GestureDetector(
            onTap: rs.role.isOwnerRole ? null : onToggleExpand,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: cardBg,
                border: Border.all(color: borderCol),
                borderRadius: rs.expanded
                    ? const BorderRadius.vertical(top: Radius.circular(16))
                    : BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  // Color dot
                  Container(
                    width: 8, height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: roleColor,
                      boxShadow: [BoxShadow(color: roleColor.withValues(alpha: 0.5), blurRadius: 6)],
                    ),
                  ),
                  const SizedBox(width: 10),

                  // Name
                  Expanded(
                    child: Text(rs.role.name,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                            color: colors.onSurface)),
                  ),

                  // Member count badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0A1428) : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: isDark ? const Color(0xFF162040) : colors.outline.withValues(alpha: 0.2)),
                    ),
                    child: Text('${rs.role.memberCount}',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                            color: colors.onSurface.withValues(alpha: isDark ? 0.3 : 0.5))),
                  ),
                  const SizedBox(width: 6),

                  // Owner tag / Save button / Delete
                  if (rs.role.isOwnerRole)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: _PC.magenta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _PC.magenta.withValues(alpha: 0.25)),
                      ),
                      child: const Text('All access',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                              color: _PC.magenta)),
                    )
                  else ...[
                    // Save button when dirty
                    if (rs.isDirty && _canEdit)
                      GestureDetector(
                        onTap: rs.saving ? null : onSave,
                        child: Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _PC.turkuaz,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: rs.saving
                              ? const SizedBox(width: 14, height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Text('Save',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                                      color: Color(0xFF06091A))),
                        ),
                      ),

                    // Delete (custom roles only)
                    if (!rs.role.isSystem && canManage)
                      GestureDetector(
                        onTap: onDelete,
                        child: Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(Icons.delete_outline_rounded, size: 18,
                              color: Colors.red.withValues(alpha: 0.7)),
                        ),
                      ),

                    // Chevron
                    AnimatedRotation(
                      turns: rs.expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.keyboard_arrow_down_rounded, size: 20,
                          color: rs.expanded ? roleColor : colors.onSurface.withValues(alpha: 0.3)),
                    ),
                  ],
                ],
              ),
            ),
          ),

          // ── Permissions body ─────────────────────────────────────────────
          if (rs.expanded && !rs.role.isOwnerRole)
            _PermBody(
              perms: rs.pendingPerms,
              editable: _canEdit,
              roleColor: roleColor,
              isDark: isDark,
              onChanged: onPermChanged,
            ),
        ],
      ),
    );
  }
}

// ─── Permissions body ─────────────────────────────────────────────────────────

class _PermBody extends StatelessWidget {
  final Set<VenuePermission> perms;
  final bool editable;
  final Color roleColor;
  final bool isDark;
  final void Function(VenuePermission, bool) onChanged;

  const _PermBody({
    required this.perms,
    required this.editable,
    required this.roleColor,
    required this.isDark,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final bodyBg = isDark ? const Color(0xFF0A1828) : colors.surfaceContainerLowest;
    final borderCol = roleColor;

    final allPerms = VenuePermission.values.toList();

    return Container(
      decoration: BoxDecoration(
        color: bodyBg,
        border: Border(
          left: BorderSide(color: borderCol),
          right: BorderSide(color: borderCol),
          bottom: BorderSide(color: borderCol),
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
      ),
      child: Column(
        children: List.generate(allPerms.length, (i) {
          final perm = allPerms[i];
          final enabled = perms.contains(perm);
          final meta = _permMeta[perm];
          final iconColor = enabled ? (meta?.color ?? roleColor) : Colors.transparent;
          final iconBg = enabled
              ? (meta?.color ?? roleColor).withValues(alpha: 0.12)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.04));

          return InkWell(
            onTap: editable ? () => onChanged(perm, !enabled) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: i < allPerms.length - 1
                  ? BoxDecoration(
                      border: Border(
                          bottom: BorderSide(
                              color: Colors.white.withValues(alpha: isDark ? 0.04 : 0.0),
                              width: isDark ? 1 : 0)))
                  : null,
              child: Row(
                children: [
                  // Icon box
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      meta?.icon ?? Icons.settings_outlined,
                      size: 15,
                      color: enabled
                          ? (meta?.color ?? roleColor)
                          : (isDark ? const Color(0xFF2E4560) : colors.onSurface.withValues(alpha: 0.25)),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Label
                  Expanded(
                    child: Text(perm.label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: enabled
                              ? (isDark ? const Color(0xFF8AA8CC) : colors.onSurface.withValues(alpha: 0.75))
                              : (isDark ? const Color(0xFF3A5070) : colors.onSurface.withValues(alpha: 0.35)),
                        )),
                  ),

                  // Toggle
                  _MiniSwitch(
                    value: enabled,
                    enabled: editable,
                    activeColor: _PC.turkuaz,
                    isDark: isDark,
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Mini switch ──────────────────────────────────────────────────────────────

class _MiniSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final Color activeColor;
  final bool isDark;

  const _MiniSwitch({
    required this.value,
    required this.enabled,
    required this.activeColor,
    this.isDark = true,
  });

  @override
  Widget build(BuildContext context) {
    final trackOn  = activeColor;
    final trackOff = isDark ? const Color(0xFF1A2A40) : Colors.black12;
    final thumbOff = isDark ? const Color(0xFF3A5070) : Colors.white;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 38, height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: enabled ? (value ? trackOn : trackOff) : trackOff.withValues(alpha: 0.5),
        border: value ? null : Border.all(
            color: isDark ? const Color(0xFF1E3060) : Colors.black.withValues(alpha: 0.1)),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : thumbOff,
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 3)],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Add Role Bottom Sheet ────────────────────────────────────────────────────

class _AddRoleSheet extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;

  const _AddRoleSheet({required this.venueId, required this.repo});

  @override
  State<_AddRoleSheet> createState() => _AddRoleSheetState();
}

class _AddRoleSheetState extends State<_AddRoleSheet> {
  final _nameCtrl = TextEditingController();
  final _formKey  = GlobalKey<FormState>();
  final Set<VenuePermission> _selected = {};
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() { _nameCtrl.dispose(); super.dispose(); }

  Future<void> _create() async {
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final role = await widget.repo.createRole(
          widget.venueId, _nameCtrl.text.trim(), _selected.toList());
      if (!mounted) return;
      Navigator.pop(context, role);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _saving = false;
        _nameError = msg.toLowerCase().contains('already exist') ||
                msg.toLowerCase().contains('duplicate') ||
                msg.toLowerCase().contains('conflict') ||
                msg.toLowerCase().contains('unique')
            ? 'A role with this name already exists.'
            : msg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;
    final maxH = (mq.size.height - keyboardInset - 40).clamp(220.0, mq.size.height * 0.88);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1525) : Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('New Role',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                          color: colors.onSurface)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _saving ? null : _create,
                    style: FilledButton.styleFrom(
                      backgroundColor: _PC.turkuaz,
                      foregroundColor: const Color(0xFF06091A),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Create', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    onChanged: (_) { if (_nameError != null) setState(() => _nameError = null); },
                    decoration: InputDecoration(
                      labelText: 'Role Name',
                      hintText: 'e.g. Bartender, Security…',
                      prefixIcon: const Icon(Icons.label_outline),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) => (v ?? '').trim().length < 2 ? 'At least 2 characters' : null,
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ),
              if (_nameError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Row(children: [
                    Icon(Icons.error_outline, size: 14, color: colors.error),
                    const SizedBox(width: 6),
                    Text(_nameError!,
                        style: TextStyle(fontSize: 12, color: colors.error, fontWeight: FontWeight.w500)),
                  ]),
                ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(children: [
                  Text('Permissions',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                          color: colors.onSurface.withValues(alpha: 0.5), letterSpacing: 0.5)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _PC.turkuaz.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${_selected.length} selected',
                        style: const TextStyle(fontSize: 11, color: _PC.turkuaz, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ),
              const SizedBox(height: 8),
              Divider(height: 1, color: colors.outline.withValues(alpha: 0.12)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: VenuePermission.values.map((perm) {
                    final enabled = _selected.contains(perm);
                    final meta = _permMeta[perm];
                    return InkWell(
                      onTap: () => setState(() {
                        if (enabled) _selected.remove(perm); else _selected.add(perm);
                      }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        child: Row(children: [
                          Container(
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: enabled
                                  ? (meta?.color ?? _PC.turkuaz).withValues(alpha: 0.12)
                                  : colors.onSurface.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(meta?.icon ?? Icons.settings_outlined, size: 14,
                                color: enabled
                                    ? (meta?.color ?? _PC.turkuaz)
                                    : colors.onSurface.withValues(alpha: 0.3)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Text(perm.label, style: const TextStyle(fontSize: 13))),
                          _MiniSwitch(value: enabled, enabled: true, activeColor: _PC.turkuaz, isDark: isDark),
                        ]),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
