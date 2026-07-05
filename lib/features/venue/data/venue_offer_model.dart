enum VenueOfferType {
  BOGO,
  PERCENT_OFF,
  FIXED_DISCOUNT,
  FREE_ITEM,
  BUNDLE,
}

enum OfferRedemptionStatus {
  PENDING,
  USED,
  EXPIRED,
}

class VenueOfferModel {
  final String id;
  final String venueId;
  final String? eventId;
  final String title;
  final String? description;
  final VenueOfferType type;
  final double? discountValue;
  final String? terms;
  final DateTime? validFrom;
  final DateTime? validUntil;
  final int? maxRedemptions;
  final int redemptionsUsed;
  final bool isActive;
  final String? photoUrl;
  final DateTime createdAt;

  const VenueOfferModel({
    required this.id,
    required this.venueId,
    this.eventId,
    required this.title,
    this.description,
    required this.type,
    this.discountValue,
    this.terms,
    this.validFrom,
    this.validUntil,
    this.maxRedemptions,
    required this.redemptionsUsed,
    required this.isActive,
    this.photoUrl,
    required this.createdAt,
  });

  factory VenueOfferModel.fromJson(Map<String, dynamic> json) {
    return VenueOfferModel(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      eventId: json['event_id'] as String?,
      title: json['title'] as String,
      description: json['description'] as String?,
      type: VenueOfferType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => VenueOfferType.BOGO,
      ),
      discountValue: json['discount_value'] != null
          ? (json['discount_value'] as num).toDouble()
          : null,
      terms: json['terms'] as String?,
      validFrom: json['valid_from'] != null ? DateTime.parse(json['valid_from'] as String) : null,
      validUntil: json['valid_until'] != null ? DateTime.parse(json['valid_until'] as String) : null,
      maxRedemptions: json['max_redemptions'] as int?,
      redemptionsUsed: json['redemptions_used'] as int? ?? 0,
      isActive: json['is_active'] as bool? ?? true,
      photoUrl: json['photo_url'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get typeDisplayName {
    switch (type) {
      case VenueOfferType.BOGO:
        return 'BOGO';
      case VenueOfferType.PERCENT_OFF:
        return discountValue != null ? '%${discountValue!.toInt()} Off' : 'Percent Off';
      case VenueOfferType.FIXED_DISCOUNT:
        return discountValue != null ? '${discountValue!.toStringAsFixed(0)} Off' : 'Discount';
      case VenueOfferType.FREE_ITEM:
        return 'Free Item';
      case VenueOfferType.BUNDLE:
        return 'Bundle Deal';
    }
  }

  bool get isExpired => validUntil != null && validUntil!.isBefore(DateTime.now());

  bool get hasRedemptionLimit => maxRedemptions != null;

  bool get isFullyRedeemed =>
      maxRedemptions != null && redemptionsUsed >= maxRedemptions!;
}

class OfferRedemptionModel {
  final String id;
  final String offerId;
  final String userId;
  final String code;
  final OfferRedemptionStatus status;
  final DateTime? redeemedAt;
  final DateTime expiresAt;
  final DateTime createdAt;

  const OfferRedemptionModel({
    required this.id,
    required this.offerId,
    required this.userId,
    required this.code,
    required this.status,
    this.redeemedAt,
    required this.expiresAt,
    required this.createdAt,
  });

  factory OfferRedemptionModel.fromJson(Map<String, dynamic> json) {
    return OfferRedemptionModel(
      id: json['id'] as String,
      offerId: json['offer_id'] as String,
      userId: json['user_id'] as String,
      code: json['code'] as String,
      status: OfferRedemptionStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => OfferRedemptionStatus.PENDING,
      ),
      redeemedAt: json['redeemed_at'] != null ? DateTime.parse(json['redeemed_at'] as String) : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  bool get isExpired => expiresAt.isBefore(DateTime.now());
}
