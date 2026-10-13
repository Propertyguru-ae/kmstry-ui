import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_repository.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_mutation.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/add_venue_event_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

const _deal = EventPartnerBenefit(
  id: 'deal-1',
  platform: 'THE_ENTERTAINER',
  offerType: 'BOGO',
  offerLabel: '2-for-1 cocktails',
);

/// The atomic response carries metadata and every committed scoped deal.
class EditedEventRepository extends VenueEventRepository {
  EditedEventRepository({this.gate});
  final Completer<void>? gate;
  int detailReads = 0;
  int attendeeReads = 0;
  int saves = 0;
  String? lastTitle;
  String? lastEditScope;
  List<String>? lastPartnershipIds;
  Map<String, dynamic>? lastOffer;
  bool lastClearOffer = false;
  VenueUpcomingEvent? committedEvent;

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
    lastTitle = title;
    lastEditScope = editScope;
    lastPartnershipIds = partnershipIds;
    lastOffer = offer;
    lastClearOffer = clearOffer;
    if (gate != null) await gate!.future;
    final event =
        committedEvent ??
        VenueUpcomingEvent(
          id: eventId,
          title: title!,
          startAt: startAt!,
          endAt: endAt!,
          partnershipBenefits: partnershipIds?.contains(_deal.id) == true
              ? const [_deal]
              : const [],
          offerId: offer == null ? null : 'offer-1',
          offerType: offer?['type'] as String?,
          offerTitle: offer?['title'] as String?,
          offerPrice: (offer?['price'] as num?)?.toDouble(),
        );
    return VenueEventMutation(event: event, events: [event]);
  }

  @override
  Future<VenueUpcomingEvent> getEventDetail({
    required String venueId,
    required String eventId,
  }) async {
    detailReads++;
    return VenueUpcomingEvent(
      id: eventId,
      title: 'Kosu',
      startAt: DateTime(2026, 11, 1, 18),
      endAt: DateTime(2026, 11, 1, 20),
      partnershipBenefits: const [_deal],
    );
  }

  @override
  Future<List<Map<String, dynamic>>> getEventRsvps({
    required String venueId,
    required String eventId,
  }) async {
    attendeeReads++;
    return [];
  }
}

class PartnershipsFake extends ExternalPartnershipRepository {
  PartnershipsFake({this.available = const [], this.gate});
  final List<ExternalPartnershipModel> available;
  final Completer<List<ExternalPartnershipModel>>? gate;
  final written = <List<String>>[];
  @override
  Future<List<ExternalPartnershipModel>> getPartnerships(
    String venueId,
  ) async => available;
  @override
  Future<List<ExternalPartnershipModel>> setEventPartnerships(
    String venueId,
    String eventId,
    List<String> partnershipIds,
  ) async {
    written.add(List.of(partnershipIds));
    return gate == null ? available : gate!.future;
  }
}

class OffersFake extends VenueOfferRepository {
  OffersFake({this.gate, this.lookupGate});
  final Completer<VenueOfferModel>? gate;
  final Completer<List<VenueOfferModel>>? lookupGate;
  final updated = <String>[];
  final updateBodies = <Map<String, dynamic>>[];
  int created = 0;
  int reads = 0;

  VenueOfferModel _offer(String id, {required bool active}) => VenueOfferModel(
    id: id,
    venueId: 'venue-a',
    eventId: 'event-a',
    title: 'Free buffet',
    type: VenueOfferType.BUFFET,
    redemptionsUsed: 0,
    isActive: active,
    createdAt: DateTime(2026, 10, 1),
  );

  @override
  Future<List<VenueOfferModel>> getOffers(String venueId) async {
    reads++;
    if (lookupGate != null) return lookupGate!.future;
    return [
      _offer('offer-old', active: false),
      _offer('offer-1', active: true),
    ];
  }

  @override
  Future<VenueOfferModel> update(
    String venueId,
    String offerId,
    Map<String, dynamic> updates,
  ) async {
    updated.add(offerId);
    updateBodies.add(Map.of(updates));
    return gate == null ? _offer(offerId, active: true) : gate!.future;
  }

  @override
  Future<VenueOfferModel> create(
    String venueId,
    Map<String, dynamic> body,
  ) async {
    created++;
    return _offer('offer-new', active: true);
  }
}

ExternalPartnershipModel _partnership() => ExternalPartnershipModel(
  id: _deal.id,
  venueId: 'venue-a',
  platform: ExternalPartnershipPlatform.THE_ENTERTAINER,
  offerType: ExternalPartnershipOfferType.BOGO,
  offerLabel: _deal.offerLabel,
  status: ExternalPartnershipStatus.ACTIVE,
  createdAt: DateTime(2026, 10, 1),
);

