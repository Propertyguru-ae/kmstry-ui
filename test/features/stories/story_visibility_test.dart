import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_visibility.dart';

void main() {
  const reported = StoryGroup(
    user: StoryUser(id: 'reported', fullName: 'Reported'),
    stories: [],
  );
  const other = StoryGroup(
    user: StoryUser(id: 'other', fullName: 'Other'),
    stories: [],
  );
  const venue = StoryGroup(
    user: StoryUser(id: 'reported', fullName: 'Venue'),
    stories: [],
    venueLabel: 'Venue',
  );

  tearDown(() => StoryVisibility.changes.value = null);

  test(
    'block removes only personal author groups without mutating viewer list',
    () {
      final original = [reported, other, venue];
      final result = const StoryVisibilityChange(
        'reported',
        blocked: true,
      ).apply(original);
      expect(result, [other, venue]);
      expect(original, [reported, other, venue]);
    },
  );

  test(
    'unblock does not resurrect stale content; caller reloads from server',
    () {
      expect(
        const StoryVisibilityChange('reported', blocked: false).apply([other]),
        [other],
      );
    },
  );

  test(
    'repeated block/report and unblock each invalidate listening screens',
    () {
      var calls = 0;
      void onChange() => calls++;
      StoryVisibility.changes.addListener(onChange);
      try {
        StoryVisibility.changed('reported', blocked: true);
        StoryVisibility.changed('reported', blocked: true);
        StoryVisibility.changed('reported', blocked: false);
        expect(calls, 3);
        expect(StoryVisibility.changes.value?.blocked, false);
      } finally {
        StoryVisibility.changes.removeListener(onChange);
      }
    },
  );
}
