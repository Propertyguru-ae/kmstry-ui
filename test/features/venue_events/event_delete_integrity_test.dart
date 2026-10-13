import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/event_photo_upload_coordinator.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_calendar_store.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_deletion.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

final _token =
    'header.${base64Url.encode(utf8.encode(jsonEncode({'sub': 'owner'})))}.signature';

class _DeleteApi extends ApiClient {
  final response = Completer<dynamic>();
  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      response.future;
}

class _Events extends VenueEventRepository {
  Future<List<VenueUpcomingEvent>> Function()? read;
  @override
  Future<List<VenueUpcomingEvent>> listEventMonth(
    String venueId,
    DateTime month,
  ) => read!();
}

PendingPublicMedia _draft(
  String id, {
  String venue = 'venue',
  String? event,
  String? rule,
}) => PendingPublicMedia(
  id: id,
  kind: PendingPublicMediaKind.eventPhoto,
  venueId: venue,
  eventId: event,
  recurringRuleId: rule,
  localPath: 'assets/images/kmstrylogo.png',
  isVideo: false,
  createdAt: DateTime(2026, 11, 1),
  hasServerReceipt: false,
);
VenueUpcomingEvent _event(String id, int day, {String? rule}) =>
    VenueUpcomingEvent(
      id: id,
      title: id,
      startAt: DateTime(2026, 11, day, 18),
      endAt: DateTime(2026, 11, day, 20),
      recurringRuleId: rule,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late PendingPublicMediaService service;
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': _token});
    service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) async => const MediaModerationSnapshot(),
      delay: (_) => Completer<void>().future,
    );
  });
  tearDown(() => service.clear());

  test(
    'single deletion cancels only that occurrence, not shared series media or another venue',
    () {
      for (final item in [
        _draft('single', event: 'selected'),
        _draft('shared', rule: 'rule'),
        _draft('foreign', venue: 'other', event: 'selected'),
      ]) {
        service.prepareUpload(
          item,
          expectedGeneration: service.sessionGeneration,
        );
      }
      service.confirmEventDeletion(
        venueId: 'venue',
        removedEventIds: {'selected'},
        expectedGeneration: service.sessionGeneration,
      );
      expect(service.items.map((item) => item.id), {'shared', 'foreign'});
      expect(service.eventPhotoCancellation('single').isCancelled, true);
      expect(service.eventPhotoCancellation('shared').isCancelled, false);
    },
  );

  test(
    'deleting a series cancels preparing and queued jobs without sending them',
    () async {
      final prepared = Completer<File>();
      var sends = 0;
      var preparations = 0;
      final coordinator = EventPhotoUploadCoordinator.forTest(
        service: service,
        prepare: (_) {
          preparations++;
          return prepared.future;
        },
        sender: (_, _, _) async => sends++,
      );
      final jobs = coordinator.share(
        venueId: 'venue',
        recurringRuleId: 'rule',
        files: [File('first'), File('second')],
        expectedGeneration: service.sessionGeneration,
      );
      service.confirmEventDeletion(
        venueId: 'venue',
        removedEventIds: {'selected'},
        removedRecurringRuleId: 'rule',
        expectedGeneration: service.sessionGeneration,
      );
      prepared.complete(File('assets/images/kmstrylogo.png'));
      await jobs.completed;
      expect(sends, 0);
      expect(preparations, 1);
      expect(service.items, isEmpty);
    },
  );

  test(
    'late receipt from an in-flight upload cannot restore deleted target previews',
    () async {
      final draft = _draft('active', event: 'selected');
      service.prepareUpload(
        draft,
        expectedGeneration: service.sessionGeneration,
      );
      final response = Completer<Map<String, dynamic>>();
      final started = Completer<void>();
      final upload = service.runUpload<Map<String, dynamic>>(
        draft: draft,
        token: _token,
        expectedGeneration: service.sessionGeneration,
        receiptId: (json) => json['moderation_item_id'] as String?,
        send: (_) {
          started.complete();
          return response.future;
        },
      );
      final failed = expectLater(
        upload,
        throwsA(isA<PublicMediaUploadCancelled>()),
      );
      await started.future;
      service.confirmEventDeletion(
        venueId: 'venue',
        removedEventIds: {'selected'},
        expectedGeneration: service.sessionGeneration,
      );
      response.complete({'moderation_item_id': 'late-receipt'});
      await failed;
      expect(service.items, isEmpty);
      expect(service.eventPhotoCancellation('active').isCancelled, true);
    },
  );

  test(
    'repository cancels only after server confirms a deletion, including last-occurrence rule removal',
    () async {
      final api = _DeleteApi();
      service.prepareUpload(
        _draft('shared', rule: 'rule'),
        expectedGeneration: service.sessionGeneration,
      );
      final deletion = VenueEventRepository(
        apiClient: api,
        uploads: service,
      ).deleteEvent(venueId: 'venue', eventId: 'selected');
      expect(service.items, hasLength(1));
      api.response.complete({
        'success': true,
        'removedEventIds': ['selected'],
        'removedRecurringRuleId': 'rule',
      });
      final result = await deletion;
      expect(result.removedRecurringRuleId, 'rule');
      expect(service.items, isEmpty);
    },
  );

  test('a failed deletion leaves pending media intact', () async {
    final api = _DeleteApi();
    service.prepareUpload(
      _draft('active', event: 'selected'),
      expectedGeneration: service.sessionGeneration,
    );
    final deletion = VenueEventRepository(
      apiClient: api,
      uploads: service,
    ).deleteEvent(venueId: 'venue', eventId: 'selected');
    final failed = expectLater(deletion, throwsA(isA<ApiException>()));
    api.response.completeError(
      ApiException(statusCode: 409, data: {'errorCode': 'EVENT_HAS_TICKETS'}),
    );
    await failed;
    expect(service.items.single.id, 'active');
    expect(service.eventPhotoCancellation('active').isCancelled, false);
  });

  test('old-session deletion cannot cancel a new session upload', () async {
    final api = _DeleteApi();
    final deletion = VenueEventRepository(
      apiClient: api,
      uploads: service,
    ).deleteEvent(venueId: 'venue', eventId: 'selected');
    await Future<void>.delayed(Duration.zero);
    service.clear();
    service.prepareUpload(
      _draft('new', event: 'selected'),
      expectedGeneration: service.sessionGeneration,
    );
    api.response.complete({
      'success': true,
      'removedEventIds': ['selected'],
    });
    await deletion;
    expect(service.items.single.id, 'new');
    expect(service.isEventPhotoTargetDeleted(service.items.single), false);
  });

  test(
    'calendar removes all deleted dots/rows immediately without invalidating an authoritative empty month',
    () async {
      final events = [
        _event('past', 1, rule: 'rule'),
        _event('future', 8, rule: 'rule'),
        _event('keep', 9),
      ];
      final repo = _Events()..read = () async => events;
      final calendar = VenueEventCalendarStore(
        venueId: 'venue',
        repository: repo,
        isCurrentSession: () => true,
      );
      addTearDown(calendar.dispose);
      await calendar.loadMonth(DateTime(2026, 11));
      calendar.removed(
        const VenueEventDeletion(
          removedEventIds: {'past', 'future'},
          removedRecurringRuleId: 'rule',
        ),
      );
      expect(calendar.events.single.id, 'keep');
      expect(calendar.daysWithEvents, {'2026-11-9'});
      calendar.removed(const VenueEventDeletion(removedEventIds: {'keep'}));
      expect(calendar.events, isEmpty);
      expect(calendar.hasLoadedSelection(DateTime(2026, 11, 9), null), true);
    },
  );

  test('an older month response cannot resurrect a removed event', () async {
    final response = Completer<List<VenueUpcomingEvent>>();
    final repo = _Events()..read = () => response.future;
    final calendar = VenueEventCalendarStore(
      venueId: 'venue',
      repository: repo,
      isCurrentSession: () => true,
      seed: [_event('selected', 1), _event('keep', 2)],
    );
    addTearDown(calendar.dispose);
    final read = calendar.loadMonth(DateTime(2026, 11));
    calendar.removed(const VenueEventDeletion(removedEventIds: {'selected'}));
    response.complete([_event('selected', 1)]);
    await read;
    expect(calendar.events.single.id, 'keep');
    expect(calendar.daysWithEvents, {'2026-11-2'});
  });
}
