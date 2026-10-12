import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';
import 'package:kmstry_frontend/features/venue_events/data/event_photo_upload_coordinator.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';

class EventRepositoryFake extends VenueEventRepository {
  int saves = 0;
  @override
  Future<VenueEventMutation> updateEvent({
    required String venueId,
    required String eventId,
    String? title,
    String? description,
    DateTime? startAt,
    DateTime? endAt,
    int? priceAed,
    bool clearPrice = false,
    String? currency,
    int? capacity,
    bool clearCapacity = false,
    String? editScope,
    Map<String, dynamic>? recurrence,
    bool clearRecurrence = false,
    List<String>? partnershipIds,
    Map<String, dynamic>? offer,
    bool clearOffer = false,
  }) async {
    saves++;
    final event = VenueUpcomingEvent(
      id: eventId,
      title: title!,
      startAt: startAt!,
      endAt: endAt!,
    );
    return VenueEventMutation(event: event, events: [event]);
  }
}

class PartnershipsFake extends ExternalPartnershipRepository {
  @override
  Future<List<ExternalPartnershipModel>> getPartnerships(
    String venueId,
  ) async => [];
  @override
  Future<List<ExternalPartnershipModel>> setEventPartnerships(
    String venueId,
    String eventId,
    List<String> partnershipIds,
  ) async => [];
}

void main() {
  testWidgets(
    'saving closes the editor without waiting for photo preparation, transfer or moderation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final prepared = Completer<File>();
      final repo = EventRepositoryFake();
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) async => const MediaModerationSnapshot(),
        delay: (_) => Completer<void>().future,
      );
      final coordinator = EventPhotoUploadCoordinator.forTest(
        service: uploads,
        prepare: (_) => prepared.future,
        sender: (_, _, _) async {},
      );
      final event = VenueUpcomingEvent(
        id: 'event-a',
        title: 'Live Session',
        startAt: DateTime(2026, 11, 1, 18),
        endAt: DateTime(2026, 11, 1, 20),
      );
      bool? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('Open editor'),
                onPressed: () async {
                  saved = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AddVenueEventPage(
                        venueId: 'venue-a',
                        existing: event,
                        repository: repo,
                        photoUploads: coordinator,
                        partnershipRepository: PartnershipsFake(),
                        photoPicker: () async =>
                            File('assets/images/kmstrylogo.png'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Add').first);
      await tester.tap(find.text('Add').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(saved, true);
      expect(find.text('Open editor'), findsOneWidget);
      expect(find.byType(AddVenueEventPage), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(uploads.items.single.state, PendingPublicMediaState.preparing);
      expect(prepared.isCompleted, false);
      expect(tester.takeException(), isNull);
      uploads.clear();
      prepared.complete(File('assets/images/kmstrylogo.png'));
      await tester.pump();
    },
  );
}
