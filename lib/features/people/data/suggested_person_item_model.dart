import 'package:kmstry_frontend/features/people/data/username_search_item_model.dart';

class SuggestedPersonItem {
  final String id;
  final String username;
  final String? fullName;
  final String? photo;
  final DateTime? birthdate;
  final String? bio;
  final int sharedVenueCount;
  final String suggestionReason;
  final SuggestedPersonVenue? sharedVenue;
  final UsernameSearchActiveCheckin? activeCheckin;

  const SuggestedPersonItem({
    required this.id,
    required this.username,
    this.fullName,
    this.photo,
    this.birthdate,
    this.bio,
    required this.sharedVenueCount,
    required this.suggestionReason,
    this.sharedVenue,
    this.activeCheckin,
  });

  factory SuggestedPersonItem.fromJson(Map<String, dynamic> json) {
    final sharedRaw = json['sharedVenue'] ?? json['shared_venue'];
    final activeRaw = json['activeCheckin'] ?? json['active_checkin'];
    final sharedVenue = sharedRaw is Map
        ? SuggestedPersonVenue.fromJson(Map<String, dynamic>.from(sharedRaw))
        : null;
    final activeCheckin = activeRaw is Map
        ? UsernameSearchActiveCheckin.fromJson(
            Map<String, dynamic>.from(activeRaw),
          )
        : null;

    String? readString(List<String> keys) {
      for (final key in keys) {
        final raw = json[key];
        if (raw == null) continue;
        final value = raw.toString().trim();
        if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
      }
      return null;
    }

    return SuggestedPersonItem(
      id: (json['id'] ?? '').toString(),
      username: (json['username'] ?? '').toString(),
      fullName: readString(const ['fullName', 'full_name']),
      photo: readString(const ['photo', 'photoUrl', 'photo_url']),
      birthdate: DateTime.tryParse((json['birthdate'] ?? '').toString()),
      bio: readString(const ['bio', 'about', 'aboutMe']),
      sharedVenueCount:
          int.tryParse(
            (json['sharedVenueCount'] ?? json['shared_venue_count'] ?? 0)
                .toString(),
          ) ??
          0,
      suggestionReason:
          readString(const ['suggestionReason', 'suggestion_reason']) ??
          'You both visited similar places',
      sharedVenue: sharedVenue,
      activeCheckin: activeCheckin,
    );
  }

  String get displayName {
    final name = fullName?.trim();
    if (name != null && name.isNotEmpty) return name;
    return username.isNotEmpty ? '@$username' : 'New person';
  }
}

class SuggestedPersonVenue {
  final String id;
  final String name;
  final String? type;
  final String? photo;

  const SuggestedPersonVenue({
    required this.id,
    required this.name,
    this.type,
    this.photo,
  });

  factory SuggestedPersonVenue.fromJson(Map<String, dynamic> json) {
    return SuggestedPersonVenue(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      type: json['type']?.toString(),
      photo: json['photo']?.toString(),
    );
  }
}
