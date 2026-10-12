import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';

void main() {
  Map<String, dynamic> response() => {
    'id': 'event-a',
    'title': 'Running',
    'startAt': '2026-11-01T18:00:00Z',
    'endAt': '2026-11-01T20:00:00Z',
    'description': null,
    'photo': null,
    'photos': <String>[],
    'currency': 'AED',
    'capacity': null,
    'priceAed': null,
    'recurringRuleId': null,
    'recurrence': null,
    'rsvpCount': 0,
    'partnershipCount': 0,
    'partnershipBenefits': <Map<String, dynamic>>[],
    'offerId': null,
    'offerTitle': null,
    'offerType': null,
    'offerPrice': null,
    'offerDiscountValue': null,
  };

  test(
    'complete committed detail needs no extra read, including explicit empty/null fields',
    () {
      expect(
        VenueEventMutation.fromJson(response()).requiresDetailRefresh,
        false,
      );
    },
  );

  test('an incomplete/older response retains the detail refresh', () {
    for (final missing in [
      'photos',
      'offerId',
      'partnershipBenefits',
      'rsvpCount',
      'recurrence',
    ]) {
      final incomplete = response()..remove(missing);
      expect(
        VenueEventMutation.fromJson(incomplete).requiresDetailRefresh,
        true,
        reason: missing,
      );
    }
  });
}
