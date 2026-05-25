import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  bool get _isOwner => widget.callerRole == VenueMemberRole.owner;
  // Only OWNER can add / edit / remove members and manage roles.
  bool get _canManage => _isOwner;
  bool get _canAccessPermissions => _isOwner;

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
      final members = await _repo.getMembers(widget.venueId);
      if (!mounted) return;
      setState(() {
        _members = members;
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

  Future<void> _openAddMember() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMemberSheet(venueId: widget.venueId, repo: _repo),
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

  Future<void> _removeMember(VenueMember member) async {
    final isStaff =
        member.user.isStaff && member.user.staffVenueId == widget.venueId;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isStaff ? 'Delete Staff' : 'Remove Member'),
        content: Text(
          isStaff
              ? '${member.user.displayName} will be removed from the team and their account will be permanently deleted.'
              : '${member.user.displayName} will be removed from the team. Their account will not be deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: Text(isStaff ? 'Delete' : 'Remove'),
          ),
        ],
      ),
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
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Team Management'),
        actions: [
          if (_canAccessPermissions)
            IconButton(
              icon: const Icon(Icons.tune_outlined),
              tooltip: 'Permission Matrix',
              onPressed: _openPermissions,
            ),
        ],
      ),
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _openAddMember,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add Member'),
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
    if (_members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.group_outlined,
                  size: 52, color: colors.onSurface.withValues(alpha: 0.3)),
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
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        itemCount: _members.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (_, i) => _buildMemberCard(_members[i], colors),
      ),
    );
  }

  Widget _buildMemberCard(VenueMember member, ColorScheme colors) {
    final isCurrentOwner = member.role == VenueMemberRole.owner;
    final canManage = _canManage && !isCurrentOwner;
    final isStaffAccount =
        member.user.isStaff && member.user.staffVenueId == widget.venueId;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outline.withValues(alpha: 0.15)),
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: _Avatar(
          photo: member.user.photo,
          displayName: member.user.displayName,
          colors: colors,
        ),
        title: Text(
          member.user.displayName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        subtitle: member.user.username != null
            ? Text(
                '@${member.user.username}',
                style: TextStyle(
                    fontSize: 12,
                    color: colors.onSurface.withValues(alpha: 0.5)),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RoleBadge(
              role: member.role,
              customName: member.venueRoleName,
              colors: colors,
            ),
            if (canManage) ...[
              const SizedBox(width: 6),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert,
                    size: 20,
                    color: colors.onSurface.withValues(alpha: 0.5)),
                itemBuilder: (_) => [
                  // Only owner can edit staff account credentials
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
                        Icon(Icons.swap_horiz_outlined, size: 18),
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
          ],
        ),
      ),
    );
  }
}

