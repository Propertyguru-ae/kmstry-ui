class MemberVenue {
  final String id;
  /// VenueMember kaydının ID'si — accept/decline çağrılarında kullanılır
  final String? membershipId;
  final String name;
  final String? photoUrl;
  final String? role;
  final bool isVerifiedOwner;
  /// 'ACTIVE' | 'PENDING' | 'REJECTED'
  final String status;
  final bool hasDocuments;
  final String? address;
  final String? inviterName;

  const MemberVenue({
    required this.id,
    this.membershipId,
    required this.name,
    this.photoUrl,
    this.role,
    this.isVerifiedOwner = false,
    this.status = 'ACTIVE',
    this.hasDocuments = false,
    this.address,
    this.inviterName,
  });

  bool get isActive => status == 'ACTIVE';
  bool get isPending => status == 'PENDING';
  bool get isRejected => status == 'REJECTED';
  bool get isPendingOwnerClaim => isPending && role?.toUpperCase() == 'OWNER';
  /// Owner'ın claim'i değil, başkası tarafından eklenmiş davet
  bool get isPendingMemberInvite => isPending && role != null && role!.toUpperCase() != 'OWNER';
  bool get isRejectedOwnerClaim => isRejected && role?.toUpperCase() == 'OWNER';
}

class MeContextModel {
  final String? homeRoute;
  final String? nextAction;
  final String? lastActiveContext;
  final String? activeVenueId;
  final bool hasPersonalProfile;
  final bool hasVenueMembership;
  final bool hasRejectedClaimOnly;
  final bool canDeleteCurrentContextProfile;
  final List<MemberVenue> memberVenues;

  const MeContextModel({
    required this.homeRoute,
    required this.nextAction,
    required this.lastActiveContext,
    required this.activeVenueId,
    required this.hasPersonalProfile,
    required this.hasVenueMembership,
    this.hasRejectedClaimOnly = false,
    required this.canDeleteCurrentContextProfile,
    required this.memberVenues,
  });

  factory MeContextModel.fromMe(Map<String, dynamic> me) {
    List<MemberVenue> parseVenues(dynamic raw) {
      if (raw is! List) return const [];
      return raw.whereType<Map>().map((item) {
        final map = Map<String, dynamic>.from(item);
        final nestedVenue = map['venue'] is Map
            ? Map<String, dynamic>.from(map['venue'] as Map)
            : null;
        final id =
            (map['id'] ??
                    map['venue_id'] ??
                    map['venueId'] ??
                    nestedVenue?['id'] ??
                    '')
                .toString();
        final name =
            (map['name'] ??
                    map['venue_name'] ??
                    map['venueName'] ??
                    nestedVenue?['name'] ??
                    'Venue')
                .toString();
        final membershipId = (map['membershipId'] ?? map['membership_id'])?.toString();
        final role = (map['role'] ?? map['myRole'])?.toString();
        final isVerifiedOwner = map['isVerifiedOwner'] == true;
        final status = (map['status'])?.toString() ?? 'ACTIVE';
        final hasDocuments = map['hasDocuments'] == true || map['has_documents'] == true;
        final photoUrl = (map['photo'] ?? map['photoUrl'] ?? nestedVenue?['photo'])?.toString();
        final address = (map['address'] ?? nestedVenue?['address'])?.toString();
        final inviterName = (map['inviterName'] ?? map['inviter_name'])?.toString();
        return MemberVenue(
          id: id,
          membershipId: membershipId,
          name: name,
          photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
          role: role,
          isVerifiedOwner: isVerifiedOwner,
          status: status,
          hasDocuments: hasDocuments,
          address: (address != null && address.isNotEmpty) ? address : null,
          inviterName: (inviterName != null && inviterName.isNotEmpty) ? inviterName : null,
        );
      }).where((venue) => venue.id.isNotEmpty).toList();
    }

    return MeContextModel(
      homeRoute: (me['homeRoute'] ?? me['home_route'])?.toString(),
      nextAction: (me['nextAction'] ?? me['next_action'])?.toString(),
      lastActiveContext:
          (me['lastActiveContext'] ?? me['last_active_context'])?.toString(),
      activeVenueId:
          (me['activeVenueId'] ?? me['active_venue_id'])?.toString(),
      hasPersonalProfile:
          me['hasPersonalProfile'] == true || me['has_personal_profile'] == true,
      hasVenueMembership:
          me['hasVenueMembership'] == true || me['has_venue_membership'] == true,
      hasRejectedClaimOnly:
          me['hasRejectedClaimOnly'] == true || me['has_rejected_claim_only'] == true,
      canDeleteCurrentContextProfile:
          me['canDeleteCurrentContextProfile'] == true ||
          me['can_delete_current_context_profile'] == true,
      memberVenues: parseVenues(me['memberVenues'] ?? me['member_venues']),
    );
  }
}
