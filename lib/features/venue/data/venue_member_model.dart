// Venue üye ve yetki matrisi modelleri

enum VenueMemberRole { owner, admin, staff }

extension VenueMemberRoleExt on VenueMemberRole {
  String get label {
    switch (this) {
      case VenueMemberRole.owner:
        return 'Owner';
      case VenueMemberRole.admin:
        return 'Admin';
      case VenueMemberRole.staff:
        return 'Staff';
    }
  }

  String get apiValue {
    switch (this) {
      case VenueMemberRole.owner:
        return 'OWNER';
      case VenueMemberRole.admin:
        return 'ADMIN';
      case VenueMemberRole.staff:
        return 'STAFF';
    }
  }

  static VenueMemberRole fromApi(String raw) {
    switch (raw.toUpperCase()) {
      case 'OWNER':
        return VenueMemberRole.owner;
      case 'ADMIN':
        return VenueMemberRole.admin;
      default:
        return VenueMemberRole.staff;
    }
  }
}

enum VenuePermission {
  eventManage,
  storyPost,
  postCreate,
  venueEdit,
  viewGuests,
  reportGuest,
  blockGuest,
  sendPush,
  viewStats,
  viewAnalytics,
  memberManage,
}

extension VenuePermissionExt on VenuePermission {
  String get apiValue {
    switch (this) {
      case VenuePermission.eventManage:
        return 'EVENT_MANAGE';
      case VenuePermission.storyPost:
        return 'STORY_POST';
      case VenuePermission.postCreate:
        return 'POST_CREATE';
      case VenuePermission.venueEdit:
        return 'VENUE_EDIT';
      case VenuePermission.viewGuests:
        return 'VIEW_GUESTS';
      case VenuePermission.reportGuest:
        return 'REPORT_GUEST';
      case VenuePermission.blockGuest:
        return 'BLOCK_GUEST';
      case VenuePermission.sendPush:
        return 'SEND_PUSH';
      case VenuePermission.viewStats:
        return 'VIEW_STATS';
      case VenuePermission.viewAnalytics:
        return 'VIEW_ANALYTICS';
      case VenuePermission.memberManage:
        return 'MEMBER_MANAGE';
    }
  }

  String get label {
    switch (this) {
      case VenuePermission.eventManage:
        return 'Create / edit / delete events';
      case VenuePermission.storyPost:
        return 'Post stories';
      case VenuePermission.postCreate:
        return 'Create posts';
      case VenuePermission.venueEdit:
        return 'Edit venue profile';
      case VenuePermission.viewGuests:
        return 'View guests at venue';
      case VenuePermission.reportGuest:
        return 'Report a guest';
      case VenuePermission.blockGuest:
        return 'Block a guest';
      case VenuePermission.sendPush:
        return 'Send nearby push notification';
      case VenuePermission.viewStats:
        return 'View check-in stats';
      case VenuePermission.viewAnalytics:
        return 'View advanced analytics';
      case VenuePermission.memberManage:
        return 'Add / remove team members';
    }
  }

  static VenuePermission? fromApi(String raw) {
    for (final p in VenuePermission.values) {
      if (p.apiValue == raw) return p;
    }
    return null;
  }
}

class VenueMemberUser {
  final String id;
  final String? fullName;
  final String? username;
  final String? photo;
  final bool isStaff;
  final String? staffVenueId;

  const VenueMemberUser({
    required this.id,
    this.fullName,
    this.username,
    this.photo,
    this.isStaff = false,
    this.staffVenueId,
  });

  factory VenueMemberUser.fromJson(Map<String, dynamic> json) {
    return VenueMemberUser(
      id: json['id']?.toString() ?? '',
      fullName: (json['fullName'] ?? json['full_name'])?.toString(),
      username: json['username']?.toString(),
      photo: json['photo']?.toString(),
      isStaff: json['isStaff'] == true || json['is_staff'] == true,
      staffVenueId: (json['staffVenueId'] ?? json['staff_venue_id'])?.toString(),
    );
  }

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (username != null && username!.isNotEmpty) return '@$username';
    return 'Member';
  }
}

class VenueMember {
  final String id;
  final VenueMemberRole role;
  final String? venueRoleId;
  final String? venueRoleName;
  final String status;
  final String createdAt;
  final VenueMemberUser user;

  const VenueMember({
    required this.id,
    required this.role,
    this.venueRoleId,
    this.venueRoleName,
    required this.status,
    required this.createdAt,
    required this.user,
  });

  /// Display name for the role badge: custom role name or system role label
  String get roleDisplayName => venueRoleName ?? role.label;

  factory VenueMember.fromJson(Map<String, dynamic> json) {
    return VenueMember(
      id: json['id']?.toString() ?? '',
      role: VenueMemberRoleExt.fromApi(json['role']?.toString() ?? 'STAFF'),
      venueRoleId: json['venueRoleId']?.toString(),
      venueRoleName: json['venueRoleName']?.toString(),
      status: json['status']?.toString() ?? 'ACTIVE',
      createdAt: (json['createdAt'] ?? json['created_at'])?.toString() ?? '',
      user: VenueMemberUser.fromJson(
        Map<String, dynamic>.from(json['user'] as Map? ?? {}),
      ),
    );
  }
}

// ─── VenueRole (custom roles created by owner) ───────────────────────────────

class VenueRole {
  final String id; // 'OWNER' | 'ADMIN' | 'STAFF' | UUID
  final String name;
  final bool isSystem;
  final bool isOwnerRole;
  final Set<VenuePermission> permissions;
  final int memberCount;

  const VenueRole({
    required this.id,
    required this.name,
    required this.isSystem,
    required this.isOwnerRole,
    required this.permissions,
    required this.memberCount,
  });

  factory VenueRole.fromJson(Map<String, dynamic> json) {
    final rawPerms = (json['permissions'] as List? ?? []);
    return VenueRole(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      isSystem: json['isSystem'] == true,
      isOwnerRole: json['isOwnerRole'] == true,
      permissions: rawPerms
          .map((e) => VenuePermissionExt.fromApi(e.toString()))
          .whereType<VenuePermission>()
          .toSet(),
      memberCount: (json['memberCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class VenueRolePermissions {
  final List<VenuePermission> admin;
  final List<VenuePermission> staff;

  const VenueRolePermissions({required this.admin, required this.staff});

  factory VenueRolePermissions.fromJson(Map<String, dynamic> json) {
    List<VenuePermission> parseList(dynamic raw) {
      if (raw == null) return [];
      return (raw as List)
          .map((e) => VenuePermissionExt.fromApi(e.toString()))
          .whereType<VenuePermission>()
          .toList();
    }

    return VenueRolePermissions(
      admin: parseList(json['ADMIN']),
      staff: parseList(json['STAFF']),
    );
  }
}

/// Kullanıcı arama sonucu (üye eklerken)
class UserSearchResult {
  final String id;
  final String? username;
  final String? fullName;
  final String? photo;

  const UserSearchResult({
    required this.id,
    this.username,
    this.fullName,
    this.photo,
  });

  factory UserSearchResult.fromJson(Map<String, dynamic> json) {
    return UserSearchResult(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString(),
      fullName: (json['fullName'] ?? json['full_name'])?.toString(),
      photo: json['photo']?.toString(),
    );
  }

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (username != null && username!.isNotEmpty) return '@$username';
    return 'User';
  }
}
