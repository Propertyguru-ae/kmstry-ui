import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/home/presentation/personal_home_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/personal_event_detail_page.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Checks extends VenueCheckinRepository {
  int calls = 0;
  @override
  Future<ActiveCheckin?> getActiveCheckin() async {
    calls++;
    return null;
  }
}

class _Stories extends StoryRepository {
  int calls = 0;
  @override
  Future<List<StoryGroup>> getHomeStories() async {
    calls++;
    return [];
  }

  @override
  Future<List<StoryItem>> getMyStories() async => [];
}

class _Events extends VenueEventRepository {
  final reads = <Completer<List<TodayEvent>>>[];
  @override
  Future<List<TodayEvent>> getMyTodayEvents() {
    final read = Completer<List<TodayEvent>>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<List<TodayEvent>> getFollowedVenuesEvents({int limit = 20}) async =>
      [];
  @override
  Future<List<TodayEvent>> getDiscoverEvents({
    double? latitude,
    double? longitude,
    int limit = 20,
    int offset = 0,
    String? platform,
    String? when,
    DateTime? from,
    DateTime? to,
    String? scope,
  }) async => [];
}

class _DetailApi extends ApiClient {
  _DetailApi(this.entry, {this.saved = false, this.interestedCount});
  final TodayEvent entry;
  final bool saved;
  final int? interestedCount;
  bool fail = false;
  int writes = 0;
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async => {
    'id': entry.event.id,
    'title': entry.event.title,
    'startAt': entry.event.startAt.toUtc().toIso8601String(),
    'endAt': entry.event.endAt.toUtc().toIso8601String(),
    'rsvpCount': interestedCount ?? (saved ? 1 : 0),
    'userHasRsvp': saved,
    'capacity': null,
  };
  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    writes++;
    if (fail) throw StateError('Could not save event');
    return {'success': true};
  }

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) async {
    writes++;
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Checks checks;
  late _Stories stories;
  late _Events events;
  late TodayEvent entry;
  late GlobalKey<NavigatorState> navigator;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-user'});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueEventRepository.calendarChanges.value = null;
    UserSession.instance.applyFromMe({'isPremium': false});
    checks = _Checks();
    stories = _Stories();
    events = _Events();
    navigator = GlobalKey<NavigatorState>();
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, 18);
    entry = TodayEvent(
      event: VenueUpcomingEvent(
        id: 'event-a',
        title: 'Today’s saved cycle event',
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
      ),
      venueId: 'alpha',
      venueName: 'Test Cafe Alpha',
    );
  });
  tearDown(() {
    PendingPublicMediaService.instance.clear();
    VenueEventRepository.calendarChanges.value = null;
    UserSession.instance.clear();
  });

  Future<void> openHome(WidgetTester tester, {bool active = true}) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: PersonalHomePage(
          checkinRepository: checks,
          storyRepository: stories,
          eventRepository: events,
          isActive: active,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDetail(WidgetTester tester, _DetailApi api) async {
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => PersonalEventDetailPage(
            event: api.entry.event,
            venueId: 'alpha',
            venueName: 'Test Cafe Alpha',
            apiClient: api,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'saving today uses calendar copy and immediately updates Home despite an older read',
    (tester) async {
      await openHome(tester);
      expect(events.reads, hasLength(1));
      // A real event can already have an interested user. Saving it must also
      // safely rebuild the overlapping avatar row from one person to two.
      final api = _DetailApi(entry, interestedCount: 1);
      await openDetail(tester, api);
      await tester.ensureVisible(find.text('Add to my calendar'));
      await tester.tap(find.text('Add to my calendar'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('2 people interested'), findsOneWidget);
      expect(find.text('Added to your calendar'), findsOneWidget);
      expect(
        find.text(
          '"${entry.event.title}" is now saved in your KMSTRY calendar.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('This does not reserve a place or confirm a booking.'),
        findsOneWidget,
      );
      expect(find.textContaining('Your spot is confirmed'), findsNothing);
      expect(find.text("You're In! 🎉"), findsNothing);
      expect(events.reads, hasLength(2));
      expect(api.writes, 1);
      // The initial read started before the save and must not undo it.
      events.reads.first.complete([]);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Got it'));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsOneWidget);
      expect(checks.calls, 1);
      expect(stories.calls, 1);
      expect(events.reads.last.isCompleted, false);
      events.reads.last.complete([entry]);
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final count in [2, 3, 10000]) {
    testWidgets(
      'event with $count interested users renders overlapping avatars and saves on a phone-sized page',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final api = _DetailApi(entry, interestedCount: count);
        await tester.pumpWidget(
          MaterialApp(
            home: PersonalEventDetailPage(
              event: entry.event,
              venueId: entry.venueId,
              venueName: entry.venueName,
              apiClient: api,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('$count people interested'));
        await tester.pumpAndSettle();
        expect(find.text('$count people interested'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Add to my calendar'));
        await tester.tap(find.text('Add to my calendar'));
        await tester.pumpAndSettle();
        expect(find.text('Added to your calendar'), findsOneWidget);
        expect(tester.takeException(), isNull);
        expect(find.text('${count + 1} people interested'), findsOneWidget);
        await tester.tap(find.text('Got it'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Remove from my calendar'));
        await tester.pumpAndSettle();
        expect(find.text('$count people interested'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  testWidgets(
    'removing a saved event immediately removes Home’s card without reloading other sections',
    (tester) async {
      await openHome(tester);
      events.reads.first.complete([entry]);
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsOneWidget);
      await openDetail(tester, _DetailApi(entry, saved: true));
      await tester.ensureVisible(find.text('Remove from my calendar'));
      await tester.tap(find.text('Remove from my calendar'));
      await tester.pumpAndSettle();
      navigator.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsNothing);
      expect(events.reads, hasLength(2));
      expect(checks.calls, 1);
      expect(stories.calls, 1);
      events.reads.last.complete([]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed save never claims a booking or inserts a Home event', (
    tester,
  ) async {
    await openHome(tester);
    events.reads.first.complete([]);
    await tester.pumpAndSettle();
    await openDetail(tester, _DetailApi(entry)..fail = true);
    await tester.ensureVisible(find.text('Add to my calendar'));
    await tester.tap(find.text('Add to my calendar'));
    await tester.pumpAndSettle();
    expect(find.text('Added to your calendar'), findsNothing);
    expect(VenueEventRepository.calendarChanges.value, isNull);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text(entry.event.title), findsNothing);
    expect(events.reads, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'retained hidden Home updates today without waiting for the 10-second return refresh',
    (tester) async {
      await openHome(tester, active: false);
      events.reads.first.complete([]);
      await tester.pumpAndSettle();
      final repo = VenueEventRepository(apiClient: _DetailApi(entry));
      await repo.rsvpEvent(
        venueId: 'alpha',
        eventId: entry.event.id,
        calendarEntry: entry,
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsOneWidget);
      expect(events.reads, hasLength(2));
      expect(checks.calls, 1);
      events.reads.last.complete([entry]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a tomorrow save is not shown in today and stale-session changes are ignored',
    (tester) async {
      await openHome(tester);
      events.reads.first.complete([]);
      await tester.pumpAndSettle();
      final tomorrow = TodayEvent(
        event: VenueUpcomingEvent(
          id: 'future',
          title: 'Tomorrow event',
          startAt: entry.event.startAt.add(const Duration(days: 1)),
          endAt: entry.event.endAt.add(const Duration(days: 1)),
        ),
        venueId: 'alpha',
        venueName: 'Test Cafe Alpha',
      );
      await VenueEventRepository(
        apiClient: _DetailApi(tomorrow),
      ).rsvpEvent(venueId: 'alpha', eventId: 'future', calendarEntry: tomorrow);
      await tester.pumpAndSettle();
      expect(find.text('Tomorrow event'), findsNothing);
      expect(events.reads, hasLength(2));
      events.reads.last.complete([]);
      final oldSession = PendingPublicMediaService.instance.sessionGeneration;
      PendingPublicMediaService.instance.clear();
      VenueEventRepository.calendarChanges.value = PersonalEventCalendarChange(
        venueId: 'alpha',
        eventId: entry.event.id,
        saved: true,
        session: oldSession,
        entry: entry,
      );
      await tester.pumpAndSettle();
      expect(find.text(entry.event.title), findsNothing);
      expect(events.reads, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
