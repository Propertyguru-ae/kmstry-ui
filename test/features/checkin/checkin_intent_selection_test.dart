import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_intent_selection.dart';

void main() {
  group('normalizeRequiredCheckinIntents', () {
    test('rejects an empty selection', () {
      expect(
        () => normalizeRequiredCheckinIntents(const []),
        throwsArgumentError,
      );
    });

    test('rejects whitespace-only values', () {
      expect(
        () => normalizeRequiredCheckinIntents(const [' ', '\n']),
        throwsArgumentError,
      );
    });

    test('trims and removes duplicate selections', () {
      expect(
        normalizeRequiredCheckinIntents(const [
          'NEW_PEOPLE',
          ' NEW_PEOPLE ',
          'GOOD_CONVERSATION',
        ]),
        const ['NEW_PEOPLE', 'GOOD_CONVERSATION'],
      );
    });

    test('does not impose a maximum selection count', () {
      expect(
        normalizeRequiredCheckinIntents(const [
          'NEW_PEOPLE',
          'GOOD_CONVERSATION',
          'MEET_SOMEONE',
          'OPEN_TO_POSSIBILITIES',
        ]),
        hasLength(4),
      );
    });
  });
}
