import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';

class VenueOwnerStatsVenue {
  final String id;
  final String name;
  final String? photo;
  final String? description;
  final String? type;
  final String? address;
  final String? city;
  final String? verificationLevel;
  final List<VenueUpcomingEvent> upcomingEvents;

  const VenueOwnerStatsVenue({
    required this.id,
    required this.name,
    this.photo,
    this.description,
    this.type,
    this.address,
    this.city,
    this.verificationLevel,
    this.upcomingEvents = const [],
  });

  factory VenueOwnerStatsVenue.fromJson(Map<String, dynamic> json) {
    final eventsRaw =
        (json['upcomingEvents'] ?? json['upcoming_events']) as List? ?? [];
    return VenueOwnerStatsVenue(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      photo: json['photo']?.toString(),
      description: json['description']?.toString(),
      type: json['type']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      verificationLevel:
          (json['verificationLevel'] ?? json['verification_level'])?.toString(),
      upcomingEvents: eventsRaw
          .whereType<Map>()
          .map((e) =>
              VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class VenueWeeklyTrendPoint {
  final String date;
  final int count;

  const VenueWeeklyTrendPoint({required this.date, required this.count});

  factory VenueWeeklyTrendPoint.fromJson(Map<String, dynamic> json) {
    return VenueWeeklyTrendPoint(
      date: json['date']?.toString() ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class VenueOwnerStats {
  final int activeNow;
  final int maleNow;
  final int femaleNow;
  final int todayTotal;
  final int totalAllTime;
  final List<VenueWeeklyTrendPoint> weeklyTrend;
  final int followerCount;
  final int storyViewsToday;

  const VenueOwnerStats({
    required this.activeNow,
    required this.maleNow,
    required this.femaleNow,
    required this.todayTotal,
    required this.totalAllTime,
    required this.weeklyTrend,
    this.followerCount = 0,
    this.storyViewsToday = 0,
  });

  factory VenueOwnerStats.fromJson(Map<String, dynamic> json) {
    final trend = (json['weeklyTrend'] ?? json['weekly_trend']) as List? ?? [];
    return VenueOwnerStats(
      activeNow: (json['activeNow'] ?? json['active_now'] as num? ?? 0).toInt(),
      maleNow: (json['maleNow'] ?? json['male_now'] as num? ?? 0).toInt(),
      femaleNow: (json['femaleNow'] ?? json['female_now'] as num? ?? 0).toInt(),
      todayTotal: (json['todayTotal'] ?? json['today_total'] as num? ?? 0).toInt(),
      totalAllTime: (json['totalAllTime'] ?? json['total_all_time'] as num? ?? 0).toInt(),
      weeklyTrend: trend
          .whereType<Map>()
          .map((e) => VenueWeeklyTrendPoint.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      followerCount: (json['followerCount'] ?? json['follower_count'] as num? ?? 0).toInt(),
      storyViewsToday: (json['storyViewsToday'] ?? json['story_views_today'] as num? ?? 0).toInt(),
    );
  }
}

class VenueActiveGuest {
  final String id;
  final String? username;
  final String? fullName;
  final String? photo;
  final String? featuredPhoto;
  final String? gender;
  final String checkinId;
  final List<StoryItem> stories;
  final Set<String> viewedStoryIds;

  const VenueActiveGuest({
    required this.id,
    this.username,
    this.fullName,
    this.photo,
    this.featuredPhoto,
    this.gender,
    required this.checkinId,
    this.stories = const [],
    this.viewedStoryIds = const {},
  });

  factory VenueActiveGuest.fromJson(Map<String, dynamic> json) {
    final storiesRaw = json['stories'] as List? ?? [];
    return VenueActiveGuest(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString(),
      fullName: (json['fullName'] ?? json['full_name'])?.toString(),
      photo: json['photo']?.toString(),
      featuredPhoto: (json['featuredPhoto'] ?? json['featured_photo'])?.toString(),
      gender: json['gender']?.toString(),
      checkinId: (json['checkinId'] ?? json['checkin_id'])?.toString() ?? '',
      stories: storiesRaw.map((e) => StoryItem(
        id: e['id']?.toString() ?? '',
        mediaUrl: e['mediaUrl']?.toString() ?? '',
        mediaType: e['mediaType']?.toString() ?? 'photo',
        thumbnailUrl: e['thumbnailUrl']?.toString(),
        durationSecs: (e['durationSecs'] as num?)?.toInt(),
        expiresAt: DateTime.tryParse(e['expiresAt']?.toString() ?? '') ?? DateTime.now().add(const Duration(hours: 24)),
        createdAt: DateTime.tryParse(e['createdAt']?.toString() ?? '') ?? DateTime.now(),
      )).toList(),
      viewedStoryIds: Set<String>.from(
        storiesRaw.where((e) => e['viewedByMe'] == true).map((e) => e['id']?.toString() ?? ''),
      ),
    );
  }

  String get displayName {
    if (fullName != null && fullName!.isNotEmpty) return fullName!;
    if (username != null && username!.isNotEmpty) return '@$username';
    return 'Guest';
  }
}

class VenueOwnerStatsResponse {
  final VenueOwnerStatsVenue venue;
  final VenueOwnerStats stats;
  final List<VenueActiveGuest> activeGuests;

  const VenueOwnerStatsResponse({
    required this.venue,
    required this.stats,
    required this.activeGuests,
  });

  factory VenueOwnerStatsResponse.fromJson(Map<String, dynamic> json) {
    final venueMap = json['venue'] as Map? ?? {};
    final statsMap = json['stats'] as Map? ?? {};
    final guestsRaw = json['activeGuests'] ?? json['active_guests'] ?? [];
    return VenueOwnerStatsResponse(
      venue: VenueOwnerStatsVenue.fromJson(
          Map<String, dynamic>.from(venueMap)),
      stats: VenueOwnerStats.fromJson(Map<String, dynamic>.from(statsMap)),
      activeGuests: (guestsRaw as List)
          .whereType<Map>()
          .map((e) =>
              VenueActiveGuest.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}
