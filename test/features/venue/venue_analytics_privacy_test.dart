import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_analytics_model.dart';

void main() {
  test('parses protected analytics metadata and nullable sections safely', () {
    final analytics = VenueAnalytics.fromJson({
      'range': '7d',
      'totals': {'totalCheckins': 4, 'uniqueVisitors': 4},
      'privacy': {
        'repeatMetricsAvailable': false,
        'demographicsAvailable': false,
        'minimumRepeatCohortSize': 5,
        'minimumDemographicCohortSize': 10,
        'minimumVisibleCellCount': 3,
      },
      'repeatVisitors': null,
      'genderBreakdown': null,
      'ageBreakdown': null,
      'topIntents': null,
    });

    expect(analytics.totalCheckins, 4);
    expect(analytics.uniqueVisitors, 4);
    expect(analytics.privacy.repeatMetricsAvailable, isFalse);
    expect(analytics.privacy.demographicsAvailable, isFalse);
    expect(analytics.repeat.total, 0);
    expect(analytics.gender.total, 0);
    expect(analytics.ageBreakdown, isEmpty);
    expect(analytics.topIntents, isEmpty);
  });

  test('keeps legacy analytics responses visible during rolling deploys', () {
    final analytics = VenueAnalytics.fromJson({
      'totals': {'totalCheckins': 1, 'uniqueVisitors': 1},
      'repeatVisitors': {
        'newVisitors': 1,
        'returningVisitors': 0,
        'repeatRate': 0,
      },
      'genderBreakdown': {'male': 1, 'female': 0, 'other': 0},
      'ageBreakdown': <Map<String, dynamic>>[],
      'topIntents': <Map<String, dynamic>>[],
    });

    expect(analytics.privacy.repeatMetricsAvailable, isTrue);
    expect(analytics.privacy.demographicsAvailable, isTrue);
  });
}
