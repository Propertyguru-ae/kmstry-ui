import 'dart:math' as math;

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
  /// Active check-ins reported as male (optional; from API).
  final int? checkinCountMale;
  /// Active check-ins reported as female (optional; from API).
  final int? checkinCountFemale;
  final VenueEventSummary? eventSummary;
  final String? verificationLevel;
  final int? distanceMeters;
  final bool? openNow;
  final double? rating;
  final List<String> types;
  final String? description;
  final Map<String, dynamic>? openingHours;
  final List<VenueUpcomingEvent> upcomingEvents;

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
    this.checkinCountMale,
    this.checkinCountFemale,
    this.eventSummary,
    this.verificationLevel,
    this.distanceMeters,
    this.openNow,
    this.rating,
    this.types = const [],
    this.description,
    this.openingHours,
    this.upcomingEvents = const [],
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
    int? maleCount = _parseOptionalInt(
      json['checkinCountMale'] ??
          json['checkin_count_male'] ??
          json['maleCheckinCount'] ??
          json['male_checkin_count'] ??
          json['checkinsMale'] ??
          json['checkins_male'],
    );
    int? femaleCount = _parseOptionalInt(
      json['checkinCountFemale'] ??
          json['checkin_count_female'] ??
          json['femaleCheckinCount'] ??
          json['female_checkin_count'] ??
          json['checkinsFemale'] ??
          json['checkins_female'],
    );
    final genderBreakRaw =
        json['checkinGenderBreakdown'] ?? json['checkin_gender_breakdown'];
    if (genderBreakRaw is Map) {
      final g = Map<dynamic, dynamic>.from(genderBreakRaw);
      maleCount ??= _parseOptionalInt(
        g['male'] ?? g['m'] ?? g['men'] ?? g['man'],
      );
      femaleCount ??= _parseOptionalInt(
        g['female'] ?? g['f'] ?? g['women'] ?? g['woman'],
      );
    }
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
      checkinCountMale: maleCount,
      checkinCountFemale: femaleCount,
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
      description: json['description']?.toString(),
      openingHours: json['openingHours'] is Map
          ? Map<String, dynamic>.from(json['openingHours'] as Map)
          : json['opening_hours'] is Map
              ? Map<String, dynamic>.from(json['opening_hours'] as Map)
              : null,
      upcomingEvents: (json['upcomingEvents'] ?? json['upcoming_events']) is List
          ? (json['upcomingEvents'] ?? json['upcoming_events'] as List)
              .whereType<Map>()
              .map<VenueUpcomingEvent>((e) => VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(e)))
              .toList()
          : const <VenueUpcomingEvent>[],
      // UI-derived helpers
      status: _computeStatus(json),
      tag: _computeTag(json),
    );
  }

  static int? _parseOptionalInt(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  // ---------- UI HELPERS ----------

  static String _computeStatus(Map<String, dynamic> json) {
    final count = json['checkinCountActive'] ?? json['checkin_count_active'];
    if (count is num) {
      if (count >= 20) return 'Very busy';
      if (count >= 8) return 'Buzzing';
      if (count > 0) return 'Active';
    }
    //final source = (json['source'] ?? '').toString().toLowerCase();
    // if (source == 'google') return 'Community data pending'; //Bu mekan bulundu ama henüz community activity oluşmadı.
    return 'Quiet right now';
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

  /// Same physical venue may appear in API `mapItems` vs `items` with different ids
  /// (e.g. placeId vs DB uuid). Used to merge check-in stats onto map pins.
  bool isSameVenueAs(Venue other) {
    if (id.isNotEmpty && id == other.id) return true;
    final p = placeId;
    final op = other.placeId;
    if (p != null && p.isNotEmpty && p == other.id) return true;
    if (op != null && op.isNotEmpty && op == id) return true;
    if (p != null &&
        op != null &&
        p.isNotEmpty &&
        op.isNotEmpty &&
        p == op) {
      return true;
    }
    // Same place from Google vs DB rows (different ids, missing placeId on one side).
    if (_venuesRoughSameLocation(this, other) &&
        _venueNamesLikelySame(name, other.name)) {
      return true;
    }
    return false;
  }

  /// Prefer non-null check-in fields from [other] when this venue has gaps.
  Venue mergeCheckinFieldsFrom(Venue other) {
    return Venue(
      id: id,
      placeId: placeId,
      name: name,
      type: type,
      status: status,
      address: address,
      city: city,
      photoUrl: photoUrl,
      latitude: latitude,
      longitude: longitude,
      tag: tag,
      source: source,
      isInDb: isInDb,
      canCheckin: canCheckin,
      checkinCountActive: checkinCountActive ?? other.checkinCountActive,
      checkinCountMale: checkinCountMale ?? other.checkinCountMale,
      checkinCountFemale: checkinCountFemale ?? other.checkinCountFemale,
      eventSummary: eventSummary,
      verificationLevel: verificationLevel,
      distanceMeters: distanceMeters,
      openNow: openNow,
      rating: rating,
      types: types,
      description: description ?? other.description,
      openingHours: openingHours ?? other.openingHours,
      upcomingEvents: upcomingEvents.isNotEmpty ? upcomingEvents : other.upcomingEvents,
    );
  }
}

/// ~100m — enough for map/list coordinate jitter; avoids false matches when names differ.
bool _venuesRoughSameLocation(Venue a, Venue b, {double maxKm = 0.1}) {
  if (!(a.latitude.isFinite &&
      b.latitude.isFinite &&
      a.longitude.isFinite &&
      b.longitude.isFinite)) {
    return false;
  }
  if (a.latitude == 0 &&
      a.longitude == 0 &&
      b.latitude == 0 &&
      b.longitude == 0) {
    return false;
  }
  final dLat = (a.latitude - b.latitude).abs();
  final dLng = (a.longitude - b.longitude).abs();
  final latRad = a.latitude * math.pi / 180.0;
  final kmLat = dLat * 111.0;
  final kmLng = dLng * 111.0 * math.cos(latRad).abs().clamp(0.2, 1.0);
  final km = math.sqrt(kmLat * kmLat + kmLng * kmLng);
  return km <= maxKm;
}

bool _venueNamesLikelySame(String a, String b) {
  final na = a.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  final nb = b.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (na.isEmpty || nb.isEmpty) return false;
  if (na == nb) return true;
  if (na.length >= 6 && nb.length >= 6 && (na.contains(nb) || nb.contains(na))) {
    return true;
  }
  return false;
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

class VenueUpcomingEvent {
  final String id;
  final String title;
  final String? description;
  final DateTime startAt;
  final DateTime endAt;
  final String? photo;
  final List<String> photos;
  final int? priceAed;

  VenueUpcomingEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startAt,
    required this.endAt,
    this.photo,
    this.photos = const [],
    this.priceAed,
  });

  factory VenueUpcomingEvent.fromJson(Map<String, dynamic> json) {
    final startRaw = json['startAt'] ?? json['start_at'] ?? '';
    final endRaw = json['endAt'] ?? json['end_at'] ?? '';
    return VenueUpcomingEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      startAt: DateTime.tryParse(startRaw.toString()) ?? DateTime.now(),
      endAt: DateTime.tryParse(endRaw.toString()) ?? DateTime.now(),
      photo: json['photo']?.toString(),
      photos: (json['photos'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      priceAed: json['priceAed'] is num
          ? (json['priceAed'] as num).toInt()
          : json['price_aed'] is num
              ? (json['price_aed'] as num).toInt()
              : null,
    );
  }

  /// Returns e.g. "Fri, 30 May · 21:00"
  String get formattedDate {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final s = startAt.toLocal();
    final e = endAt.toLocal();
    final dayName   = days[(s.weekday - 1) % 7];
    final monthName = months[s.month - 1];
    final sH = s.hour.toString().padLeft(2, '0');
    final sM = s.minute.toString().padLeft(2, '0');
    final eH = e.hour.toString().padLeft(2, '0');
    final eM = e.minute.toString().padLeft(2, '0');

    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) {
      return '$dayName, ${s.day} $monthName · $sH:$sM → $eH:$eM';
    }
    final eDayName   = days[(e.weekday - 1) % 7];
    final eMonthName = months[e.month - 1];
    return '$dayName, ${s.day} $monthName $sH:$sM → $eDayName, ${e.day} $eMonthName $eH:$eM';
  }
}
