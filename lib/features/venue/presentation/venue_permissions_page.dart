import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

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

  bool _loading = true;
  String? _error;
  List<_RoleState> _roles = [];

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
      final roles = await _repo.getRoles(widget.venueId);
      if (!mounted) return;
      setState(() {
        _roles = roles.map((r) => _RoleState(role: r)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Failed to load roles. Please try again.';
      });
    }
  }

  Future<void> _saveRole(_RoleState rs) async {
    if (rs.saving || !rs.isDirty) return;
    setState(() => rs.saving = true);
    try {
      await _repo.updateRolePerms(
        widget.venueId,
        rs.role.id,
        rs.pendingPerms.toList(),
      );
      if (!mounted) return;
      setState(() {
        rs.originalPerms = Set.from(rs.pendingPerms);
        rs.saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${rs.role.name} permissions saved.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => rs.saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _addRole() async {
    final result = await showModalBottomSheet<VenueRole>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddRoleSheet(venueId: widget.venueId, repo: _repo),
    );
    if (result != null) {
      setState(() => _roles.add(_RoleState(role: result)));
    }
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
                : 'This role will be permanently deleted. This action cannot be undone.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: AppTheme.brandPrimary),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                if (rs.role.memberCount == 0)
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: colors.error),
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Delete'),
                  ),
              ],
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    try {
      await _repo.deleteRole(widget.venueId, rs.role.id);
      if (!mounted) return;
      setState(() => _roles.remove(rs));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${rs.role.name}" deleted.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Roles & Permissions'),
      ),
      floatingActionButton: _isOwner && !_loading
          ? FloatingActionButton.extended(
              onPressed: _addRole,
              icon: const Icon(Icons.add),
              label: const Text('Add Role'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError(colors)
              : _buildList(colors),
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

  Widget _buildList(ColorScheme colors) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: [
        // Info banner
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
                  _isOwner
                      ? 'Owner always has full access. Customize which features each role can use.'
                      : 'Only the Owner can edit role permissions. You have read-only access.',
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
        const SizedBox(height: 16),

        // Role cards
        ...List.generate(_roles.length, (i) {
          final rs = _roles[i];
          final isLast = i == _roles.length - 1;
          return Padding(
            padding: EdgeInsets.only(bottom: isLast ? 0 : 8),
            child: _RoleCard(
              rs: rs,
              isOwner: _isOwner,
              callerRole: widget.callerRole,
              onSave: () => _saveRole(rs),
              onDelete: () => _deleteRole(rs),
              onPermChanged: (perm, value) {
                setState(() {
                  if (value) {
                    rs.pendingPerms.add(perm);
                  } else {
                    rs.pendingPerms.remove(perm);
                  }
                });
              },
              onToggleExpand: () {
                setState(() => rs.expanded = !rs.expanded);
              },
            ),
          );
        }),
      ],
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

  static bool _setEqual(Set<VenuePermission> a, Set<VenuePermission> b) {
    if (a.length != b.length) return false;
    return a.containsAll(b);
  }
}

// ─── Role card (accordion) ────────────────────────────────────────────────────

class _RoleCard extends StatelessWidget {
  final _RoleState rs;
  final bool isOwner;
  final VenueMemberRole callerRole;
  final VoidCallback onSave;
  final VoidCallback onDelete;
  final void Function(VenuePermission, bool) onPermChanged;
  final VoidCallback onToggleExpand;

  const _RoleCard({
    required this.rs,
    required this.isOwner,
    required this.callerRole,
    required this.onSave,
    required this.onDelete,
    required this.onPermChanged,
    required this.onToggleExpand,
  });

  bool get _canEditThisRole {
    if (rs.role.isOwnerRole) return false;
    return isOwner;
  }

  Color _roleColor(ColorScheme c) {
    if (rs.role.isOwnerRole) return c.primary;
    if (rs.role.id == 'ADMIN') return c.secondary;
    if (rs.role.id == 'STAFF') return c.tertiary;
    // Custom roles — cycle through theme colors (error/red excluded — it implies a problem)
    final palette = [c.secondary, c.tertiary, c.primary];
    final index = rs.role.name.codeUnits.fold(0, (a, b) => a + b) % palette.length;
    return palette[index];
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final roleColor = _roleColor(colors);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: rs.expanded
              ? roleColor.withValues(alpha: 0.4)
              : colors.outline.withValues(alpha: 0.15),
          width: rs.expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: rs.role.isOwnerRole ? null : onToggleExpand,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Role color dot
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: roleColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Role name
                  Expanded(
                    child: Row(
                      children: [
                        Text(
                          rs.role.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${rs.role.memberCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                        if (rs.role.isOwnerRole)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '· All access',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurface.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Save button (visible when dirty)
                  if (rs.isDirty && _canEditThisRole)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onTap: rs.saving ? null : onSave,
                        child: rs.saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: colors.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Save',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: colors.onPrimary,
                                  ),
                                ),
                              ),
                      ),
                    ),
                  // Delete button (custom roles, owner only, not expanded members)
                  if (!rs.role.isSystem && isOwner)
                    GestureDetector(
                      onTap: onDelete,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: colors.error.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  // Expand arrow
                  if (!rs.role.isOwnerRole)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: AnimatedRotation(
                        turns: rs.expanded ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 22,
                          color: colors.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // Expanded permission list
          if (rs.expanded && !rs.role.isOwnerRole)
            _PermissionList(
              perms: rs.pendingPerms,
              editable: _canEditThisRole,
              roleColor: roleColor,
              onChanged: onPermChanged,
            ),
        ],
      ),
    );
  }
}

// ─── Permission list inside expanded card ─────────────────────────────────────

class _PermissionList extends StatelessWidget {
  final Set<VenuePermission> perms;
  final bool editable;
  final Color roleColor;
  final void Function(VenuePermission, bool) onChanged;

  const _PermissionList({
    required this.perms,
    required this.editable,
    required this.roleColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // MEMBER_MANAGE is OWNER-only and not configurable for other roles.
    final configurablePerms = VenuePermission.values
        .where((p) => p != VenuePermission.memberManage)
        .toList();

    return Column(
      children: [
        Divider(
          height: 1,
          color: colors.outline.withValues(alpha: 0.12),
        ),
        ...configurablePerms.asMap().entries.map((entry) {
          final perm = entry.value;
          final enabled = perms.contains(perm);
          final isOdd = entry.key.isOdd;

          return InkWell(
            onTap: editable ? () => onChanged(perm, !enabled) : null,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              color: isOdd
                  ? colors.surfaceContainerHighest.withValues(alpha: 0.25)
                  : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      perm.label,
                      style: TextStyle(
                        fontSize: 13,
                        color: editable
                            ? colors.onSurface.withValues(alpha: 0.85)
                            : colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  _MiniSwitch(
                    value: enabled,
                    enabled: editable,
                    activeColor: roleColor,
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Mini switch ──────────────────────────────────────────────────────────────

class _MiniSwitch extends StatelessWidget {
  final bool value;
  final bool enabled;
  final Color activeColor;

  const _MiniSwitch({
    required this.value,
    required this.enabled,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final trackColor = enabled
        ? (value ? activeColor : colors.onSurface.withValues(alpha: 0.15))
        : colors.onSurface.withValues(alpha: 0.08);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 38,
      height: 22,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        color: trackColor,
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: enabled
                  ? Colors.white
                  : Colors.white.withValues(alpha: 0.4),
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
  final _formKey = GlobalKey<FormState>();
  final Set<VenuePermission> _selected = {};
  bool _saving = false;
  String? _nameError;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _nameError = null);
    if (!_formKey.currentState!.validate() || _saving) return;
    setState(() => _saving = true);
    try {
      final role = await widget.repo.createRole(
        widget.venueId,
        _nameCtrl.text.trim(),
        _selected.toList(),
      );
      if (!mounted) return;
      Navigator.pop(context, role);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceAll('Exception: ', '');
      setState(() {
        _saving = false;
        // Duplicate/conflict hatasını field altında göster, diğerlerini de yakala
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
    final mq = MediaQuery.of(context);
    final keyboardInset = mq.viewInsets.bottom;

    // Cap the sheet content height so that (content + keyboardInset) never
    // exceeds the screen height.  Leave 40 px of safe margin at the top.
    final maxContentHeight =
        (mq.size.height - keyboardInset - 40).clamp(220.0, mq.size.height * 0.88);

    // AnimatedPadding pushes the entire sheet UP as the keyboard rises — the
    // content box itself never changes height, so Expanded/Flexible children
    // always have valid, non-negative constraints.
    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxContentHeight),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header (always visible above keyboard) ─────────────────
              const SizedBox(height: 12),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Text(
                      'New Role',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving ? null : _create,
                      style: FilledButton.styleFrom(
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Create',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Form(
                  key: _formKey,
                  child: TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    autofocus: false,
                    onChanged: (_) {
                      if (_nameError != null) setState(() => _nameError = null);
                    },
                    decoration: InputDecoration(
                      labelText: 'Role Name',
                      hintText: 'e.g. Bartender, Security...',
                      prefixIcon: const Icon(Icons.label_outline),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) {
                      if ((v ?? '').trim().length < 2) {
                        return 'At least 2 characters';
                      }
                      return null;
                    },
                    textInputAction: TextInputAction.next,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      'Permissions',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface.withValues(alpha: 0.5),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colors.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${_selected.length} selected',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (_nameError != null)
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 6, 20, 0),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          size: 14, color: colors.error),
                      const SizedBox(width: 6),
                      Text(
                        _nameError!,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Divider(height: 1, color: colors.outline.withValues(alpha: 0.12)),

              // ── Scrollable permission toggles ───────────────────────────
              // Flexible (not Expanded) so Column can size itself to remaining
              // space without ever computing a negative constraint.
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: VenuePermission.values
                      .where((p) => p != VenuePermission.memberManage)
                      .toList()
                      .asMap()
                      .entries
                      .map((entry) {
                    final perm = entry.value;
                    final enabled = _selected.contains(perm);
                    final isOdd = entry.key.isOdd;
                    return InkWell(
                      onTap: () => setState(() {
                        if (enabled) {
                          _selected.remove(perm);
                        } else {
                          _selected.add(perm);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 11),
                        color: isOdd
                            ? colors.surfaceContainerHighest
                                .withValues(alpha: 0.25)
                            : null,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                perm.label,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            _MiniSwitch(
                              value: enabled,
                              enabled: true,
                              activeColor: colors.primary,
                            ),
                          ],
                        ),
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
