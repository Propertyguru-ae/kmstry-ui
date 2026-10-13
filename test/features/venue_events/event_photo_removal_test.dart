import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

PendingPublicMedia photo({
  PendingPublicMediaState state = PendingPublicMediaState.underReview,
  bool receipt = true,
}) => PendingPublicMedia(
  id: 'receipt-a',
  uploadId: 'upload-a',
  kind: PendingPublicMediaKind.eventPhoto,
  venueId: 'venue-a',
  recurringRuleId: 'series-a',
  localPath: '',
  isVideo: false,
  createdAt: DateTime.now(),
  state: state,
  hasServerReceipt: receipt,
);

class _Api extends ApiClient {
  final requests = <String>[];
  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) async {
    requests.add(path);
    expect(headers?['Authorization'], 'Bearer test-token');
    return {'ok': true, 'removed': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'removal uses the exact receipt and JWT, never a private photo URL',
    () async {
      FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
      final api = _Api();
      await ContentModerationRepository(apiClient: api).removeEventPhotoUpload(
        venueId: 'venue-a',
        itemId: 'receipt-a',
        isCurrentSession: () => true,
      );
      expect(api.requests, ['/venues/venue-a/events/photo-uploads/receipt-a']);
    },
  );

  test('a changed login cannot send a removal request', () async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-token'});
    final api = _Api();
    await expectLater(
      ContentModerationRepository(apiClient: api).removeEventPhotoUpload(
        venueId: 'venue-a',
        itemId: 'receipt-a',
        isCurrentSession: () => false,
      ),
      throwsStateError,
    );
    expect(api.requests, isEmpty);
  });

  test(
    'series preview remains until confirmed removal, then disappears for every occurrence',
    () async {
      final removal = Completer<void>();
      var calls = 0;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        removeEventPhoto: (item, isCurrentSession) {
          calls++;
          expect(item.id, 'receipt-a');
          expect(isCurrentSession(), true);
          return removal.future;
        },
      );
      addTearDown(service.clear);
      service.track(photo());
      final pending = service.removeEventPhoto(
        'receipt-a',
        expectedGeneration: service.sessionGeneration,
      );
      await service.removeEventPhoto(
        'receipt-a',
        expectedGeneration: service.sessionGeneration,
      );
      expect(calls, 1);
      expect(service.isRemovingEventPhoto('receipt-a'), true);
      expect(
        service.items.single.belongsToEvent(
          'venue-a',
          'occurrence-1',
          'series-a',
        ),
        true,
      );
      expect(
        service.items.single.belongsToEvent(
          'venue-a',
          'occurrence-2',
          'series-a',
        ),
        true,
      );
      removal.complete();
      await pending;
      expect(service.items, isEmpty);
      expect(service.eventPublicationChanges.value, 1);
    },
  );

  test('failed removal preserves the review and permits a retry', () async {
    var fail = true;
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
      removeEventPhoto: (_, _) async {
        if (fail) throw StateError('offline');
      },
    );
    addTearDown(service.clear);
    service.track(photo());
    await expectLater(
      service.removeEventPhoto(
        'receipt-a',
        expectedGeneration: service.sessionGeneration,
      ),
      throwsStateError,
    );
    expect(
      service.byId('receipt-a')?.state,
      PendingPublicMediaState.underReview,
    );
    expect(service.isRemovingEventPhoto('receipt-a'), false);
    fail = false;
    await service.removeEventPhoto(
      'receipt-a',
      expectedGeneration: service.sessionGeneration,
    );
    expect(service.items, isEmpty);
  });

  test('a late approval cannot publish or restore a removed preview', () async {
    final decision = Completer<MediaModerationSnapshot>();
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => true,
      moderationLookup: (_) => decision.future,
      delay: (_) => Completer<void>().future,
      removeEventPhoto: (_, _) async {},
    );
    addTearDown(service.clear);
    service.track(photo());
    await service.removeEventPhoto(
      'receipt-a',
      expectedGeneration: service.sessionGeneration,
    );
    decision.complete(
      const MediaModerationSnapshot(
        status: 'APPROVED',
        photoPublication: 'PUBLISHED',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(service.items, isEmpty);
    expect(service.wasPublished('receipt-a'), false);
  });

  test('a late removal result cannot remove an item in a new login', () async {
    final removal = Completer<void>();
    final service = PendingPublicMediaService.forTest(
      publishedLookup: (_) async => false,
      moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
      delay: (_) => Completer<void>().future,
      removeEventPhoto: (_, _) => removal.future,
    );
    addTearDown(service.clear);
    service.track(photo());
    final request = service.removeEventPhoto(
      'receipt-a',
      expectedGeneration: service.sessionGeneration,
    );
    service.clear();
    service.track(photo());
    removal.complete();
    await request;
    expect(service.byId('receipt-a'), isNotNull);
  });

  test(
    'only a definite local failure can be removed without a server receipt',
    () async {
      var calls = 0;
      final service = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
        removeEventPhoto: (_, _) async => calls++,
      );
      addTearDown(service.clear);
      service.track(
        photo(state: PendingPublicMediaState.connectionIssue, receipt: false),
      );
      await expectLater(
        service.removeEventPhoto(
          'receipt-a',
          expectedGeneration: service.sessionGeneration,
        ),
        throwsStateError,
      );
      expect(service.items, hasLength(1));
      service.dismiss('receipt-a');
      service.track(
        photo(state: PendingPublicMediaState.failed, receipt: false),
      );
      await service.removeEventPhoto(
        'receipt-a',
        expectedGeneration: service.sessionGeneration,
      );
      expect(service.items, isEmpty);
      expect(calls, 0);
    },
  );
}
