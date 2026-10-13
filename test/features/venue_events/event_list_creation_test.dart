import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_calendar_entry.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_events_list_page.dart';

class DelayedEvents extends VenueEventRepository {
  final first = Completer<List<VenueUpcomingEvent>>();
  final fresh = Completer<List<VenueUpcomingEvent>>();
  int reads = 0;
  @override
  Future<List<VenueUpcomingEvent>> listEventMonth(
    String venueId,
    DateTime month,
  ) => ++reads == 1 ? first.future : fresh.future;

  @override
  Future<List<VenueEventCalendarEntry>> getEventCalendar(
    String venueId,
  ) async => [];
}

class DelayedCalendar extends DelayedEvents {
  final calendar = Completer<List<VenueEventCalendarEntry>>();
  @override
  Future<List<VenueEventCalendarEntry>> getEventCalendar(String venueId) =>
      calendar.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'NO_TEST_NETWORK'),
        );
    VenueSession.instance.clear();
    await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
  });
  tearDown(() => VenueSession.instance.clear());
  testWidgets(
    'first opening never claims no events before the month read succeeds',
    (tester) async {
      final repo = DelayedEvents();
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventsListPage(
            venueId: 'venue-a',
            events: const [],
            repository: repo,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('events-initial-loading')),
        findsOneWidget,
      );
      expect(find.text('No events on this day'), findsNothing);
      final date = DateTime.now();
      repo.first.complete([
        VenueUpcomingEvent(
          id: 'today',
          title: 'Today Running',
          startAt: date,
          endAt: date.add(const Duration(hours: 1)),
        ),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('Today Running'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('events-initial-loading')),
        findsNothing,
      );
      expect(find.text('No events on this day'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('an authoritative successful empty month shows the empty state', (
    tester,
  ) async {
    final repo = DelayedEvents();
    await tester.pumpWidget(
      MaterialApp(
        home: VenueEventsListPage(
          venueId: 'venue-a',
          events: const [],
          repository: repo,
          onRefresh: () {},
        ),
      ),
    );
    repo.first.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No events on this day'), findsOneWidget);
    expect(find.byKey(const ValueKey('events-initial-loading')), findsNothing);
  });

  testWidgets('a failed month offers retry instead of a false empty result', (
    tester,
  ) async {
    final repo = DelayedEvents();
    await tester.pumpWidget(
      MaterialApp(
        home: VenueEventsListPage(
          venueId: 'venue-a',
          events: const [],
          repository: repo,
          onRefresh: () {},
        ),
      ),
    );
    repo.first.completeError(StateError('network unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Could not load events'), findsOneWidget);
    expect(find.text('No events on this day'), findsNothing);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.reads, 2);
    expect(
      find.byKey(const ValueKey('events-initial-loading')),
      findsOneWidget,
    );
    repo.fresh.complete([]);
    await tester.pumpAndSettle();
    expect(find.text('No events on this day'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'an already-open date picker gets calendar dots before full event details arrive',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DelayedCalendar();
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventsListPage(
            venueId: 'venue-a',
            events: const [],
            repository: repo,
            onRefresh: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Range'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.calendar_today_outlined).first);
      await tester.pumpAndSettle();
      final dots = find.byWidgetPredicate(
        (widget) =>
            widget is Container &&
            widget.constraints?.maxWidth == 4 &&
            widget.constraints?.maxHeight == 4,
      );
      expect(dots, findsNothing);
      repo.calendar.complete([
        VenueEventCalendarEntry(id: 'event', startAt: DateTime.now()),
      ]);
      await tester.pumpAndSettle();
      expect(dots, findsOneWidget);
      expect(repo.first.isCompleted, false);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      repo.first.complete([]);
      await tester.pump();
    },
  );
  testWidgets(
    'updated events render immediately; late fetch cannot restore an old title or removed repeats',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DelayedEvents();
      final date = DateTime.now();
      final old = VenueUpcomingEvent(
        id: 'selected',
        title: 'Old Bicycle',
        startAt: date,
        endAt: date.add(const Duration(hours: 2)),
        recurringRuleId: 'rule',
      );
      final repeat = VenueUpcomingEvent(
        id: 'repeat',
        title: 'Future Bicycle',
        startAt: date.add(const Duration(days: 7)),
        endAt: date.add(const Duration(days: 7, hours: 2)),
        recurringRuleId: 'rule',
      );
      final updated = VenueUpcomingEvent(
        id: old.id,
        title: 'New Bicycle',
        startAt: old.startAt,
        endAt: old.endAt,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventsListPage(
            venueId: 'venue-a',
            events: [old, repeat],
            repository: repo,
            onRefresh: () {},
            detailPageBuilder: (context, event, onUpdated) => Scaffold(
              body: Center(
                child: TextButton(
                  child: const Text('Save test update'),
                  onPressed: () {
                    onUpdated(
                      VenueEventMutation(
                        event: updated,
                        events: [updated],
                        removedEventIds: {repeat.id},
                      ),
                    );
                    Navigator.pop(context, true);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Old Bicycle'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save test update'));
      await tester.pumpAndSettle();
      expect(find.text('New Bicycle'), findsOneWidget);
      expect(find.text('Old Bicycle'), findsNothing);
      repo.first.complete([old, repeat]);
      await tester.pumpAndSettle();
      expect(find.text('New Bicycle'), findsOneWidget);
      repo.fresh.complete([updated]);
      await tester.pumpAndSettle();
      expect(find.text('New Bicycle'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'saved events appear immediately and an older list response cannot erase them',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = DelayedEvents();
      final saved = VenueUpcomingEvent(
        id: 'server-created',
        title: 'New Running Event',
        startAt: DateTime(2026, 11, 9, 18),
        endAt: DateTime(2026, 11, 9, 20),
        recurringRuleId: 'server-rule',
      );
      var parentRefreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventsListPage(
            venueId: 'venue-a',
            events: const [],
            repository: repo,
            onRefresh: () => parentRefreshes++,
            createPageBuilder: (context, onCreated) => Scaffold(
              body: Center(
                child: TextButton(
                  child: const Text('Save test event'),
                  onPressed: () {
                    onCreated([saved]);
                    Navigator.pop(context, true);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save test event'));
      await tester.pumpAndSettle();
      expect(find.text('New Running Event'), findsOneWidget);
      expect(repo.first.isCompleted, false);
      expect(parentRefreshes, 0);
      // This fetch began before the server save and is now stale.
      repo.first.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('New Running Event'), findsOneWidget);
      expect(repo.reads, 2);
      repo.fresh.complete([saved]);
      await tester.pumpAndSettle();
      expect(find.text('New Running Event'), findsOneWidget);
      expect(parentRefreshes, 1);
      expect(tester.takeException(), isNull);
    },
  );
}
