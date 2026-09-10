class UsernameSearchItem {
  final String id;
  final String username;
  final String? fullName;
  final String? photo;
  final DateTime? birthdate;
  final UsernameSearchActiveCheckin? activeCheckin;
  final bool isMatched;
  final String? chatId;
  final String? myAction;
  final String? theirAction;
  final String? relationshipState;
  final String? bio;

  UsernameSearchItem({
    required this.id,
    required this.username,
    this.fullName,
    this.photo,
    this.birthdate,
    this.activeCheckin,
    this.isMatched = false,
    this.chatId,
    this.myAction,
    this.theirAction,
    this.relationshipState,
    this.bio,
  });

  factory UsernameSearchItem.fromJson(Map<String, dynamic> json) {
    final activeRaw = json['activeCheckin'] ?? json['active_checkin'];
    final relationshipRaw = json['relationship'];
    UsernameSearchActiveCheckin? active;
    Map<String, dynamic>? relationship;
    if (activeRaw is Map) {
      active = UsernameSearchActiveCheckin.fromJson(
        Map<String, dynamic>.from(activeRaw),
      );
    }
    if (relationshipRaw is Map) {
      relationship = Map<String, dynamic>.from(relationshipRaw);
    }

    String? readString(Map<String, dynamic> map, List<String> keys) {
      for (final key in keys) {
        final raw = map[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') {
          return value;
        }
      }
      return null;
    }

    Map<String, dynamic>? asMap(dynamic value) {
      if (value is Map) return Map<String, dynamic>.from(value);
      return null;
    }

    final relation = relationship ?? const <String, dynamic>{};
    final relationMyAction = asMap(relation['myAction']);
    final relationTheirAction = asMap(relation['theirAction']);
    final relationMatch = asMap(relation['match']);

    final myAction = readString(relationMyAction ?? relation, const [
      'action',
      'myActionAtThisVenue',
      'my_action_at_this_venue',
      'myAction',
      'my_action',
      'feedAction',
      'feed_action',
    ]);
    final theirAction = readString(relationTheirAction ?? relation, const [
      'action',
      'theirActionAtThisVenue',
      'their_action_at_this_venue',
      'theirAction',
      'their_action',
      'incomingAction',
      'incoming_action',
      'actionFromOtherUser',
      'action_from_other_user',
    ]);
    final relationshipState = readString(relation, const [
      'state',
      'status',
      'relationshipState',
      'relationship_state',
      'actionState',
      'action_state',
    ]);
    final chatId = readString(relationMatch ?? relation, const [
      'chatId',
      'chat_id',
    ]);
    final isMatchedRaw =
        relation['isMatched'] ??
        relation['is_matched'] ??
        relationMatch != null;
    final status = relationshipState?.toLowerCase();
    final isMatched =
        isMatchedRaw == true ||
        isMatchedRaw.toString() == 'true' ||
        status == 'matched';

    return UsernameSearchItem(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      fullName: (json['fullName'] ?? json['full_name'])?.toString(),
      photo: readString(json, const ['photo', 'photoUrl', 'photo_url']),
      birthdate: DateTime.tryParse((json['birthdate'] ?? '').toString()),
      activeCheckin: active,
      isMatched: isMatched,
      chatId: chatId,
      myAction: myAction?.toLowerCase(),
      theirAction: theirAction?.toLowerCase(),
      relationshipState: status,
      bio: readString(json, const ['bio', 'bio_text', 'about', 'aboutMe']),
    );
  }
}

class UsernameSearchActiveCheckin {
  final String id;
  final String? venueId;
  final String? venueName;
  final String? venueType;
  final String? venuePhoto;
  final DateTime? expiresAt;

  UsernameSearchActiveCheckin({
    required this.id,
    this.venueId,
    this.venueName,
    this.venueType,
    this.venuePhoto,
    this.expiresAt,
  });

  factory UsernameSearchActiveCheckin.fromJson(Map<String, dynamic> json) {
    final venueRaw = json['venue'];
    final venue = venueRaw is Map<String, dynamic> ? venueRaw : null;
    return UsernameSearchActiveCheckin(
      id: (json['id'] ?? '').toString(),
      venueId: (json['venueId'] ?? json['venue_id'])?.toString(),
      venueName: (json['venueName'] ?? json['venue_name'] ?? venue?['name'])
          ?.toString(),
      venueType: (json['venueType'] ?? json['venue_type'] ?? venue?['type'])
          ?.toString(),
      venuePhoto: (json['venuePhoto'] ?? json['venue_photo'] ?? venue?['photo'])
          ?.toString(),
      expiresAt: DateTime.tryParse(
        (json['expiresAt'] ?? json['expires_at'] ?? '').toString(),
      ),
    );
  }
}
