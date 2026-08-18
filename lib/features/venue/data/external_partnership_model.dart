enum ExternalPartnershipPlatform {
  THE_ENTERTAINER,
  COBONE,
  GROUPON,
  FAZAA,
  ESAAD,
  OTHER,
}

enum ExternalPartnershipOfferType {
  BOGO,
  PERCENT_OFF,
  VOUCHER,
  MEMBERSHIP,
  OTHER,
}

enum ExternalPartnershipStatus {
  PENDING_REVIEW,
  ACTIVE,
  REJECTED,
  EXPIRED,
  HIDDEN,
}

class ExternalPartnershipModel {
  final String id;
  final String venueId;
  final ExternalPartnershipPlatform platform;
  final String? platformLabel;
  final ExternalPartnershipOfferType offerType;
  final String offerLabel;
  final String? externalUrl;
  final String? proofImageUrl;
  final ExternalPartnershipStatus status;
  final DateTime? validUntil;
  final DateTime createdAt;

  const ExternalPartnershipModel({
    required this.id,
    required this.venueId,
    required this.platform,
    this.platformLabel,
    required this.offerType,
    required this.offerLabel,
    this.externalUrl,
    this.proofImageUrl,
    required this.status,
    this.validUntil,
    required this.createdAt,
  });

  factory ExternalPartnershipModel.fromJson(Map<String, dynamic> json) {
    return ExternalPartnershipModel(
      id: json['id'] as String,
      venueId: json['venue_id'] as String,
      platform: ExternalPartnershipPlatform.values.firstWhere(
        (e) => e.name == json['platform'],
        orElse: () => ExternalPartnershipPlatform.OTHER,
      ),
      platformLabel: json['platform_label'] as String?,
      offerType: ExternalPartnershipOfferType.values.firstWhere(
        (e) => e.name == json['offer_type'],
        orElse: () => ExternalPartnershipOfferType.OTHER,
      ),
      offerLabel: json['offer_label'] as String,
      externalUrl: json['external_url'] as String?,
      proofImageUrl: json['proof_image_url'] as String?,
      status: ExternalPartnershipStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => ExternalPartnershipStatus.PENDING_REVIEW,
      ),
      validUntil: json['valid_until'] != null ? DateTime.parse(json['valid_until'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  String get platformDisplayName {
    switch (platform) {
      case ExternalPartnershipPlatform.THE_ENTERTAINER:
        return 'The Entertainer';
      case ExternalPartnershipPlatform.COBONE:
        return 'Cobone';
      case ExternalPartnershipPlatform.GROUPON:
        return 'Groupon';
      case ExternalPartnershipPlatform.FAZAA:
        return 'Fazaa';
      case ExternalPartnershipPlatform.ESAAD:
        return 'Esaad';
      case ExternalPartnershipPlatform.OTHER:
        return platformLabel ?? 'Other';
    }
  }

  String get offerTypeDisplayName {
    switch (offerType) {
      case ExternalPartnershipOfferType.BOGO:
        return 'BOGO';
      case ExternalPartnershipOfferType.PERCENT_OFF:
        return 'Percent Off';
      case ExternalPartnershipOfferType.VOUCHER:
        return 'Voucher';
      case ExternalPartnershipOfferType.MEMBERSHIP:
        return 'Membership Benefit';
      case ExternalPartnershipOfferType.OTHER:
        return 'Benefit';
    }
  }
}
