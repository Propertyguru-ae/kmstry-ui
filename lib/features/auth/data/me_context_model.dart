class MemberVenue {
  final String id;
  final String name;
  final String? photoUrl;
  final String? role;
  final bool isVerifiedOwner;
  /// 'ACTIVE' | 'PENDING' | 'REJECTED'
  final String status;

  const MemberVenue({
    required this.id,
    required this.name,
    this.photoUrl,
    this.role,
    this.isVerifiedOwner = false,
    this.status = 'ACTIVE',
  });

  bool get isActive => status == 'ACTIVE';
  bool get isPending => status == 'PENDING';
}

class MeContextModel {
  final String? homeRoute;
  final String? nextAction;
  final String? lastActiveContext;
  final String? activeVenueId;
  final bool hasPersonalProfile;
  final bool hasVenueMembership;
  final bool canDeleteCurrentContextProfile;
  final List<MemberVenue> memberVenues;

  const MeContextModel({
    required this.homeRoute,
    required this.nextAction,
    required this.lastActiveContext,
    required this.activeVenueId,
    required this.hasPersonalProfile,
    required this.hasVenueMembership,
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
        final role = (map['role'] ?? map['myRole'])?.toString();
        final isVerifiedOwner = map['isVerifiedOwner'] == true;
        final status = (map['status'])?.toString() ?? 'ACTIVE';
        final photoUrl = (map['photo'] ?? map['photoUrl'] ?? nestedVenue?['photo'])?.toString();
        return MemberVenue(
          id: id,
          name: name,
          photoUrl: (photoUrl != null && photoUrl.isNotEmpty) ? photoUrl : null,
          role: role,
          isVerifiedOwner: isVerifiedOwner,
          status: status,
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
      canDeleteCurrentContextProfile:
          me['canDeleteCurrentContextProfile'] == true ||
          me['can_delete_current_context_profile'] == true,
      memberVenues: parseVenues(me['memberVenues'] ?? me['member_venues']),
    );
  }
}
