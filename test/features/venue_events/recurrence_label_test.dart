import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

void main() {
  test(
    'recurring events say whether they repeat weekly, monthly or yearly',
    () {
      expect(
        const RecurrenceInfo(frequency: 'weekly', interval: 1).shortLabel,
        'Weekly',
      );
      expect(
        const RecurrenceInfo(frequency: 'monthly', interval: 1).shortLabel,
        'Monthly',
      );
      expect(
        const RecurrenceInfo(frequency: 'yearly', interval: 1).shortLabel,
        'Yearly',
      );
      expect(
        const RecurrenceInfo(frequency: 'weekly', interval: 2).shortLabel,
        'Every 2 weeks',
      );
    },
  );

  test('summary includes how long the series runs', () {
    expect(
      const RecurrenceInfo(frequency: 'yearly', interval: 1).summary,
      'Repeats every year',
    );
    expect(
      RecurrenceInfo(
        frequency: 'weekly',
        interval: 1,
        endsOn: DateTime(2026, 12, 31, 12),
      ).summary,
      'Repeats every week · until 31 Dec 2026',
    );
    expect(
      const RecurrenceInfo(
        frequency: 'monthly',
        interval: 1,
        maxOccurrences: 10,
      ).summary,
      'Repeats every month · 10 times',
    );
  });
}
