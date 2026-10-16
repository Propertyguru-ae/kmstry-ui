import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_search_location.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class _Auth extends AuthRepository {
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => {
    'registrationName': 'Fixture Owner',
    'birthdate': '1990-01-02',
  };
}

class _Location extends VenueSearchLocationResolver {
  final Future<VenueSearchLocation?> value;
  _Location(this.value);
  @override
  Future<VenueSearchLocation?> resolve() => value;
}

class _Venues extends VenueRepository {
  final calls = <({String query, double? latitude, double? longitude})>[];
  String? resolvedPlace;
  String? savedVenue;
  Future<List<Venue>> Function(String)? search;
  @override
  Future<Map<String, dynamic>?> getClaimDraft() async => {'current_step': 1};
  @override
  Future<String> ensureVenueDbId(String placeId) async {
    resolvedPlace = placeId;
    return 'resolved-london';
  }

  @override
  Future<Map<String, dynamic>> upsertClaimDraft({
    String? venueId,
    String? ownerFullName,
    String? ownerPhone,
    String? tradeLicenceUrl,
    String? ownerVideoUrl,
    int? currentStep,
  }) async {
    savedVenue = venueId;
    return {};
  }

  @override
  Future<List<Venue>> searchVenues({
    required String query,
    double? latitude,
    double? longitude,
    int limit = 12,
  }) {
    calls.add((query: query, latitude: latitude, longitude: longitude));
    return search?.call(query) ?? Future.value([_london]);
  }
}

final _london = Venue.fromJson({
  'placeId': 'london',
  'name': 'Pizza Pilgrims Soho',
  'address': '11 Dean Street, Soho, London W1D 3RP, United Kingdom',
  'latitude': 51.5138,
  'longitude': -0.1318,
  'source': 'google',
});
const _dubai = VenueSearchLocation(25.2048, 55.2708);
final _field = find.byKey(const ValueKey('venue-search'));

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'fixture'});
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> open(
    WidgetTester tester,
    _Venues venues, {
    bool addVenue = false,
    Future<VenueSearchLocation?>? location,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: VenueContextOnboardingPage(
          fromAppShell: addVenue,
          repository: venues,
          authRepository: _Auth(),
          searchLocationResolver: _Location(location ?? Future.value(_dubai)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> type(WidgetTester tester, String query) async {
    await tester.enterText(_field, query);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  for (final addVenue in [false, true]) {
    final flow = addVenue ? 'Add Venue' : 'normal venue signup';
    testWidgets(
      '$flow sends Dubai as optional bias and shows a London branch address',
      (tester) async {
        final venues = _Venues();
        await open(tester, venues, addVenue: addVenue);
        expect(
          find.text('Add the city to find the right location.'),
          findsOneWidget,
        );
        await type(tester, 'Pizza Pilgrims London');
        expect(venues.calls.single, (
          query: 'Pizza Pilgrims London',
          latitude: 25.2048,
          longitude: 55.2708,
        ));
        expect(find.text(_london.name), findsOneWidget);
        expect(find.text(_london.address), findsOneWidget);
        expect(tester.widget<Text>(find.text(_london.address)).maxLines, 2);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text(_london.name));
        await tester.pumpAndSettle();
        expect(find.text('No venues found'), findsNothing);
        expect(venues.calls.length, 1);
        await tester.ensureVisible(find.text('Continue'));
        await tester.tap(find.text('Continue'));
        await tester.pumpAndSettle();
        expect(find.text('STEP 2 OF 4'), findsOneWidget);
        expect(venues.resolvedPlace, 'london');
        expect(venues.savedVenue, 'resolved-london');
      },
    );

    testWidgets('$flow works without location permission', (tester) async {
      final venues = _Venues();
      await open(
        tester,
        venues,
        addVenue: addVenue,
        location: Future.value(null),
      );
      await type(tester, 'Pizza Pilgrims London');
      expect(venues.calls.single, (
        query: 'Pizza Pilgrims London',
        latitude: null,
        longitude: null,
      ));
      expect(find.text(_london.address), findsOneWidget);
    });
  }

  testWidgets(
    'late GPS does not block typing and stale unbiased results cannot overwrite refresh',
    (tester) async {
      final location = Completer<VenueSearchLocation?>();
      final first = Completer<List<Venue>>();
      final second = Completer<List<Venue>>();
      final venues = _Venues();
      venues.search = (_) =>
          venues.calls.length == 1 ? first.future : second.future;
      await open(tester, venues, location: location.future);
      await type(tester, 'pizza');
      expect(venues.calls.single.latitude, isNull);
      location.complete(_dubai);
      await tester.pump();
      expect(venues.calls.last.latitude, 25.2048);
      first.complete([]);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      second.complete([_london]);
      await tester.pumpAndSettle();
      expect(find.text(_london.name), findsOneWidget);
    },
  );

  testWidgets(
    'old query response cannot stop the new query spinner or replace results',
    (tester) async {
      final old = Completer<List<Venue>>();
      final current = Completer<List<Venue>>();
      final venues = _Venues()
        ..search = (q) => q == 'pizza' ? old.future : current.future;
      await open(tester, venues);
      await type(tester, 'pizza');
      await type(tester, 'Pizza Pilgrims London');
      old.complete([]);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      current.complete([_london]);
      await tester.pumpAndSettle();
      expect(find.text(_london.name), findsOneWidget);
    },
  );

  testWidgets('provider failure is not displayed as no venues found', (
    tester,
  ) async {
    final venues = _Venues()..search = (_) async => throw StateError('offline');
    await open(tester, venues);
    await type(tester, 'pizza');
    expect(find.text('Search failed. Please try again.'), findsOneWidget);
    expect(find.text('No venues found'), findsNothing);
    venues.search = (_) async => [];
    await tester.ensureVisible(find.text('Retry search'));
    await tester.tap(find.text('Retry search'));
    await tester.pumpAndSettle();
    expect(venues.calls.length, 2);
    expect(venues.calls.last.query, 'pizza');
    expect(find.text('Search failed. Please try again.'), findsNothing);
    expect(find.text('No venues found'), findsOneWidget);
    expect(
      find.text('Try the full venue name and city, or its address.'),
      findsOneWidget,
    );
    expect(find.text("Add it manually and we'll verify it"), findsNothing);
  });

  testWidgets('clearing search invalidates an in-flight response', (
    tester,
  ) async {
    final pending = Completer<List<Venue>>();
    final venues = _Venues()..search = (_) => pending.future;
    await open(tester, venues);
    await type(tester, 'pizza');
    await type(tester, '');
    pending.complete([_london]);
    await tester.pumpAndSettle();
    expect(find.text(_london.name), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });
}
