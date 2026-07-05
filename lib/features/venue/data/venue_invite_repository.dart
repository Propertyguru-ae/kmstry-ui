import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_member_model.dart';

class VenueInviteInfo {
  final String id;
  final String token;
  final String role;
  final String roleName;
  final String expiresAt;
  final bool isExpired;
  final bool isUsed;
  final bool isValid;
  final VenueInviteVenue venue;

  const VenueInviteInfo({
    required this.id,
    required this.token,
    required this.role,
    required this.roleName,
    required this.expiresAt,
    required this.isExpired,
    required this.isUsed,
    required this.isValid,
    required this.venue,
  });

  factory VenueInviteInfo.fromJson(Map<String, dynamic> json) {
    return VenueInviteInfo(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      roleName: json['roleName']?.toString() ?? json['role']?.toString() ?? '',
      expiresAt: json['expiresAt']?.toString() ?? '',
      isExpired: json['isExpired'] == true,
      isUsed: json['isUsed'] == true,
      isValid: json['isValid'] == true,
      venue: VenueInviteVenue.fromJson(
        Map<String, dynamic>.from(json['venue'] as Map? ?? {}),
      ),
    );
  }
}

class VenueInviteVenue {
  final String id;
  final String name;
  final String? photo;
  final String type;
  final String? city;

  const VenueInviteVenue({
    required this.id,
    required this.name,
    this.photo,
    required this.type,
    this.city,
  });

  factory VenueInviteVenue.fromJson(Map<String, dynamic> json) {
    return VenueInviteVenue(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      photo: json['photo']?.toString(),
      type: json['type']?.toString() ?? '',
      city: json['city']?.toString(),
    );
  }
}

class CreatedInvite {
  final String id;
  final String token;
  final String inviteUrl;
  final String role;
  final String? venueRoleName;
  final String expiresAt;

  const CreatedInvite({
    required this.id,
    required this.token,
    required this.inviteUrl,
    required this.role,
    this.venueRoleName,
    required this.expiresAt,
  });

  factory CreatedInvite.fromJson(Map<String, dynamic> json) {
    return CreatedInvite(
      id: json['id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      inviteUrl: json['inviteUrl']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      venueRoleName: json['venueRoleName']?.toString(),
      expiresAt: json['expiresAt']?.toString() ?? '',
    );
  }

  String get roleDisplay => venueRoleName ?? role;
}

/// createInvite şu sonuçları döndürebilir:
/// - [linkCreated]: girilen email'in hesabı yok → web kayıt linki oluştu
/// - [existingUserRequestSent]: email zaten bir hesaba ait → username daveti
///   gibi in-app istek gönderildi (push + bildirim)
/// - [alreadyMember]: email zaten bu venue'nun aktif üyesi
/// - [alreadyInvited]: email için bekleyen bir davet zaten var
enum InviteResultType {
  linkCreated,
  existingUserRequestSent,
  alreadyMember,
  alreadyInvited,
}

class InviteResult {
  final InviteResultType type;
  final String email;
  final String role;

  // Sadece linkCreated durumunda dolu:
  final String? id;
  final String? token;
  final String? inviteUrl;
  final String? venueRoleName;
  final String? expiresAt;

  const InviteResult({
    required this.type,
    required this.email,
    required this.role,
    this.id,
    this.token,
    this.inviteUrl,
    this.venueRoleName,
    this.expiresAt,
  });

  bool get isLink => type == InviteResultType.linkCreated;

  factory InviteResult.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type']?.toString();
    final type = switch (typeStr) {
      'EXISTING_USER_REQUEST_SENT' => InviteResultType.existingUserRequestSent,
      'ALREADY_MEMBER' => InviteResultType.alreadyMember,
      'ALREADY_INVITED' => InviteResultType.alreadyInvited,
      _ => InviteResultType.linkCreated,
    };
    return InviteResult(
      type: type,
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      id: json['id']?.toString(),
      token: json['token']?.toString(),
      inviteUrl: json['inviteUrl']?.toString(),
      venueRoleName: json['venueRoleName']?.toString(),
      expiresAt: json['expiresAt']?.toString(),
    );
  }
}

class VenueInviteRepository {
  final ApiClient _api = ApiClient();

  Future<Map<String, String>> _authHeaders() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<VenueInviteInfo> getInvite(String token) async {
    final data = await _api.get('/invites/$token');
    return VenueInviteInfo.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> acceptInvite(String token) async {
    final headers = await _authHeaders();
    await _api.post('/invites/$token/accept', headers: headers, body: {});
  }

  Future<InviteResult> createInvite({
    required String venueId,
    required String email,
    required VenueMemberRole role,
    String? venueRoleId,
    int expiresInDays = 7,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'email': email.trim(),
      'role': role.apiValue,
      'expiresInDays': expiresInDays,
    };
    if (venueRoleId != null) body['venueRoleId'] = venueRoleId;

    final data = await _api.post(
      '/venues/$venueId/invites',
      headers: headers,
      body: body,
    );
    return InviteResult.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<List<CreatedInvite>> listInvites(String venueId) async {
    final headers = await _authHeaders();
    final data = await _api.get('/venues/$venueId/invites', headers: headers);
    final map = Map<String, dynamic>.from(data as Map);
    final raw = map['invites'] as List? ?? [];
    return raw
        .whereType<Map>()
        .map((e) => CreatedInvite.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> revokeInvite(String venueId, String inviteId) async {
    final headers = await _authHeaders();
    await _api.delete('/venues/$venueId/invites/$inviteId', headers: headers);
  }

  // Returns true if there's a pending invite claimed for this email on the web landing page.
  // Used before OTP to catch wrong-email mistakes early in the invite signup flow.
  Future<bool> checkInviteEmail(String email) async {
    try {
      final data = await _api.post(
        '/invites/check-email',
        body: {'email': email},
      );
      final map = Map<String, dynamic>.from(data as Map);
      return map['found'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> declineInvite(String token) async {
    final headers = await _authHeaders();
    await _api.post('/invites/$token/decline', headers: headers, body: {});
  }

  // Returns the pending invite for the logged-in user (matched by claimed email), or null.
  Future<VenueInviteInfo?> getPendingInvite() async {
    try {
      final headers = await _authHeaders();
      final data = await _api.get('/invites/pending', headers: headers);
      if (data == null) return null;
      return VenueInviteInfo.fromJson(Map<String, dynamic>.from(data as Map));
    } catch (_) {
      return null;
    }
  }
}
