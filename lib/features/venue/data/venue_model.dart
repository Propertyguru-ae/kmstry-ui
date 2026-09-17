import 'dart:math' as math;

import 'package:kmstry_frontend/core/media/media_reference.dart';

class Venue {
  final String id;
  final String? placeId;
  final String name;
  final String type;
  final String status; // UI derived
  final String address;
  final String city;
  final String photoUrl;
  final MediaReference? photoReference;
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
  final int? ratingCount;
  final List<String> types;
  final String? description;
  final List<String> photos;
  final Map<String, dynamic>? openingHours;
  final List<VenueUpcomingEvent> upcomingEvents;
  final bool isFollowing;
  final int followerCount;
  final String? recommendationReason;

  /// Aktif external partnership platformları (THE_ENTERTAINER, FAZAA, ...).
  /// Harita partnership filtresi için kullanılır.
  final List<String> partnershipPlatforms;

  Venue({
    required this.id,
    this.placeId,
    required this.name,
    required this.type,
    required this.status,
    required this.address,
    required this.city,
    required this.photoUrl,
    this.photoReference,
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
    this.ratingCount,
    this.types = const [],
    this.description,
    this.photos = const [],
    this.openingHours,
    this.upcomingEvents = const [],
    this.isFollowing = false,
    this.followerCount = 0,
    this.recommendationReason,
    this.partnershipPlatforms = const [],
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
    final resolvedId = (json['id'] ?? json['placeId'] ?? json['place_id'] ?? '')
        .toString();
    final photoReference = MediaReference.venuePhoto(
      json,
      venueId: resolvedId,
      allowRefresh: isInDb && source == 'db',
    );

    return Venue(
      id: resolvedId,
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
      photoUrl: photoReference.url,
      photoReference: photoReference.url.isNotEmpty || photoReference.canRefresh
          ? photoReference
          : null,
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
      ratingCount: _parseRatingCount(json),
      types: (json['types'] is List) ? List<String>.from(json['types']) : [],
      description: json['description']?.toString(),
      photos: _parsePhotoList(json),
      openingHours: json['openingHours'] is Map
          ? Map<String, dynamic>.from(json['openingHours'] as Map)
          : json['opening_hours'] is Map
          ? Map<String, dynamic>.from(json['opening_hours'] as Map)
          : null,
      upcomingEvents:
          (json['upcomingEvents'] ?? json['upcoming_events']) is List
          ? (json['upcomingEvents'] ?? json['upcoming_events'] as List)
                .whereType<Map>()
                .map<VenueUpcomingEvent>(
                  (e) =>
                      VenueUpcomingEvent.fromJson(Map<String, dynamic>.from(e)),
                )
                .toList()
          : const <VenueUpcomingEvent>[],
      isFollowing: (json['isFollowing'] ?? json['is_following']) == true,
      followerCount:
          _parseOptionalInt(json['followerCount'] ?? json['follower_count']) ??
          0,
      recommendationReason:
          (json['recommendationReason'] ?? json['recommendation_reason'])
              ?.toString(),
      partnershipPlatforms:
          (json['partnershipPlatforms'] ?? json['partnership_platforms'])
              is List
          ? List<String>.from(
              (json['partnershipPlatforms'] ?? json['partnership_platforms'])
                  as List,
            )
          : const <String>[],
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

  static int? _parseRatingCount(Map<String, dynamic> json) {
    final direct = _parseOptionalInt(
      json['ratingCount'] ??
          json['rating_count'] ??
          json['reviewCount'] ??
          json['review_count'] ??
          json['userRatingsTotal'] ??
          json['user_ratings_total'] ??
          json['ratingsTotal'] ??
          json['ratings_total'],
    );
    if (direct != null) return direct;
    final reviews = json['reviews'];
    if (reviews is List) return reviews.length;
    return _parseOptionalInt(reviews);
  }

  static List<String> _parsePhotoList(Map<String, dynamic> json) {
    final raw =
        json['photos'] ??
        json['gallery'] ??
        json['images'] ??
        json['photoUrls'] ??
        json['photo_urls'];
    if (raw is! List) return const <String>[];
    return raw
        .map((item) {
          if (item is String) return item;
          if (item is Map) {
            return (item['url'] ??
                    item['photo'] ??
                    item['photoUrl'] ??
                    item['photo_url'] ??
                    item['imageUrl'] ??
                    item['image_url'])
                ?.toString();
          }
          return null;
        })
        .whereType<String>()
        .where((url) => url.trim().isNotEmpty)
        .toSet()
        .toList();
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
    if (p != null && op != null && p.isNotEmpty && op.isNotEmpty && p == op) {
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
      photoReference: photoReference ?? other.photoReference,
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
      ratingCount: ratingCount ?? other.ratingCount,
      types: types,
      description: description ?? other.description,
      photos: photos.isNotEmpty ? photos : other.photos,
      openingHours: openingHours ?? other.openingHours,
      upcomingEvents: upcomingEvents.isNotEmpty
          ? upcomingEvents
          : other.upcomingEvents,
      partnershipPlatforms: partnershipPlatforms.isNotEmpty
          ? partnershipPlatforms
          : other.partnershipPlatforms,
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
  if (na.length >= 6 &&
      nb.length >= 6 &&
      (na.contains(nb) || nb.contains(na))) {
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

class RecurrenceInfo {
  final String frequency;
  final int interval;
  final DateTime? endsOn;
  final int? maxOccurrences;

  const RecurrenceInfo({
    required this.frequency,
    required this.interval,
    this.endsOn,
    this.maxOccurrences,
  });

  factory RecurrenceInfo.fromJson(Map<String, dynamic> json) {
    final endsOnRaw = json['endsOn'] ?? json['ends_on'];
    return RecurrenceInfo(
      frequency: json['frequency']?.toString() ?? 'weekly',
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      endsOn: endsOnRaw is String ? DateTime.tryParse(endsOnRaw) : null,
      maxOccurrences:
          ((json['maxOccurrences'] ?? json['max_occurrences']) as num?)
              ?.toInt(),
    );
  }
}

class EventPartnerBenefit {
  final String id;
  final String platform;
  final String? platformLabel;
  final String offerType;
  final String offerLabel;

  const EventPartnerBenefit({
    required this.id,
    required this.platform,
    this.platformLabel,
    required this.offerType,
    required this.offerLabel,
  });

  factory EventPartnerBenefit.fromJson(Map<String, dynamic> json) {
    return EventPartnerBenefit(
      id: json['id']?.toString() ?? '',
      platform: json['platform'] as String? ?? '',
      platformLabel:
          json['platformLabel'] as String? ?? json['platform_label'] as String?,
      offerType:
          json['offerType'] as String? ?? json['offer_type'] as String? ?? '',
      offerLabel:
          json['offerLabel'] as String? ?? json['offer_label'] as String? ?? '',
    );
  }

  String get platformDisplayName {
    switch (platform) {
      case 'THE_ENTERTAINER':
        return 'The Entertainer';
      case 'COBONE':
        return 'Cobone';
      case 'GROUPON':
        return 'Groupon';
      case 'FAZAA':
        return 'Fazaa';
      case 'ESAAD':
        return 'Esaad';
      default:
        return platformLabel ?? 'Other';
    }
  }

  String get offerTypeDisplayName {
    switch (offerType) {
      case 'BOGO':
        return 'BOGO';
      case 'PERCENT_OFF':
        return 'Percent Off';
      case 'VOUCHER':
        return 'Voucher';
      case 'MEMBERSHIP':
        return 'Membership';
      default:
        return 'Benefit';
    }
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
  final String currency;
  final String? recurringRuleId;
  final RecurrenceInfo? recurrence;
  final int partnershipCount;
  final List<EventPartnerBenefit> partnershipBenefits;
  final String? offerId;
  final String? offerTitle;
  final String? offerType;
  final double? offerDiscountValue;
  final double? offerPrice;
  final int? capacity;
  final int rsvpCount;

  VenueUpcomingEvent({
    required this.id,
    required this.title,
    this.description,
    required this.startAt,
    required this.endAt,
    this.photo,
    this.photos = const [],
    this.priceAed,
    this.currency = 'TRY',
    this.recurringRuleId,
    this.recurrence,
    this.partnershipCount = 0,
    this.partnershipBenefits = const [],
    this.offerId,
    this.offerTitle,
    this.offerType,
    this.offerDiscountValue,
    this.offerPrice,
    this.capacity,
    this.rsvpCount = 0,
  });

  bool get isRecurring => recurringRuleId != null;

  /// Offer var mı? (conditions/title opsiyonel — tip varsa offer vardır)
  bool get hasOffer => offerType != null;

  /// Offer tipinin kısa etiketi (chip'lerde gösterim için).
  String? get offerTypeLabel {
    switch (offerType) {
      case 'BUFFET':
        return 'Buffet';
      case 'SET_MENU':
        return 'Set Menu';
      case 'OPEN_DRINK':
        return 'Open Drink';
      case 'OPEN_FOOD':
        return 'Open Food';
      case 'BOGO':
        return 'BOGO';
      case 'PERCENT_OFF':
        return 'Percent Off';
      case 'FIXED_DISCOUNT':
        return 'Discount';
      case 'FREE_ITEM':
        return 'Free Item';
      case 'BUNDLE':
        return 'Bundle';
      default:
        return offerType == null ? null : 'Offer';
    }
  }

  factory VenueUpcomingEvent.fromJson(Map<String, dynamic> json) {
    final startRaw = json['startAt'] ?? json['start_at'] ?? '';
    final endRaw = json['endAt'] ?? json['end_at'] ?? '';
    final recurrenceRaw = json['recurrence'];
    final benefitsRaw =
        json['partnershipBenefits'] ?? json['partnership_benefits'];
    return VenueUpcomingEvent(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      startAt: DateTime.tryParse(startRaw.toString()) ?? DateTime.now(),
      endAt: DateTime.tryParse(endRaw.toString()) ?? DateTime.now(),
      photo: json['photo']?.toString(),
      photos:
          (json['photos'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      priceAed: json['priceAed'] is num
          ? (json['priceAed'] as num).toInt()
          : json['price_aed'] is num
          ? (json['price_aed'] as num).toInt()
          : null,
      currency: json['currency']?.toString() ?? 'TRY',
      recurringRuleId:
          json['recurringRuleId']?.toString() ??
          json['recurring_rule_id']?.toString(),
      recurrence: recurrenceRaw is Map<String, dynamic>
          ? RecurrenceInfo.fromJson(recurrenceRaw)
          : recurrenceRaw is Map
          ? RecurrenceInfo.fromJson(Map<String, dynamic>.from(recurrenceRaw))
          : null,
      partnershipCount: json['partnershipCount'] is num
          ? (json['partnershipCount'] as num).toInt()
          : json['partnership_count'] is num
          ? (json['partnership_count'] as num).toInt()
          : 0,
      partnershipBenefits: benefitsRaw is List
          ? benefitsRaw
                .map(
                  (e) => EventPartnerBenefit.fromJson(
                    e is Map<String, dynamic>
                        ? e
                        : Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList()
          : const [],
      offerId: json['offerId']?.toString() ?? json['offer_id']?.toString(),
      offerTitle:
          json['offerTitle'] as String? ?? json['offer_title'] as String?,
      offerType: json['offerType'] as String? ?? json['offer_type'] as String?,
      offerDiscountValue: json['offerDiscountValue'] is num
          ? (json['offerDiscountValue'] as num).toDouble()
          : json['offer_discount_value'] is num
          ? (json['offer_discount_value'] as num).toDouble()
          : null,
      offerPrice: json['offerPrice'] is num
          ? (json['offerPrice'] as num).toDouble()
          : json['offer_price'] is num
          ? (json['offer_price'] as num).toDouble()
          : null,
      capacity: json['capacity'] is num
          ? (json['capacity'] as num).toInt()
          : null,
      rsvpCount: json['rsvpCount'] is num
          ? (json['rsvpCount'] as num).toInt()
          : 0,
    );
  }

  /// Returns e.g. "Fri, 30 May · 21:00"
  String get formattedDate {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final s = startAt.toLocal();
    final e = endAt.toLocal();
    final dayName = days[(s.weekday - 1) % 7];
    final monthName = months[s.month - 1];
    final sH = s.hour.toString().padLeft(2, '0');
    final sM = s.minute.toString().padLeft(2, '0');
    final eH = e.hour.toString().padLeft(2, '0');
    final eM = e.minute.toString().padLeft(2, '0');

    final sameDay = s.year == e.year && s.month == e.month && s.day == e.day;
    if (sameDay) {
      return '$dayName, ${s.day} $monthName · $sH:$sM → $eH:$eM';
    }
    final eDayName = days[(e.weekday - 1) % 7];
    final eMonthName = months[e.month - 1];
    return '$dayName, ${s.day} $monthName $sH:$sM → $eDayName, ${e.day} $eMonthName $eH:$eM';
  }
}