// ─── Alt bileşenler ───────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? photo;
  final String displayName;
  final ColorScheme colors;

  const _Avatar({
    required this.photo,
    required this.displayName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (photo != null && photo!.isNotEmpty) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: NetworkImage(photo!),
        onBackgroundImageError: (_, _) {},
      );
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: colors.primary.withValues(alpha: 0.12),
      child: Text(
        displayName.isNotEmpty ? displayName[0].toUpperCase() : '?',
        style: TextStyle(
          color: colors.primary,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final VenueMemberRole role;
  final String? customName;
  final ColorScheme colors;

  const _RoleBadge({
    required this.role,
    this.customName,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final isCustom = customName != null;
    final (bg, fg) = isCustom
        ? (colors.tertiary.withValues(alpha: 0.15), colors.tertiary)
        : switch (role) {
            VenueMemberRole.owner => (colors.primary, colors.onPrimary),
            VenueMemberRole.admin => (
                colors.secondary.withValues(alpha: 0.15),
                colors.secondary
              ),
            VenueMemberRole.staff => (
                colors.onSurface.withValues(alpha: 0.08),
                colors.onSurface.withValues(alpha: 0.6)
              ),
          };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        customName ?? role.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

// ─── Üye Ekleme Bottom Sheet (iki sekme) ─────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;

  const _AddMemberSheet({required this.venueId, required this.repo});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  List<VenueRole>? _roles;
  bool _loadingRoles = true;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() => setState(() {}));
    _loadRoles();
  }

  Future<void> _loadRoles() async {
    try {
      final roles = await widget.repo.getRoles(widget.venueId);
      if (!mounted) return;
      setState(() {
        _roles = roles.where((r) => !r.isOwnerRole).toList();
        _loadingRoles = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRoles = false);
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
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
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TabBar(
                controller: _tabs,
                dividerColor: Colors.transparent,
                labelColor: colors.primary,
                unselectedLabelColor: colors.onSurface.withValues(alpha: 0.5),
                indicatorSize: TabBarIndicatorSize.tab,
                tabs: const [
                  Tab(text: 'Search User'),
                  Tab(text: 'Invite Link'),
                ],
              ),
            ),
            SizedBox(
              height: 440,
              child: _loadingRoles
                  ? const Center(child: CircularProgressIndicator())
                  : TabBarView(
                      controller: _tabs,
                      children: [
                        _ExistingUserTab(
                          venueId: widget.venueId,
                          repo: widget.repo,
                          venueRoles: _roles ?? [],
                        ),
                        _InviteLinkTab(
                          venueId: widget.venueId,
                          venueRoles: _roles ?? [],
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

// ─── Sekme 1: Mevcut kullanıcı ara ───────────────────────────────────────────

class _ExistingUserTab extends StatefulWidget {
  final String venueId;
  final VenueMemberRepository repo;
  final List<VenueRole> venueRoles;

  const _ExistingUserTab({
    required this.venueId,
    required this.repo,
    required this.venueRoles,
  });

  @override
  State<_ExistingUserTab> createState() => _ExistingUserTabState();
}

class _ExistingUserTabState extends State<_ExistingUserTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  bool _searching = false;
  List<UserSearchResult> _results = [];
  UserSearchResult? _selected;
  // Selected role: either a system VenueRole (id = 'ADMIN'/'STAFF') or custom
  VenueRole? _selectedVenueRole;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    // Default to Admin role
    if (widget.venueRoles.isNotEmpty) {
      _selectedVenueRole = widget.venueRoles.firstWhere(
        (r) => r.id == 'ADMIN',
        orElse: () => widget.venueRoles.first,
      );
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
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
    final venueRole = _selectedVenueRole;
    if (user == null || venueRole == null || _adding) return;
    setState(() => _adding = true);
    try {
      // System roles → pass enum; custom roles → pass STAFF enum + venueRoleId
      final enumRole = venueRole.id == 'ADMIN'
          ? VenueMemberRole.admin
          : VenueMemberRole.staff;
      final customId =
          (venueRole.id != 'ADMIN' && venueRole.id != 'STAFF')
              ? venueRole.id
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              labelText: 'Search by username',
              hintText: 'e.g. john',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border:
                  OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          if (_results.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              decoration: BoxDecoration(
                border: Border.all(
                    color: colors.outline.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _results.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: colors.outline.withValues(alpha: 0.15),
                ),
                itemBuilder: (_, i) {
                  final u = _results[i];
                  final isSelected = _selected?.id == u.id;
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor:
                          colors.primary.withValues(alpha: 0.1),
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
                                  color: colors.primary, fontSize: 12),
                            )
                          : null,
                    ),
                    title: Text(u.displayName,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: u.username != null
                        ? Text('@${u.username}',
                            style: const TextStyle(fontSize: 11))
                        : null,
                    selected: isSelected,
                    selectedTileColor:
                        colors.primary.withValues(alpha: 0.08),
                    onTap: () => setState(() => _selected = u),
                    trailing: isSelected
                        ? Icon(Icons.check_circle,
                            color: colors.primary, size: 18)
                        : null,
                  );
                },
              ),
            ),
          ],
          if (_selected != null && widget.venueRoles.isNotEmpty) ...[
            const SizedBox(height: 16),
            _VenueRolePicker(
              roles: widget.venueRoles,
              selected: _selectedVenueRole,
              onChanged: (r) => setState(() => _selectedVenueRole = r),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _selected == null || _adding ? null : _add,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _adding
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      _selected == null
                          ? 'Select a user first'
                          : 'Add ${_selected!.displayName} as ${_selectedVenueRole?.name ?? ''}',
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700),
                      overflow: TextOverflow.ellipsis,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sekme 2: Davet linki oluştur ────────────────────────────────────────────

class _InviteLinkTab extends StatefulWidget {
  final String venueId;
  final List<VenueRole> venueRoles;

  const _InviteLinkTab({required this.venueId, required this.venueRoles});

  @override
  State<_InviteLinkTab> createState() => _InviteLinkTabState();
}

class _InviteLinkTabState extends State<_InviteLinkTab> {
  final _inviteRepo = VenueInviteRepository();
  VenueRole? _selectedRole;
  bool _generating = false;
  CreatedInvite? _created;

  @override
  void initState() {
    super.initState();
    if (widget.venueRoles.isNotEmpty) {
      _selectedRole = widget.venueRoles.firstWhere(
        (r) => r.id == 'STAFF',
        orElse: () => widget.venueRoles.last,
      );
    }
  }

  Future<void> _generate() async {
    final role = _selectedRole;
    if (role == null || _generating) return;
    setState(() => _generating = true);
    try {
      final enumRole =
          role.id == 'ADMIN' ? VenueMemberRole.admin : VenueMemberRole.staff;
      final customId =
          (role.id != 'ADMIN' && role.id != 'STAFF') ? role.id : null;

      final invite = await _inviteRepo.createInvite(
        venueId: widget.venueId,
        role: enumRole,
        venueRoleId: customId,
      );
      if (!mounted) return;
      setState(() {
        _created = invite;
        _generating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to generate: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _copyLink() {
    if (_created == null) return;
    Clipboard.setData(ClipboardData(text: _created!.inviteUrl));
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
                    'Generate a link and share it via WhatsApp, SMS or any channel. '
                    'The person taps it, opens the app, and joins with the selected role.',
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

          // Role picker
          if (widget.venueRoles.isNotEmpty) ...[
            _VenueRolePicker(
              roles: widget.venueRoles,
              selected: _selectedRole,
              onChanged: (r) => setState(() {
                _selectedRole = r;
                _created = null; // rol değişince eski linki sıfırla
              }),
            ),
            const SizedBox(height: 20),
          ],

          // Generate button
          if (_created == null)
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
                    : const Icon(Icons.link_rounded, size: 18),
                label: Text(
                  _generating ? 'Generating...' : 'Generate Invite Link',
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

          // Generated link card
          if (_created != null) ...[
            Container(
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
                      Icon(Icons.check_circle,
                          color: colors.primary, size: 18),
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
                    _created!.inviteUrl,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Role: ${_created!.roleDisplay}  ·  Expires in 7 days',
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
                            padding:
                                const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        onPressed: () => setState(() => _created = null),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('New'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Role',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: colors.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: roles.map((role) {
            final isSelected = selected?.id == role.id;
            return GestureDetector(
              onTap: () => onChanged(role),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? colors.primary : colors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? colors.primary
                        : colors.outline.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  role.name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? colors.onPrimary : colors.onSurface,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
                    color: colors.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    role.name.isNotEmpty ? role.name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: colors.onPrimaryContainer,
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
                    ? Icon(Icons.check_circle,
                        color: colors.primary, size: 20)
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
