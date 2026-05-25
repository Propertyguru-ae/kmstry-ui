import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_member_model.dart';

class VenueInviteInfo {
  final String id;
  final String role;
  final String roleName;
  final String expiresAt;
  final bool isExpired;
  final bool isUsed;
  final bool isValid;
  final VenueInviteVenue venue;

  const VenueInviteInfo({
    required this.id,
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

  Future<CreatedInvite> createInvite({
    required String venueId,
    required VenueMemberRole role,
    String? venueRoleId,
    int expiresInDays = 7,
  }) async {
    final headers = await _authHeaders();
    final body = <String, dynamic>{
      'role': role.apiValue,
      'expiresInDays': expiresInDays,
    };
    if (venueRoleId != null) body['venueRoleId'] = venueRoleId;

    final data = await _api.post(
      '/venues/$venueId/invites',
      headers: headers,
      body: body,
    );
    return CreatedInvite.fromJson(Map<String, dynamic>.from(data as Map));
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
}
