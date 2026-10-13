import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_calendar_entry.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_calendar_store.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Events extends VenueEventRepository {
  final months = <DateTime>[];
  final venues = <String>[];
  int calendars = 0;
  Future<List<VenueEventCalendarEntry>> Function()? calendarRead;
  Future<List<VenueUpcomingEvent>> Function(DateTime)? monthRead;

  @override
  Future<List<VenueEventCalendarEntry>> getEventCalendar(String venueId) {
    calendars++;
    venues.add(venueId);
    return calendarRead?.call() ?? Future.value([]);
  }

  @override
  Future<List<VenueUpcomingEvent>> listEventMonth(
    String venueId,
    DateTime month,
  ) {
    months.add(month);
    venues.add(venueId);
    return monthRead?.call(month) ?? Future.value([]);
  }
}

VenueUpcomingEvent _event(
  String id,
  int month, {
  String? rule,
  String? title,
}) => VenueUpcomingEvent(
  id: id,
  title: title ?? id,
  startAt: DateTime(2026, month, 9, 18),
  endAt: DateTime(2026, month, 9, 20),
  recurringRuleId: rule,
);
VenueEventCalendarEntry _entry(VenueUpcomingEvent e) => VenueEventCalendarEntry(
  id: e.id,
  startAt: e.startAt,
  recurringRuleId: e.recurringRuleId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all calendar dots arrive without waiting for the selected month media',
    () async {
      final month = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events();
      repo.calendarRead = () async => [
        _entry(_event('past', 1)),
        _entry(_event('future', 12)),
      ];
      repo.monthRead = (_) => month.future;
      final store = VenueEventCalendarStore(
        venueId: 'venue-a',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(store.dispose);
      final detail = store.loadMonth(DateTime(2026, 10));
      await store.loadCalendar();
      expect(store.daysWithEvents, {'2026-1-9', '2026-12-9'});
      expect(store.events, isEmpty);
      month.complete([_event('october', 10)]);
      await detail;
      expect(store.events.single.id, 'october');
      expect(store.daysWithEvents, contains('2026-10-9'));
    },
  );

  test(
    'parallel reads deduplicate; day changes and returning to a loaded month reuse complete rows',
    () async {
      final response = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events()..monthRead = (_) => response.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(store.dispose);
      final first = store.loadMonth(DateTime(2026, 10));
      final duplicate = store.loadMonth(DateTime(2026, 10, 22));
      expect(repo.months, hasLength(1));
      response.complete([_event('oct', 10)]);
      await Future.wait([first, duplicate]);
      await store.loadSelection(DateTime(2026, 10, 12), null);
      await store.loadMonth(DateTime(2026, 11));
      await store.loadMonth(DateTime(2026, 10));
      expect(repo.months, hasLength(2));
      expect(store.events.single.id, 'oct');
    },
  );

  test(
    'ranges can span arbitrary months, but use at most two concurrent reads; failure does not block later months',
    () async {
      final responses = {
        for (var m = 1; m <= 4; m++) m: Completer<List<VenueUpcomingEvent>>(),
      };
      final repo = _Events()
        ..monthRead = (month) => responses[month.month]!.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(store.dispose);
      final range = store.loadSelection(
        DateTime(2026, 1),
        DateTime(2026, 4, 30),
      );
      expect(repo.months.map((m) => m.month), [1, 2]);
      responses[1]!.completeError(StateError('temporary outage'));
      await Future<void>.delayed(Duration.zero);
      expect(repo.months.map((m) => m.month), [1, 2, 3]);
      responses[2]!.complete([_event('feb', 2)]);
      await Future<void>.delayed(Duration.zero);
      expect(repo.months.map((m) => m.month), [1, 2, 3, 4]);
      responses[3]!.complete([_event('mar', 3)]);
      responses[4]!.complete([_event('apr', 4)]);
      await range;
      expect(store.events.map((e) => e.id).toSet(), {'feb', 'mar', 'apr'});
      repo.monthRead = (_) async => [_event('jan', 1)];
      await store.loadMonth(DateTime(2026, 1));
      expect(store.events.map((e) => e.id), contains('jan'));
    },
  );

  test(
    'short-lived month cache expires and a failed refresh remains retryable',
    () async {
      var now = DateTime(2026, 10, 6);
      final repo = _Events()..monthRead = (_) async => [_event('first', 10)];
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
        clock: () => now,
      );
      addTearDown(store.dispose);
      await store.loadMonth(now);
      now = now.add(const Duration(seconds: 40));
      await store.loadMonth(now);
      expect(repo.months, hasLength(1));
      now = now.add(const Duration(seconds: 21));
      repo.monthRead = (_) async => throw StateError('temporary outage');
      await expectLater(store.loadMonth(now), throwsStateError);
      expect(store.events.single.id, 'first');
      repo.monthRead = (_) async => [_event('fresh', 10)];
      await store.loadMonth(now);
      expect(repo.months, hasLength(3));
      expect(store.events.single.id, 'fresh');
    },
  );

  test(
    'create appears immediately; late calendar and month cannot erase it or block new reads',
    () async {
      final oldCalendar = Completer<List<VenueEventCalendarEntry>>();
      final oldMonth = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events();
      repo.calendarRead = () => oldCalendar.future;
      repo.monthRead = (_) => oldMonth.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(store.dispose);
      final initial = Future.wait([
        store.loadCalendar(),
        store.loadMonth(DateTime(2026, 10)),
      ]);
      final saved = _event('new', 11);
      store.created([saved]);
      expect(store.events.single.id, 'new');
      expect(store.daysWithEvents, {'2026-11-9'});
      repo.calendarRead = () async => [_entry(saved)];
      repo.monthRead = (_) async => [saved];
      await Future.wait([store.loadCalendar(), store.loadMonth(saved.startAt)]);
      oldCalendar.complete([]);
      oldMonth.complete([]);
      await initial;
      expect(store.events.single.id, 'new');
      expect(store.daysWithEvents, {'2026-11-9'});
    },
  );

  test(
    'edit all removes exact repeats, moves dates and prevents old title/calendar resurrection',
    () async {
      final old = _event('event', 10, rule: 'series', title: 'Old');
      final repeat = _event('repeat', 11, rule: 'series');
      final keep = _event('historical', 1, rule: 'series');
      final late = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events()..monthRead = (_) => late.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
        seed: [old, repeat, keep],
      );
      addTearDown(store.dispose);
      final read = store.loadMonth(DateTime(2026, 10));
      final updated = _event(old.id, 12, title: 'New');
      store.updated(
        VenueEventMutation(
          event: updated,
          events: [updated],
          removedEventIds: {repeat.id},
        ),
      );
      expect(store.daysWithEvents, {'2026-1-9', '2026-12-9'});
      late.complete([old]);
      await read;
      expect(store.events.map((e) => e.title).toSet(), {'New', 'historical'});
    },
  );

  test(
    'series deletion removes dots even for unloaded dates; unrelated series stay',
    () async {
      final selected = _event('selected', 10, rule: 'series');
      final repo = _Events()
        ..calendarRead = () async => [
          _entry(selected),
          _entry(_event('unloaded', 12, rule: 'series')),
          _entry(_event('other', 1, rule: 'other-series')),
        ];
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
        seed: [selected],
      );
      addTearDown(store.dispose);
      await store.loadCalendar();
      store.deleted(selected, series: true);
      expect(store.events, isEmpty);
      expect(store.daysWithEvents, {'2026-1-9'});
    },
  );

  test(
    'single deletion and moderation invalidation force fresh reads without erasing unrelated rows',
    () async {
      final first = _event('first', 10);
      final second = _event('second', 10);
      final repo = _Events()..monthRead = (_) async => [first, second];
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(store.dispose);
      await store.loadMonth(first.startAt);
      store.deleted(first, series: false);
      expect(store.events.single.id, 'second');
      repo.monthRead = (_) async => [second];
      await store.loadMonth(second.startAt);
      store.invalidate();
      await store.loadMonth(second.startAt);
      expect(repo.months, hasLength(3));
    },
  );

  test(
    'session change hides cached rows and ignores late responses; page/venue instances never share cache',
    () async {
      var current = true;
      final late = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events()..monthRead = (_) => late.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => current,
        seed: [_event('old', 10)],
      );
      addTearDown(store.dispose);
      final read = store.loadMonth(DateTime(2026, 10));
      current = false;
      late.complete([_event('late', 10)]);
      await read;
      expect(store.events, isEmpty);
      expect(store.daysWithEvents, isEmpty);
      final newRepo = _Events()
        ..monthRead = (_) async => [_event('new-session', 10)];
      final newStore = VenueEventCalendarStore(
        venueId: 'b',
        repository: newRepo,
        isCurrentSession: () => true,
      );
      addTearDown(newStore.dispose);
      expect(newStore.events, isEmpty);
      await newStore.loadMonth(DateTime(2026, 10));
      expect(newRepo.venues, ['b']);
      expect(newStore.events.single.id, 'new-session');
    },
  );

  test(
    'dispose ignores late results without notifying a closed page',
    () async {
      final late = Completer<List<VenueUpcomingEvent>>();
      final repo = _Events()..monthRead = (_) => late.future;
      final store = VenueEventCalendarStore(
        venueId: 'a',
        repository: repo,
        isCurrentSession: () => true,
      );
      var notifications = 0;
      store.addListener(() => notifications++);
      final read = store.loadMonth(DateTime(2026, 10));
      final notificationsBeforeDispose = notifications;
      store.dispose();
      late.complete([_event('late', 10)]);
      await read;
      expect(notifications, notificationsBeforeDispose);
      expect(store.events, isEmpty);
    },
  );
}
