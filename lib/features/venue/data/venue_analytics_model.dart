/// GET /venues/:id/analytics?range=7d|30d|90d yanıtı.
class VenueAnalytics {
  final String range;
  final int totalCheckins;
  final int uniqueVisitors;
  final AnalyticsPrivacy privacy;
  final AnalyticsRepeat repeat;
  final List<AnalyticsDayCount> checkinsByDay;
  final List<AnalyticsHourCount> peakHours;
  final AnalyticsGender gender;
  final List<AnalyticsAgeBucket> ageBreakdown;
  final List<AnalyticsIntent> topIntents;

  const VenueAnalytics({
    required this.range,
    required this.totalCheckins,
    required this.uniqueVisitors,
    required this.privacy,
    required this.repeat,
    required this.checkinsByDay,
    required this.peakHours,
    required this.gender,
    required this.ageBreakdown,
    required this.topIntents,
  });

  factory VenueAnalytics.fromJson(Map<String, dynamic> json) {
    final totals = Map<String, dynamic>.from(json['totals'] as Map? ?? {});
    final privacyJson = json['privacy'];
    final hasPrivacyMetadata = privacyJson is Map;
    return VenueAnalytics(
      range: json['range']?.toString() ?? '7d',
      totalCheckins: (totals['totalCheckins'] as num?)?.toInt() ?? 0,
      uniqueVisitors: (totals['uniqueVisitors'] as num?)?.toInt() ?? 0,
      privacy: AnalyticsPrivacy.fromJson(
        hasPrivacyMetadata
            ? Map<String, dynamic>.from(privacyJson)
            : const <String, dynamic>{},
        legacyResponse: !hasPrivacyMetadata,
      ),
      repeat: AnalyticsRepeat.fromJson(
        Map<String, dynamic>.from(json['repeatVisitors'] as Map? ?? {}),
      ),
      checkinsByDay: (json['checkinsByDay'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AnalyticsDayCount.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      peakHours: (json['peakHours'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AnalyticsHourCount.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      gender: AnalyticsGender.fromJson(
        Map<String, dynamic>.from(json['genderBreakdown'] as Map? ?? {}),
      ),
      ageBreakdown: (json['ageBreakdown'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AnalyticsAgeBucket.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      topIntents: (json['topIntents'] as List? ?? [])
          .whereType<Map>()
          .map((e) => AnalyticsIntent.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

class AnalyticsPrivacy {
  final bool repeatMetricsAvailable;
  final bool demographicsAvailable;
  final int minimumRepeatCohortSize;
  final int minimumDemographicCohortSize;
  final int minimumVisibleCellCount;

  const AnalyticsPrivacy({
    required this.repeatMetricsAvailable,
    required this.demographicsAvailable,
    required this.minimumRepeatCohortSize,
    required this.minimumDemographicCohortSize,
    required this.minimumVisibleCellCount,
  });

  factory AnalyticsPrivacy.fromJson(
    Map<String, dynamic> json, {
    required bool legacyResponse,
  }) {
    return AnalyticsPrivacy(
      // Older backend responses had no privacy contract. Preserve their
      // existing rendering until the protected backend is deployed.
      repeatMetricsAvailable: legacyResponse
          ? true
          : json['repeatMetricsAvailable'] == true,
      demographicsAvailable: legacyResponse
          ? true
          : json['demographicsAvailable'] == true,
      minimumRepeatCohortSize:
          (json['minimumRepeatCohortSize'] as num?)?.toInt() ?? 5,
      minimumDemographicCohortSize:
          (json['minimumDemographicCohortSize'] as num?)?.toInt() ?? 10,
      minimumVisibleCellCount:
          (json['minimumVisibleCellCount'] as num?)?.toInt() ?? 3,
    );
  }
}

class AnalyticsIntent {
  final String intent; // enum key, örn. NEW_PEOPLE
  final int count;

  const AnalyticsIntent({required this.intent, required this.count});

  /// Backend enum'undaki tüm geliş amaçları — veri olmasa da 0 ile gösterilir.
  static const List<String> allKeys = [
    'NEW_PEOPLE',
    'GOOD_CONVERSATION',
    'MEET_SOMEONE',
    'OPEN_TO_POSSIBILITIES',
    'JUST_CHILLING',
    'BUSINESS_NETWORKING',
    'CELEBRATING',
    'LOOKING_FOR_FUN',
  ];

  factory AnalyticsIntent.fromJson(Map<String, dynamic> json) =>
      AnalyticsIntent(
        intent: json['intent']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );

  /// Enum değerini kullanıcı dostu etikete çevirir.
  String get label {
    switch (intent) {
      case 'NEW_PEOPLE':
        return 'New people';
      case 'GOOD_CONVERSATION':
        return 'Good conversation';
      case 'MEET_SOMEONE':
        return 'Meet someone';
      case 'OPEN_TO_POSSIBILITIES':
        return 'Open to possibilities';
      case 'JUST_CHILLING':
        return 'Just chilling';
      case 'BUSINESS_NETWORKING':
        return 'Networking';
      case 'CELEBRATING':
        return 'Celebrating';
      case 'LOOKING_FOR_FUN':
        return 'Fun';
      default:
        return intent;
    }
  }
}

class AnalyticsRepeat {
  final int newVisitors;
  final int returningVisitors;
  final double repeatRate; // 0.0 – 1.0

  const AnalyticsRepeat({
    required this.newVisitors,
    required this.returningVisitors,
    required this.repeatRate,
  });

  int get total => newVisitors + returningVisitors;
  int get repeatPercent => (repeatRate * 100).round();

  factory AnalyticsRepeat.fromJson(Map<String, dynamic> json) =>
      AnalyticsRepeat(
        newVisitors: (json['newVisitors'] as num?)?.toInt() ?? 0,
        returningVisitors: (json['returningVisitors'] as num?)?.toInt() ?? 0,
        repeatRate: (json['repeatRate'] as num?)?.toDouble() ?? 0.0,
      );
}

class AnalyticsDayCount {
  final String date; // "YYYY-MM-DD"
  final int count;

  const AnalyticsDayCount({required this.date, required this.count});

  factory AnalyticsDayCount.fromJson(Map<String, dynamic> json) =>
      AnalyticsDayCount(
        date: json['date']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsHourCount {
  final int hour; // 0-23
  final int count;

  const AnalyticsHourCount({required this.hour, required this.count});

  factory AnalyticsHourCount.fromJson(Map<String, dynamic> json) =>
      AnalyticsHourCount(
        hour: (json['hour'] as num?)?.toInt() ?? 0,
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsGender {
  final int male;
  final int female;
  final int other;
  final int withheldCount;

  const AnalyticsGender({
    required this.male,
    required this.female,
    required this.other,
    this.withheldCount = 0,
  });

  int get total => male + female + other;

  factory AnalyticsGender.fromJson(Map<String, dynamic> json) =>
      AnalyticsGender(
        male: (json['male'] as num?)?.toInt() ?? 0,
        female: (json['female'] as num?)?.toInt() ?? 0,
        other: (json['other'] as num?)?.toInt() ?? 0,
        withheldCount: (json['withheldCount'] as num?)?.toInt() ?? 0,
      );
}

class AnalyticsAgeBucket {
  final String bucket; // "18-24", "25-34", ...
  final int count;

  const AnalyticsAgeBucket({required this.bucket, required this.count});

  factory AnalyticsAgeBucket.fromJson(Map<String, dynamic> json) =>
      AnalyticsAgeBucket(
        bucket: json['bucket']?.toString() ?? '',
        count: (json['count'] as num?)?.toInt() ?? 0,
      );
}

/// GET /venues/:id/reports — geçmiş haftalık raporlar.
class WeeklyReport {
  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String? pdfUrl;
  final int totalCheckins;
  final int uniqueVisitors;

  const WeeklyReport({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.pdfUrl,
    required this.totalCheckins,
    required this.uniqueVisitors,
  });

  factory WeeklyReport.fromJson(Map<String, dynamic> json) {
    final metrics = Map<String, dynamic>.from(json['metrics'] as Map? ?? {});
    return WeeklyReport(
      id: json['id']?.toString() ?? '',
      periodStart:
          DateTime.tryParse(json['periodStart']?.toString() ?? '') ??
          DateTime.now(),
      periodEnd:
          DateTime.tryParse(json['periodEnd']?.toString() ?? '') ??
          DateTime.now(),
      pdfUrl: json['pdfUrl']?.toString(),
      totalCheckins: (metrics['totalCheckins'] as num?)?.toInt() ?? 0,
      uniqueVisitors: (metrics['uniqueVisitors'] as num?)?.toInt() ?? 0,
    );
  }
}
