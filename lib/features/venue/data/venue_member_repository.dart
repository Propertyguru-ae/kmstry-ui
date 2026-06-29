import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_member_model.dart';

class VenueMemberRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  /// Venue üye listesini döner (ACTIVE üyeler).
  Future<List<VenueMember>> getMembers(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/members', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    final raw = map['members'] as List? ?? [];
    return raw
        .whereType<Map>()
        .map((e) => VenueMember.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// ADMIN ve STAFF rolleri için yetki matrisini döner.
  Future<VenueRolePermissions> getRolePermissions(String venueId) async {
    final headers = await _authHeaders();
    final data =
        await _api.get('/venues/$venueId/role-permissions', headers: headers);
    return VenueRolePermissions.fromJson(
        Map<String, dynamic>.from(data as Map));
  }

  /// Owner, bir rol için yetkileri günceller.
  Future<void> updateRolePermissions(
    String venueId,
    VenueMemberRole role,
    List<VenuePermission> permissions,
  ) async {
    final headers = await _authHeaders();
    await _api.put(
      '/venues/$venueId/role-permissions',
      headers: headers,
      body: {
        'role': role.apiValue,
        'permissions': permissions.map((p) => p.apiValue).toList(),
      },
    );
  }

  /// Yeni üye ekler (Owner/Admin → ACTIVE olarak eklenir).
  Future<void> addMember(
    String venueId,
    String userId,
    VenueMemberRole role, {
    String? venueRoleId,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{'userId': userId, 'role': role.apiValue};
    if (venueRoleId != null) body['venueRoleId'] = venueRoleId;
    await _api.post('/venues/$venueId/members', headers: headers, body: body);
  }

  /// Üyenin rolünü günceller.
  Future<void> updateMemberRole(
    String venueId,
    String memberId,
    VenueMemberRole role, {
    String? venueRoleId,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{'role': role.apiValue};
    if (venueRoleId != null) body['venueRoleId'] = venueRoleId;
    await _api.patch(
      '/venues/$venueId/members/$memberId/role',
      headers: headers,
      body: body,
    );
  }

  /// Üyeyi venue'dan çıkarır.
  Future<int> cleanPastInvites(String venueId) async {
    final headers = await _authHeaders();
    final result = await _api.delete(
      '/venues/$venueId/members/past',
      headers: headers,
    );
    return (result?['deleted'] as num?)?.toInt() ?? 0;
  }

  Future<void> removeMember(String venueId, String memberId) async {
    final headers = await _authHeaders();
    await _api.delete(
      '/venues/$venueId/members/$memberId',
      headers: headers,
    );
  }

  /// Venue owner tarafından yeni staff hesabı oluşturur.
  Future<VenueMember> createStaffUser({
    required String venueId,
    required String fullName,
    required String username,
    required String password,
    required VenueMemberRole role,
    String? venueRoleId,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'fullName': fullName,
      'username': username,
      'password': password,
      'role': role.apiValue,
    };
    if (venueRoleId != null) body['venueRoleId'] = venueRoleId;
    final data = await _api.post('/venues/$venueId/staff', headers: headers, body: body);
    final map = Map<String, dynamic>.from(data as Map);
    return VenueMember.fromJson(Map<String, dynamic>.from(map['member'] as Map));
  }

  /// Staff hesabının bilgilerini günceller (sadece owner).
  Future<void> updateStaffUser({
    required String venueId,
    required String memberId,
    String? fullName,
    String? username,
    String? newPassword,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{};
    if (fullName != null) body['fullName'] = fullName;
    if (username != null) body['username'] = username;
    if (newPassword != null) body['newPassword'] = newPassword;
    await _api.patch(
      '/venues/$venueId/staff/$memberId',
      headers: headers,
      body: body,
    );
  }

  // ── Custom Role CRUD ────────────────────────────────────────────────────────

  /// Returns all roles: Owner (virtual) + Admin + Staff + custom roles.
  Future<List<VenueRole>> getRoles(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/roles', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    final raw = map['roles'] as List? ?? [];
    return raw
        .whereType<Map>()
        .map((e) => VenueRole.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Owner creates a new custom role.
  Future<VenueRole> createRole(
    String venueId,
    String name,
    List<VenuePermission> permissions,
  ) async {
    final headers = await _authHeaders();
    final data = await _api.post(
      '/venues/$venueId/roles',
      headers: headers,
      body: {
        'name': name,
        'permissions': permissions.map((p) => p.apiValue).toList(),
      },
    );
    return VenueRole.fromJson(Map<String, dynamic>.from(data as Map));
  }

  /// Updates permissions for any role (system or custom).
  /// roleId: 'ADMIN' | 'STAFF' | UUID
  Future<void> updateRolePerms(
    String venueId,
    String roleId,
    List<VenuePermission> permissions,
  ) async {
    final headers = await _authHeaders();
    await _api.patch(
      '/venues/$venueId/roles/$roleId/permissions',
      headers: headers,
      body: {'permissions': permissions.map((p) => p.apiValue).toList()},
    );
  }

  /// Owner deletes a custom role.
  Future<void> deleteRole(String venueId, String roleId) async {
    final headers = await _authHeaders();
    await _api.delete('/venues/$venueId/roles/$roleId', headers: headers);
  }

  // ── Member status ────────────────────────────────────────────────────────────

  /// Bildirim tap'ında gerçek durumu sorgular: PENDING / ACTIVE / REJECTED / CANCELLED / EXPIRED
  Future<Map<String, String>> getMemberStatus(String venueId, String memberId) async {
    final headers = await _authHeaders();
    final data = await _api.get(
      '/venues/$venueId/members/$memberId/status',
      headers: headers,
    );
    final map = Map<String, dynamic>.from(data as Map);
    return {
      'status': map['status']?.toString() ?? 'PENDING',
      'role': map['role']?.toString() ?? '',
      'venueName': map['venueName']?.toString() ?? '',
    };
  }

  // ── Pending member invite ────────────────────────────────────────────────────

  /// Kullanıcı, kendisine gelen PENDING venue üyelik davetini kabul eder.
  Future<void> acceptMemberInvite(String venueId, String memberId) async {
    final headers = await _authHeaders();
    await _api.post(
      '/venues/$venueId/members/$memberId/accept',
      headers: headers,
      body: {},
    );
  }

  /// Kullanıcı, kendisine gelen PENDING venue üyelik davetini reddeder.
  Future<void> declineMemberInvite(String venueId, String memberId) async {
    final headers = await _authHeaders();
    await _api.post(
      '/venues/$venueId/members/$memberId/decline',
      headers: headers,
      body: {},
    );
  }

  /// Venue owner, gönderdiği PENDING daveti iptal eder.
  Future<void> cancelMemberInvite(String venueId, String memberId) async {
    final headers = await _authHeaders();
    await _api.post(
      '/venues/$venueId/members/$memberId/cancel',
      headers: headers,
      body: {},
    );
  }

  // ── My permissions ──────────────────────────────────────────────────────────

  /// Oturum açmış kullanıcının bu venue'daki aktif permission listesini döner.
  Future<List<VenuePermission>> getMyPermissions(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/my-permissions', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    final raw = (map['permissions'] as List? ?? []);
    return raw
        .map((e) => VenuePermissionExt.fromApi(e.toString()))
        .whereType<VenuePermission>()
        .toList();
  }

  // ── User search ─────────────────────────────────────────────────────────────

  /// Venue'ya eklenebilecek kullanıcıları arar.
  /// GET /venues/:venueId/members/search?q=...
  /// Username veya isim içinde arar; zaten üye olanlar dışlanır.
  Future<List<UserSearchResult>> searchUsers(
      String venueId, String query) async {
    if (query.trim().isEmpty) return [];
    final headers = await _authHeaders();
    final encoded = Uri.encodeQueryComponent(query.trim());
    final data = await _api.get(
      '/venues/$venueId/members/search?q=$encoded',
      headers: headers,
    );
    // Backend { users: [...] } döner
    List<dynamic> raw;
    if (data is Map) {
      raw = (data['users'] ?? []) as List;
    } else if (data is List) {
      raw = data;
    } else {
      return [];
    }
    return raw
        .whereType<Map>()
        .map((e) => UserSearchResult.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
