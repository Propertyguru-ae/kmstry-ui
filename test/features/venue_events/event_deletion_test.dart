import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_deletion.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

class _Events extends VenueEventRepository {
  final calls = <String>[];
  Completer<VenueEventDeletion>? gate;
  Object? failure;
  @override
  Future<List<Map<String, dynamic>>> getEventRsvps({
    required String venueId,
    required String eventId,
  }) async => [];
  Future<VenueEventDeletion> _delete(
    String call,
    VenueEventDeletion result,
  ) async {
    calls.add(call);
    if (failure != null) throw failure!;
    return gate?.future ?? result;
  }

  @override
  Future<VenueEventDeletion> deleteEvent({
    required String venueId,
    required String eventId,
  }) => _delete(
    'single:$venueId:$eventId',
    const VenueEventDeletion(removedEventIds: {'selected'}),
  );
  @override
  Future<VenueEventDeletion> deleteRecurringSeries({
    required String venueId,
    required String ruleId,
  }) => _delete(
    'series:$venueId:$ruleId',
    const VenueEventDeletion(
      removedEventIds: {'past', 'selected', 'future'},
      removedRecurringRuleId: 'rule',
    ),
  );
}

Future<void> _open(
  WidgetTester tester,
  _Events repo,
  ValueChanged<VenueEventDeletion> deleted, {
  bool recurring = true,
}) async {
  tester.view.physicalSize = const Size(1000, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            child: const Text('Open event'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => VenueEventDetailPage(
                  venueId: 'venue',
                  event: VenueUpcomingEvent(
                    id: 'selected',
                    title: 'Running',
                    startAt: DateTime(2026, 11, 1, 18),
                    endAt: DateTime(2026, 11, 1, 20),
                    recurringRuleId: recurring ? 'rule' : null,
                  ),
                  repository: repo,
                  onDeleted: deleted,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open event'));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.delete_outline_rounded));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test'});
    PendingPublicMediaService.instance.clear();
    await VenueSession.instance.load('venue', VenueMemberRole.owner);
  });
  tearDown(() {
    VenueSession.instance.clear();
    PendingPublicMediaService.instance.clear();
  });

  testWidgets(
    'series deletion requires a past/future warning; Cancel makes no request',
    (tester) async {
      final repo = _Events();
      await _open(tester, repo, (_) => fail('No deletion should be published'));
      expect(find.text('Only this event'), findsOneWidget);
      expect(find.text('All events in series'), findsOneWidget);
      await tester.tap(find.text('All events in series'));
      await tester.pumpAndSettle();
      expect(find.textContaining('All past and future events'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.calls, isEmpty);
      expect(find.byType(VenueEventDetailPage), findsOneWidget);
    },
  );

  testWidgets(
    'series deletion uses the series endpoint once and publishes exact removals only after success',
    (tester) async {
      final repo = _Events()..gate = Completer<VenueEventDeletion>();
      VenueEventDeletion? deleted;
      await _open(tester, repo, (result) => deleted = result);
      await tester.tap(find.text('All events in series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete series'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['series:venue:rule']);
      expect(deleted, isNull);
      await tester.tap(find.byIcon(Icons.delete_outline_rounded));
      await tester.pump();
      expect(repo.calls, hasLength(1));
      expect(find.text('All events in series'), findsNothing);
      repo.gate!.complete(
        const VenueEventDeletion(
          removedEventIds: {'past', 'selected', 'future'},
          removedRecurringRuleId: 'rule',
        ),
      );
      await tester.pumpAndSettle();
      expect(deleted!.removedEventIds, {'past', 'selected', 'future'});
      expect(deleted!.removedRecurringRuleId, 'rule');
      expect(find.byType(VenueEventDetailPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Only this event keeps the series and uses only the occurrence endpoint',
    (tester) async {
      final repo = _Events();
      VenueEventDeletion? deleted;
      await _open(tester, repo, (result) => deleted = result);
      await tester.tap(find.text('Only this event'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Other events in this series will be kept'),
        findsOneWidget,
      );
      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['single:venue:selected']);
      expect(deleted!.removedRecurringRuleId, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'non-recurring event goes directly to single deletion confirmation',
    (tester) async {
      final repo = _Events();
      await _open(tester, repo, (_) {}, recurring: false);
      expect(find.text('Only this event'), findsNothing);
      expect(find.textContaining('Other events in this series'), findsNothing);
      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();
      expect(repo.calls, ['single:venue:selected']);
    },
  );

  testWidgets(
    'ticket conflict explains why deletion is blocked without leaving the detail page',
    (tester) async {
      final repo = _Events()
        ..failure = ApiException(
          statusCode: 409,
          data: {'errorCode': 'EVENT_HAS_TICKETS'},
        );
      await _open(
        tester,
        repo,
        (_) => fail('Failed deletion cannot update the list'),
      );
      await tester.tap(find.text('All events in series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete series'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('has tickets and cannot be deleted'),
        findsOneWidget,
      );
      expect(find.byType(VenueEventDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late deletion completion after logout cannot update or close the new session',
    (tester) async {
      final repo = _Events()..gate = Completer<VenueEventDeletion>();
      await _open(
        tester,
        repo,
        (_) => fail('Old session callback must be ignored'),
      );
      await tester.tap(find.text('Only this event'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete event'));
      await tester.pumpAndSettle();
      PendingPublicMediaService.instance.clear();
      VenueSession.instance.clear();
      repo.gate!.complete(
        const VenueEventDeletion(removedEventIds: {'selected'}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VenueEventDetailPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'deletion still updates the parent list after the owner leaves the detail page',
    (tester) async {
      final repo = _Events()..gate = Completer<VenueEventDeletion>();
      VenueEventDeletion? deleted;
      await _open(tester, repo, (result) => deleted = result);
      await tester.tap(find.text('All events in series'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete series'));
      await tester.pumpAndSettle();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(VenueEventDetailPage), findsNothing);
      repo.gate!.complete(
        const VenueEventDeletion(
          removedEventIds: {'selected'},
          removedRecurringRuleId: 'rule',
        ),
      );
      await tester.pumpAndSettle();
      expect(deleted!.removedRecurringRuleId, 'rule');
      expect(tester.takeException(), isNull);
    },
  );
}
