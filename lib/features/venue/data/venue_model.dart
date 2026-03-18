class Venue {
  final String id;
  final String? placeId;
  final String name;
  final String type;
  final String status; // UI derived
  final String address;
  final String city;
  final String photoUrl;
  final double latitude;
  final double longitude;
  final String tag; // UI derived
  final String source; // "google" | "db"
  final bool isInDb;
  final bool canCheckin;
  final int? checkinCountActive;
  final VenueEventSummary? eventSummary;
  final String? verificationLevel;
  final int? distanceMeters;
  final bool? openNow;
  final double? rating;
  final List<String> types;
  Venue({
    required this.id,
    this.placeId,
    required this.name,
    required this.type,
    required this.status,
    required this.address,
    required this.city,
    required this.photoUrl,
    required this.latitude,
    required this.longitude,
    required this.tag,
    this.source = 'db',
    this.isInDb = true,
    this.canCheckin = true,
    this.checkinCountActive,
    this.eventSummary,
    this.verificationLevel,
    this.distanceMeters,
    this.openNow,
    this.rating,
    this.types = const [],
  });

  factory Venue.fromJson(Map<String, dynamic> json) {
    final eventRaw = json['eventSummary'] ?? json['event_summary'];
    final source =
        (json['source'] ?? (json['isInDb'] == true ? 'db' : 'google'))
            .toString()
            .toLowerCase();
    final isInDb = json['isInDb'] == true || json['is_in_db'] == true;
    final checkinCountRaw =
        json['checkinCountActive'] ?? json['checkin_count_active'];
    final canCheckinRaw = json['canCheckin'] ?? json['can_checkin'];
    final distanceRaw = json['distanceMeters'] ?? json['distance_meters'];

    return Venue(
      id: (json['id'] ?? json['placeId'] ?? json['place_id'] ?? '').toString(),
      placeId: (json['placeId'] ?? json['place_id'])?.toString(),
      name: (json['name'] ?? '').toString(),
      type: (json['venueType'] ?? json['venue_type'] ?? json['type'] ?? 'venue')
          .toString(),
      address: (json['address'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      latitude: (json['latitude'] is num)
          ? (json['latitude'] as num).toDouble()
          : 0.0,
      longitude: (json['longitude'] is num)
          ? (json['longitude'] as num).toDouble()
          : 0.0,
      photoUrl: (json['photo'] ?? '').toString(),
      source: source == 'db' ? 'db' : 'google',
      isInDb: isInDb,
      canCheckin: canCheckinRaw is bool ? canCheckinRaw : isInDb,
      checkinCountActive: checkinCountRaw is num
          ? checkinCountRaw.toInt()
          : null,
      eventSummary: eventRaw is Map<String, dynamic>
          ? VenueEventSummary.fromJson(eventRaw)
          : (eventRaw is Map
                ? VenueEventSummary.fromJson(
                    Map<String, dynamic>.from(eventRaw),
                  )
                : null),
      verificationLevel:
          (json['verificationLevel'] ?? json['verification_level'])?.toString(),
      distanceMeters: distanceRaw is num ? distanceRaw.toInt() : null,
      openNow: (json['openNow'] ?? json['open_now']) is bool
          ? (json['openNow'] ?? json['open_now']) as bool
          : null,
      rating: json['rating'] is num ? (json['rating'] as num).toDouble() : null,
      types: (json['types'] is List) ? List<String>.from(json['types']) : [],
      // UI-derived helpers
      status: _computeStatus(json),
      tag: _computeTag(json),
    );
  }

  // ---------- UI HELPERS ----------

  static String _computeStatus(Map<String, dynamic> json) {
    final count = json['checkinCountActive'] ?? json['checkin_count_active'];
    if (count is num) {
      if (count >= 20) return 'Very busy';
      if (count >= 8) return 'Buzzing';
      if (count > 0) return 'Active';
    }
    final source = (json['source'] ?? '').toString().toLowerCase();
    if (source == 'google') return 'Community data pending';
    return 'Open';
  }

  static String _computeTag(Map<String, dynamic> json) {
    final event = json['eventSummary'] ?? json['event_summary'];
    if (event is Map &&
        (event['hasEvent'] == true || event['has_event'] == true)) {
      return '#EventSoon';
    }
    if (json['isInDb'] == false || json['is_in_db'] == false) {
      return '#CommunityDataPending';
    }
    return '#NearbyNow';
  }
}

class VenueEventSummary {
  final bool hasEvent;
  final DateTime? nextStartAt;
  final String? title;

  VenueEventSummary({required this.hasEvent, this.nextStartAt, this.title});

  factory VenueEventSummary.fromJson(Map<String, dynamic> json) {
    final raw = json['nextStartAt'] ?? json['next_start_at'];
    return VenueEventSummary(
      hasEvent: json['hasEvent'] == true || json['has_event'] == true,
      nextStartAt: raw is String ? DateTime.tryParse(raw) : null,
   title: json['title']?.toString(),
    );
  }
}