VenueUpcomingEvent _event({
  bool withLinks = false,
  String title = 'Kosu',
  bool recurring = false,
}) => VenueUpcomingEvent(
  id: 'event-a',
  title: title,
  startAt: DateTime(2026, 11, 1, 18),
  endAt: DateTime(2026, 11, 1, 20),
  partnershipBenefits: withLinks ? const [_deal] : const [],
  offerId: withLinks ? 'offer-1' : null,
  offerType: withLinks ? 'BUFFET' : null,
  offerTitle: withLinks ? 'Free buffet' : null,
  offerPrice: withLinks ? 75.5 : null,
  recurringRuleId: recurring ? 'rule' : null,
  recurrence: recurring
      ? RecurrenceInfo(frequency: 'weekly', interval: 1, maxOccurrences: 5)
      : null,
);

Future<void> _selectDeal(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Select partner benefits…'));
  await tester.tap(find.text('Select partner benefits…'));
  await tester.pumpAndSettle();
  await tester.tap(find.textContaining('2-for-1 cocktails'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Apply (1)'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'NO_TEST_NETWORK'),
        );
    PendingPublicMediaService.instance.clear();
    VenueSession.instance.clear();
    await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
  });
  tearDown(() {
    VenueSession.instance.clear();
    PendingPublicMediaService.instance.clear();
  });

  testWidgets('deals saved in the editor show on the detail page right away', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = EditedEventRepository();
    final partnerships = PartnershipsFake(available: [_partnership()]);
    await tester.pumpWidget(
      MaterialApp(
        home: VenueEventDetailPage(
          event: VenueUpcomingEvent(
            id: 'event-a',
            title: 'Kosu',
            startAt: DateTime(2026, 11, 1, 18),
            endAt: DateTime(2026, 11, 1, 20),
          ),
          venueId: 'venue-a',
          repository: repo,
          partnershipRepository: partnerships,
          offerRepository: OffersFake(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PARTNER BENEFITS'), findsNothing);

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await _selectDeal(tester);
    await tester.tap(find.text('Save Changes'));
    await tester.pumpAndSettle();

    expect(find.byType(AddVenueEventPage), findsNothing);
    expect(repo.detailReads, 0);
    expect(repo.attendeeReads, 1);
    expect(partnerships.written, isEmpty);
    expect(repo.lastPartnershipIds, ['deal-1']);
    expect(find.text('PARTNER BENEFITS'), findsOneWidget);
    expect(find.text('2-for-1 cocktails'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'metadata-only edit uses the committed response without redundant linked writes or detail/attendee reads',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = EditedEventRepository()
        ..committedEvent = _event(withLinks: true, title: 'Updated running');
      final partnerships = PartnershipsFake(available: [_partnership()]);
      final offers = OffersFake();
      VenueEventMutation? applied;
      int refreshes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: VenueEventDetailPage(
            event: _event(withLinks: true),
            venueId: 'venue-a',
            repository: repo,
            partnershipRepository: partnerships,
            offerRepository: offers,
            onUpdated: (mutation) => applied = mutation,
            onChanged: () => refreshes++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == 'Kosu',
      );
      await tester.enterText(title, 'Updated running');
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(find.byType(AddVenueEventPage), findsNothing);
      expect(repo.saves, 1);
      expect(repo.lastTitle, 'Updated running');
      expect(find.text('Updated running'), findsWidgets);
      expect(partnerships.written, isEmpty);
      expect(repo.lastPartnershipIds, isNull);
      expect(repo.lastOffer, isNull);
      expect(offers.reads, 0);
      expect(offers.updated, isEmpty);
      expect(offers.created, 0);
      expect(repo.detailReads, 0);
      expect(repo.attendeeReads, 1);
      expect(refreshes, 0);
      expect(applied!.requiresDetailRefresh, false);
      expect(applied!.event.offerPrice, 75.5);
      expect(applied!.event.partnershipBenefits, [_deal]);
      expect(find.text('2-for-1 cocktails'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'changed partnerships and offer commit atomically before updating detail or closing',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final commitGate = Completer<void>();
      final repo = EditedEventRepository(gate: commitGate);
      final partnerships = PartnershipsFake(available: [_partnership()]);
      final offers = OffersFake();
      VenueEventMutation? applied;
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
                        existing: _event(withLinks: true),
                        repository: repo,
                        partnershipRepository: partnerships,
                        offerRepository: offers,
                        onUpdated: (mutation) => applied = mutation,
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
      await tester.ensureVisible(find.byIcon(Icons.close_rounded));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      final offerTitle = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == 'Free buffet',
      );
      await tester.ensureVisible(offerTitle);
      await tester.enterText(offerTitle, 'Updated buffet');
      await tester.pump();
      expect(find.text('Updated buffet'), findsOneWidget);
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(partnerships.written, isEmpty);
      expect(repo.lastPartnershipIds, []); // Explicit clearing in the PATCH.
      expect(offers.created, 0);
      expect(offers.updated, isEmpty);
      expect(offers.reads, 0);
      expect(repo.lastOffer!['price'], 75.5);
      expect(repo.lastOffer!['title'], 'Updated buffet');
      expect(applied, isNull);
      expect(saved, isNull);
      commitGate.complete();
      await tester.pumpAndSettle();
      expect(saved, true);
      expect(applied!.requiresDetailRefresh, false);
      expect(applied!.event.partnershipBenefits, isEmpty);
      expect(applied!.event.offerTitle, 'Updated buffet');
      expect(find.byType(AddVenueEventPage), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'public-text rejection in the atomic PATCH keeps the editor open without committing a partial change',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final gate = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: AddVenueEventPage(
            venueId: 'venue-a',
            existing: _event(withLinks: true),
            repository: EditedEventRepository(gate: gate),
            partnershipRepository: PartnershipsFake(),
            offerRepository: OffersFake(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final offerTitle = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField && widget.controller?.text == 'Free buffet',
      );
      await tester.ensureVisible(offerTitle);
      await tester.enterText(offerTitle, 'Rejected text');
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      gate.completeError(
        ApiException(
          statusCode: 400,
          data: {'errorCode': 'PUBLIC_TEXT_NOT_ALLOWED'},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AddVenueEventPage), findsOneWidget);
      expect(find.text(publicTextRejectionMessage), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving an event whose offer id is unknown uses the atomic PATCH, no client lookup or duplicate create',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final offers = OffersFake();
      final repo = EditedEventRepository();
      await tester.pumpWidget(
        MaterialApp(
          home: AddVenueEventPage(
            venueId: 'venue-a',
            // A refreshed detail payload: the offer is there, its id is not.
            existing: VenueUpcomingEvent(
              id: 'event-a',
              title: 'Kosu',
              startAt: DateTime(2026, 11, 1, 18),
              endAt: DateTime(2026, 11, 1, 20),
              offerType: 'BUFFET',
              offerTitle: 'Free buffet',
            ),
            repository: repo,
            partnershipRepository: PartnershipsFake(),
            offerRepository: offers,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(offers.updated, isEmpty);
      expect(offers.reads, 0);
      expect(repo.lastOffer!['type'], 'BUFFET');
      expect(offers.created, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late atomic response cannot publish changes or close the editor in a new session',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final commit = Completer<void>();
      final offers = OffersFake();
      VenueEventMutation? applied;
      await tester.pumpWidget(
        MaterialApp(
          home: AddVenueEventPage(
            venueId: 'venue-a',
            existing: VenueUpcomingEvent(
              id: 'event-a',
              title: 'Kosu',
              startAt: DateTime(2026, 11, 1, 18),
              endAt: DateTime(2026, 11, 1, 20),
              offerType: 'BUFFET',
              offerTitle: 'Free buffet',
            ),
            repository: EditedEventRepository(gate: commit),
            partnershipRepository: PartnershipsFake(),
            offerRepository: offers,
            onUpdated: (mutation) => applied = mutation,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pump();
      expect(offers.reads, 0);
      PendingPublicMediaService.instance.clear();
      commit.complete();
      await tester.pump();
      expect(applied, isNull);
      expect(offers.updated, isEmpty);
      expect(offers.created, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull);
    },
  );

  for (final choice in {
    'This event only': 'this',
    'This and following events': 'thisAndFollowing',
    'All events in series': 'all',
  }.entries) {
    testWidgets(
      'detail editor sends selected deals with ${choice.value} scope in one PATCH',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = EditedEventRepository();
        final partnerships = PartnershipsFake(available: [_partnership()]);
        final offers = OffersFake();
        await tester.pumpWidget(
          MaterialApp(
            home: VenueEventDetailPage(
              event: _event(recurring: true),
              venueId: 'venue-a',
              repository: repo,
              partnershipRepository: partnerships,
              offerRepository: offers,
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.edit_outlined));
        await tester.pumpAndSettle();
        await tester.tap(find.text(choice.key));
        await tester.pumpAndSettle();
        await _selectDeal(tester);
        await tester.tap(find.text('Save Changes'));
        await tester.pumpAndSettle();
        expect(repo.saves, 1);
        expect(repo.lastEditScope, choice.value);
        expect(repo.lastPartnershipIds, ['deal-1']);
        expect(partnerships.written, isEmpty);
        expect(offers.updated, isEmpty);
        expect(repo.detailReads, 0);
        expect(find.text('2-for-1 cocktails'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'turning the offer off sends explicit scoped removal, not an ignored toggle',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final repo = EditedEventRepository();
      final offers = OffersFake();
      VenueEventMutation? saved;
      await tester.pumpWidget(
        MaterialApp(
          home: AddVenueEventPage(
            venueId: 'venue-a',
            existing: _event(withLinks: true, recurring: true),
            editScope: 'all',
            repository: repo,
            partnershipRepository: PartnershipsFake(),
            offerRepository: offers,
            onUpdated: (result) => saved = result,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('event-offer-toggle'));
      await tester.ensureVisible(toggle);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();
      expect(repo.lastEditScope, 'all');
      expect(repo.lastClearOffer, true);
      expect(repo.lastOffer, isNull);
      expect(offers.updated, isEmpty);
      expect(saved!.event.offerId, isNull);
      expect(tester.takeException(), isNull);
    },
  );
}
