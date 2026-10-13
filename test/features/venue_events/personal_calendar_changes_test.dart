import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Api extends ApiClient {
  Future<dynamic> Function() write = () async => {'success': true};
  final started = Completer<void>();
  String? method;
  String? path;
  Map<String, String>? headers;

  Future<dynamic> _write(String verb, String url, Map<String, String>? auth) {
    method = verb;
    path = url;
    headers = auth;
    if (!started.isCompleted) started.complete();
    return write();
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => _write('POST', path, headers);

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _write('DELETE', path, headers);
}

TodayEvent _entry(String id, DateTime start, {String venue = 'alpha'}) =>
    TodayEvent(
      event: VenueUpcomingEvent(
        id: id,
        title: 'Saved $id',
        description: 'Complete event description',
        startAt: start,
        endAt: start.add(const Duration(hours: 1)),
        photos: const ['photo-a', 'photo-b'],
        offerId: 'offer-a',
        offerType: 'BOGO',
        capacity: 30,
      ),
      venueId: venue,
      venueName: 'Test Cafe Alpha',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-user'});
    PendingPublicMediaService.instance.clear();
    VenueEventRepository.calendarChanges.value = null;
  });
  tearDown(() {
    PendingPublicMediaService.instance.clear();
    VenueEventRepository.calendarChanges.value = null;
  });

  final today = DateTime(2026, 10, 7, 12);
  PersonalEventCalendarChange change(TodayEvent? entry, {bool saved = true}) =>
      PersonalEventCalendarChange(
        venueId: 'alpha',
        eventId: 'event-a',
        saved: saved,
        session: 0,
        entry: entry,
      );

  test(
    'a committed save inserts today immediately without duplicates or losing fields',
    () {
      final entry = _entry('event-a', today);
      final later = _entry('later', today.add(const Duration(hours: 2)));
      final current = [later];
      final added = change(entry).applyToday(current, now: today);
      expect(added.map((item) => item.event.id), ['event-a', 'later']);
      expect(added.first, same(entry));
      expect(added.first.event.photos, ['photo-a', 'photo-b']);
      expect(added.first.event.offerId, 'offer-a');
      expect(change(entry).applyToday(added, now: today), hasLength(2));
      expect(current, [later]);
    },
  );

  test('future or past calendar entries never appear in Today’s events', () {
    for (final days in [-1, 1]) {
      final entry = _entry('event-a', today.add(Duration(days: days)));
      expect(change(entry).applyToday([], now: today), isEmpty);
    }
  });

  test('removal only affects the selected event and venue', () {
    final selected = _entry('event-a', today);
    final otherVenue = _entry('event-a', today, venue: 'beta');
    final otherEvent = _entry('event-b', today);
    final remaining = change(
      null,
      saved: false,
    ).applyToday([selected, otherVenue, otherEvent], now: today);
    expect(remaining, containsAll([otherVenue, otherEvent]));
    expect(remaining, isNot(contains(selected)));
  });

  test('unknown or mismatched snapshots do not add another event', () {
    final selected = _entry('event-a', today);
    expect(change(null).applyToday([selected], now: today), [selected]);
    expect(
      change(_entry('wrong-id', today)).applyToday([selected], now: today),
      [selected],
    );
    expect(
      change(_entry('wrong-id', today)).applyToday([], now: today),
      isEmpty,
    );
    expect(
      change(
        _entry('event-a', today, venue: 'beta'),
      ).applyToday([], now: today),
      isEmpty,
    );
  });

  for (final save in [true, false]) {
    Future<dynamic> mutate(VenueEventRepository repo) => save
        ? repo.rsvpEvent(
            venueId: 'alpha',
            eventId: 'event-a',
            calendarEntry: _entry('event-a', today),
          )
        : repo.cancelRsvp(venueId: 'alpha', eventId: 'event-a');

    test(
      '${save ? 'add' : 'remove'} emits only after an authenticated successful write',
      () async {
        final response = Completer<dynamic>();
        final api = _Api()..write = () => response.future;
        final request = mutate(VenueEventRepository(apiClient: api));
        await api.started.future;
        expect(VenueEventRepository.calendarChanges.value, isNull);
        response.complete({'success': true});
        await request;
        final committed = VenueEventRepository.calendarChanges.value!;
        expect(committed.saved, save);
        expect(committed.eventId, 'event-a');
        expect(committed.venueId, 'alpha');
        expect(
          committed.session,
          PendingPublicMediaService.instance.sessionGeneration,
        );
        expect(api.method, save ? 'POST' : 'DELETE');
        expect(api.path, '/venues/alpha/events/event-a/rsvp');
        expect(api.headers?['Authorization'], 'Bearer test-user');
      },
    );

    test(
      '${save ? 'add' : 'remove'} does not emit on API failure or a negative result',
      () async {
        for (final failure in [true, false]) {
          final api = _Api()
            ..write = () async {
              if (failure) throw StateError('server unavailable');
              return {'success': false};
            };
          await expectLater(
            mutate(VenueEventRepository(apiClient: api)),
            throwsStateError,
          );
          expect(VenueEventRepository.calendarChanges.value, isNull);
        }
      },
    );

    test(
      '${save ? 'add' : 'remove'} cannot update another login after a session change',
      () async {
        final response = Completer<dynamic>();
        final api = _Api()..write = () => response.future;
        final request = mutate(VenueEventRepository(apiClient: api));
        await api.started.future;
        PendingPublicMediaService.instance.clear();
        response.complete({'success': true});
        await request;
        expect(VenueEventRepository.calendarChanges.value, isNull);
      },
    );
    test(
      '${save ? 'add' : 'remove'} is not dispatched if the login changes while reading credentials',
      () async {
        final api = _Api();
        final request = mutate(VenueEventRepository(apiClient: api));
        PendingPublicMediaService.instance.clear();
        await expectLater(request, throwsStateError);
        expect(api.started.isCompleted, false);
        expect(VenueEventRepository.calendarChanges.value, isNull);
      },
    );
  }
}
