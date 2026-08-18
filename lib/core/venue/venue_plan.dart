import 'package:flutter/material.dart';

/// KMSTRY venue subscription tiers. Mirrors backend `VenuePlan`.
enum VenuePlan { free, social, live, premium }

/// Plan-gated venue capabilities. Mirrors backend `VenueFeature` enum strings.
enum VenueFeature {
  stories,
  offers,
  customerChat,
  weeklyReports,
  priorityListing,
  featuredBadge,
  roleLevels,
  events,
  goLive,
  advancedAnalytics,
  repeatVisitor,
  homepageFeature,
  sponsoredSearch,
  vipList,
  customerDemographics,
  areaComparison,
}

extension VenuePlanX on VenuePlan {
  static VenuePlan fromApi(String? raw) {
    switch ((raw ?? 'FREE').toUpperCase()) {
      case 'SOCIAL':
        return VenuePlan.social;
      case 'LIVE':
        return VenuePlan.live;
      case 'PREMIUM':
        return VenuePlan.premium;
      default:
        return VenuePlan.free;
    }
  }

  String get label {
    switch (this) {
      case VenuePlan.free:
        return 'Free';
      case VenuePlan.social:
        return 'Social';
      case VenuePlan.live:
        return 'Live';
      case VenuePlan.premium:
        return 'Premium';
    }
  }

  /// Monthly price in AED (0 for free).
  int get priceAed {
    switch (this) {
      case VenuePlan.free:
        return 0;
      case VenuePlan.social:
        return 299;
      case VenuePlan.live:
        return 500;
      case VenuePlan.premium:
        return 900;
    }
  }

  /// Bu kademenin izin verdiği toplam personel koltuğu (owner dahil).
  /// null = sınırsız. Backend ADMIN_ACCOUNT_LIMIT ile aynı.
  int? get staffLimit {
    switch (this) {
      case VenuePlan.free:
        return 1;
      case VenuePlan.social:
        return 3;
      case VenuePlan.live:
        return 10;
      case VenuePlan.premium:
        return null;
    }
  }

  Color get color {
    switch (this) {
      case VenuePlan.free:
        return const Color(0xFF8A8F98);
      case VenuePlan.social:
        return const Color(0xFF1A9FE8); // mavi
      case VenuePlan.live:
        return const Color(0xFF1FD9A8); // turkuaz
      case VenuePlan.premium:
        return const Color(0xFFE020D8); // magenta
    }
  }
}

extension VenueFeatureX on VenueFeature {
  /// The backend enum string (e.g. VenueFeature.goLive → "GO_LIVE").
  String get api {
    switch (this) {
      case VenueFeature.stories:
        return 'STORIES';
      case VenueFeature.offers:
        return 'OFFERS';
      case VenueFeature.customerChat:
        return 'CUSTOMER_CHAT';
      case VenueFeature.weeklyReports:
        return 'WEEKLY_REPORTS';
      case VenueFeature.priorityListing:
        return 'PRIORITY_LISTING';
      case VenueFeature.featuredBadge:
        return 'FEATURED_BADGE';
      case VenueFeature.roleLevels:
        return 'ROLE_LEVELS';
      case VenueFeature.events:
        return 'EVENTS';
      case VenueFeature.goLive:
        return 'GO_LIVE';
      case VenueFeature.advancedAnalytics:
        return 'ADVANCED_ANALYTICS';
      case VenueFeature.repeatVisitor:
        return 'REPEAT_VISITOR';
      case VenueFeature.homepageFeature:
        return 'HOMEPAGE_FEATURE';
      case VenueFeature.sponsoredSearch:
        return 'SPONSORED_SEARCH';
      case VenueFeature.vipList:
        return 'VIP_LIST';
      case VenueFeature.customerDemographics:
        return 'CUSTOMER_DEMOGRAPHICS';
      case VenueFeature.areaComparison:
        return 'AREA_COMPARISON';
    }
  }

  /// Minimum tier that unlocks this feature (mirrors backend FEATURE_MIN_TIER).
  VenuePlan get minPlan {
    switch (this) {
      case VenueFeature.stories:
      case VenueFeature.offers:
      case VenueFeature.customerChat:
      case VenueFeature.weeklyReports:
      case VenueFeature.priorityListing:
      case VenueFeature.featuredBadge:
      case VenueFeature.roleLevels:
        return VenuePlan.social;
      case VenueFeature.events:
      case VenueFeature.goLive:
      case VenueFeature.advancedAnalytics:
      case VenueFeature.repeatVisitor:
        return VenuePlan.live;
      case VenueFeature.homepageFeature:
      case VenueFeature.sponsoredSearch:
      case VenueFeature.vipList:
      case VenueFeature.customerDemographics:
      case VenueFeature.areaComparison:
        return VenuePlan.premium;
    }
  }

  static VenueFeature? fromApi(String raw) {
    for (final f in VenueFeature.values) {
      if (f.api == raw) return f;
    }
    return null;
  }
}
