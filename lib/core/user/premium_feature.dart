/// KMSTRY+ (user premium) features — the frontend mirror of the backend
/// `premium-matrix.ts`. KMSTRY+ is binary today, so [PremiumGate] gates all of
/// these on a single `isPremium` flag. Each new premium feature is one enum
/// value here + one gate call at the call site.
enum PremiumFeature {
  advancedFilters,
  anonymousMode,
  seeWhoInterested,
  priorityVisibility,
  incognitoViewing,
  unlimitedRewinds,
  priorityEventAccess,
  exclusiveOffers,
  readReceiptsControl,
}

extension PremiumFeatureX on PremiumFeature {
  /// Wire value — must match backend `PremiumFeature` enum.
  String get api {
    switch (this) {
      case PremiumFeature.advancedFilters:
        return 'ADVANCED_FILTERS';
      case PremiumFeature.anonymousMode:
        return 'ANONYMOUS_MODE';
      case PremiumFeature.seeWhoInterested:
        return 'SEE_WHO_INTERESTED';
      case PremiumFeature.priorityVisibility:
        return 'PRIORITY_VISIBILITY';
      case PremiumFeature.incognitoViewing:
        return 'INCOGNITO_VIEWING';
      case PremiumFeature.unlimitedRewinds:
        return 'UNLIMITED_REWINDS';
      case PremiumFeature.priorityEventAccess:
        return 'PRIORITY_EVENT_ACCESS';
      case PremiumFeature.exclusiveOffers:
        return 'EXCLUSIVE_OFFERS';
      case PremiumFeature.readReceiptsControl:
        return 'READ_RECEIPTS_CONTROL';
    }
  }

  String get label {
    switch (this) {
      case PremiumFeature.advancedFilters:
        return 'Advanced Filters';
      case PremiumFeature.anonymousMode:
        return 'Anonymous Mode';
      case PremiumFeature.seeWhoInterested:
        return 'See Who\'s Interested';
      case PremiumFeature.priorityVisibility:
        return 'Priority Visibility';
      case PremiumFeature.incognitoViewing:
        return 'Incognito Viewing';
      case PremiumFeature.unlimitedRewinds:
        return 'Unlimited Rewinds';
      case PremiumFeature.priorityEventAccess:
        return 'Priority Event Access';
      case PremiumFeature.exclusiveOffers:
        return 'Exclusive Offers';
      case PremiumFeature.readReceiptsControl:
        return 'Read Receipts Control';
    }
  }
}
