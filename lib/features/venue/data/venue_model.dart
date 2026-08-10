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
