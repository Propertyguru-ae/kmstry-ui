import 'dart:async';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/venue/venue_read_changes.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Api extends ApiClient {
  _Api(this.respond);
  final Future<dynamic> Function(String path) respond;
  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => respond(path);
  @override
  Future<dynamic> patch(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => respond(path);
  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      respond(path);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    PendingPublicMediaService.instance.clear();
    VenueReadChanges.changes.value = null;
  });

  Map<String, dynamic> event() => {
    'id': 'event',
    'title': 'Event',
    'startAt': '2026-10-06T09:00:00Z',
    'endAt': '2026-10-06T10:00:00Z',
  };
  Map<String, dynamic> partnership() => {
    'id': 'partnership',
    'venue_id': 'venue',
    'platform': 'OTHER',
    'offer_type': 'OTHER',
    'offer_label': 'Benefit',
    'status': 'ACTIVE',
    'created_at': '2026-10-06T09:00:00Z',
  };
  void check(Set<VenueReadSection> sections) {
    final change = VenueReadChanges.changes.value!;
    expect(change.venueId, 'venue');
    expect(change.sections, sections);
    expect(
      change.session,
      PendingPublicMediaService.instance.sessionGeneration,
    );
  }

  test(
    'venue metadata commit invalidates identity only, with no cached result data',
    () async {
      await VenueOwnerRepository(
        apiClient: _Api((_) async => {'id': 'venue', 'name': 'New Name'}),
      ).updateVenue('venue', name: 'New Name');
      check({VenueReadSection.identity});
    },
  );

  test(
    'create/update/delete event and series invalidate events only after success',
    () async {
      var signals = 0;
      void listener() => signals++;
      VenueReadChanges.changes.addListener(listener);
      addTearDown(() => VenueReadChanges.changes.removeListener(listener));
      final repo = VenueEventRepository(apiClient: _Api((_) async => event()));
      await repo.createEvent(
        venueId: 'venue',
        title: 'Event',
        startAt: DateTime(2026, 10, 6),
        endAt: DateTime(2026, 10, 7),
      );
      check({VenueReadSection.events});
      await repo.updateEvent(
        venueId: 'venue',
        eventId: 'event',
        title: 'Update',
      );
      await repo.deleteEvent(venueId: 'venue', eventId: 'event');
      await repo.deleteRecurringSeries(venueId: 'venue', ruleId: 'series');
      check({VenueReadSection.events});
      expect(signals, 4);
    },
  );

  test(
    'partnership changes invalidate benefits and event relations; event assignment invalidates only events',
    () async {
      final repo = ExternalPartnershipRepository(
        apiClient: _Api(
          (path) async => path.contains('/events/')
              ? [
                  {'partnership': partnership()},
                ]
              : partnership(),
        ),
      );
      await repo.create(
        'venue',
        platform: 'OTHER',
        offerType: 'OTHER',
        offerLabel: 'Benefit',
      );
      check({VenueReadSection.partnerships, VenueReadSection.events});
      await repo.update('venue', 'partnership', {'offer_label': 'New'});
      check({VenueReadSection.partnerships, VenueReadSection.events});
      await repo.delete('venue', 'partnership');
      check({VenueReadSection.partnerships, VenueReadSection.events});
      await repo.setEventPartnerships('venue', 'event', ['partnership']);
      check({VenueReadSection.events});
    },
  );

  test('failed writes do not invalidate any retained data', () async {
    final api = _Api((_) async => throw StateError('write failed'));
    await expectLater(
      VenueOwnerRepository(apiClient: api).updateVenue('venue', name: 'New'),
      throwsStateError,
    );
    await expectLater(
      VenueEventRepository(
        apiClient: api,
      ).deleteEvent(venueId: 'venue', eventId: 'event'),
      throwsStateError,
    );
    await expectLater(
      ExternalPartnershipRepository(
        apiClient: api,
      ).delete('venue', 'partnership'),
      throwsStateError,
    );
    expect(VenueReadChanges.changes.value, isNull);
  });

  test(
    'a late successful write from a previous login cannot invalidate the new login',
    () async {
      final response = Completer<dynamic>();
      final repo = VenueOwnerRepository(
        apiClient: _Api((_) => response.future),
      );
      final pending = repo.updateVenue('venue', name: 'New');
      await Future<void>.delayed(Duration.zero);
      PendingPublicMediaService.instance.clear();
      response.complete({'id': 'venue', 'name': 'New'});
      await pending;
      expect(VenueReadChanges.changes.value, isNull);
    },
  );
}
