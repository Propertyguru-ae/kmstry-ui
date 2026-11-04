import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/followed_venues_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_checkin_stats_row.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Venues extends VenueContextRepository {
  _Venues(this.read);
  Future<List<Venue>> Function() read;
  final calls = <String>[];
  bool fail = false;
  Completer<void>? pending;

  @override
  Future<List<Venue>> getFollowedVenues() => read();

  Future<Map<String, dynamic>> _record(String call) async {
    calls.add(call);
    if (pending != null) await pending!.future;
    if (fail) throw Exception('offline');
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> followVenue(String venueId) =>
      _record('follow $venueId');

  @override
  Future<Map<String, dynamic>> unfollowVenue(String venueId) =>
      _record('unfollow $venueId');
}

Venue _venue() => Venue.fromJson({
  'id': 'venue-1',
  'name': 'Test Cafe Alpha',
  'isInDb': true,
  'latitude': 25.2,
  'longitude': 55.3,
});

final _cta = find.widgetWithText(PrimaryButton, 'Discover on map');

/// Sayfayı gerçekteki gibi ayrı bir route olarak açar; kapanış sonucunu döndürür.
Future<Completer<bool?>> _open(
  WidgetTester tester,
  _Venues venues, {
  ThemeData? theme,
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final closed = Completer<bool?>();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              closed.complete(
                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => FollowedVenuesPage(repository: venues),
                  ),
                ),
              );
            },
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return closed;
}

void _expectNoListControls() {
  expect(find.byType(TextField), findsNothing);
  expect(find.textContaining('Sort by'), findsNothing);
  expect(find.text('0 venues'), findsNothing);
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
  });

  for (final dark in [false, true]) {
    testWidgets('no followed venues offers only the map CTA; dark=$dark', (
      tester,
    ) async {
      final closed = await _open(
        tester,
        _Venues(() async => const []),
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      expect(find.text('No followed venues yet'), findsOneWidget);
      expect(
        find.text('Find venues on the map and follow them to see them here.'),
        findsOneWidget,
      );
      expect(_cta, findsOneWidget);
      _expectNoListControls();
      expect(tester.takeException(), isNull);

      await tester.tap(_cta);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FollowedVenuesPage), findsNothing);
      expect(await closed.future, isTrue);
    });
  }

  testWidgets('going back from the empty page does not ask for the map', (
    tester,
  ) async {
    final closed = await _open(tester, _Venues(() async => const []));
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(await closed.future, isNull);
  });

  testWidgets('CTA stays reachable on a small screen with large text', (
    tester,
  ) async {
    await _open(
      tester,
      _Venues(() async => const []),
      size: const Size(320, 480),
      textScale: 1.6,
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(_cta);
    await tester.pump();
    await tester.tap(_cta);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(FollowedVenuesPage), findsNothing);
  });

  testWidgets('first load claims nothing about the list', (tester) async {
    final pending = Completer<List<Venue>>();
    await _open(tester, _Venues(() => pending.future));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(_cta, findsNothing);
    expect(find.text('No followed venues yet'), findsNothing);
    _expectNoListControls();
    pending.complete(const []);
    await tester.pump();
    await tester.pump();
    expect(_cta, findsOneWidget);
  });

  testWidgets('a failed load is not shown as an empty list', (tester) async {
    await _open(tester, _Venues(() async => throw StateError('unavailable')));
    expect(find.text('Followed venues could not be loaded.'), findsOneWidget);
    expect(find.text('No followed venues yet'), findsNothing);
    expect(_cta, findsNothing);
    _expectNoListControls();
  });

  testWidgets('followed venues keep search and sort, without the CTA', (
    tester,
  ) async {
    await _open(tester, _Venues(() async => [_venue()]));
    expect(find.text('Test Cafe Alpha'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Sort by'), findsOneWidget);
    expect(find.text('1 venue'), findsOneWidget);
    expect(_cta, findsNothing);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await tester.pump();
    expect(find.text('No venues found'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(_cta, findsNothing);
  });

  group('Following button', () {
    final following = find.text('Following');
    final follow = find.text('Follow');

    for (final dark in [false, true]) {
      testWidgets('unfollows in place and refollows; dark=$dark', (
        tester,
      ) async {
        final venues = _Venues(() async => [_venue()]);
        await _open(
          tester,
          venues,
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        final before = tester.getTopLeft(find.text('Test Cafe Alpha'));

        await tester.tap(following);
        await tester.pump();
        expect(venues.calls, ['unfollow venue-1']);
        expect(following, findsNothing);
        expect(follow, findsOneWidget);
        // The card stays put and the tap never reaches it.
        expect(find.text('Test Cafe Alpha'), findsOneWidget);
        expect(tester.getTopLeft(find.text('Test Cafe Alpha')), before);
        expect(find.text('1 venue'), findsOneWidget);
        expect(find.byType(VenueDetailPage), findsNothing);

        await tester.tap(follow);
        await tester.pump();
        expect(venues.calls, ['unfollow venue-1', 'follow venue-1']);
        expect(following, findsOneWidget);
        expect(find.byType(VenueDetailPage), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('the card itself still opens the venue', (tester) async {
      await _open(tester, _Venues(() async => [_venue()]));
      await tester.tap(find.text('Test Cafe Alpha'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(VenueDetailPage), findsOneWidget);
      // The page's deferred loads are mounted-guarded timers.
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('a failed unfollow restores the button and says so', (
      tester,
    ) async {
      final venues = _Venues(() async => [_venue()])..fail = true;
      await _open(tester, venues);
      await tester.tap(following);
      await tester.pump();
      await tester.pump();
      expect(following, findsOneWidget);
      expect(follow, findsNothing);
      expect(
        find.widgetWithText(BrandedNoticeCard, 'Could not unfollow venue'),
        findsOneWidget,
      );
    });

    testWidgets('a failed refollow keeps Follow and says so', (tester) async {
      final venues = _Venues(() async => [_venue()]);
      await _open(tester, venues);
      await tester.tap(following);
      await tester.pump();
      venues.fail = true;
      await tester.tap(follow);
      await tester.pump();
      await tester.pump();
      expect(follow, findsOneWidget);
      expect(
        find.widgetWithText(BrandedNoticeCard, 'Could not follow venue'),
        findsOneWidget,
      );
    });

    testWidgets('a tap during a request sends nothing and opens nothing', (
      tester,
    ) async {
      final venues = _Venues(() async => [_venue()])
        ..pending = Completer<void>();
      await _open(tester, venues);
      await tester.tap(following);
      await tester.pump();
      await tester.tap(follow);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(venues.calls, ['unfollow venue-1']);
      expect(find.byType(VenueDetailPage), findsNothing);
      venues.pending!.complete();
      await tester.pump();
      expect(follow, findsOneWidget);
    });

    testWidgets('refreshing drops an unfollowed venue; the last one shows the '
        'CTA', (tester) async {
      final venues = _Venues(() async => [_venue()]);
      await _open(tester, venues);
      await tester.tap(following);
      await tester.pump();
      venues.read = () async => const [];
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Test Cafe Alpha'), findsNothing);
      expect(find.text('No followed venues yet'), findsOneWidget);
      expect(_cta, findsOneWidget);
    });

    testWidgets('a venue followed again elsewhere reloads as Following', (
      tester,
    ) async {
      final venues = _Venues(() async => [_venue()]);
      await _open(tester, venues);
      await tester.tap(following);
      await tester.pump();
      await tester.fling(find.byType(ListView), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Test Cafe Alpha'), findsOneWidget);
      expect(following, findsOneWidget);
    });

    testWidgets('a long name yields to the button on a small screen', (
      tester,
    ) async {
      final longName = Venue.fromJson({
        'id': 'venue-2',
        'name': 'A very long venue name that cannot fit next to the button',
        'isInDb': true,
        'latitude': 25.2,
        'longitude': 55.3,
      });
      await _open(
        tester,
        _Venues(() async => [longName]),
        // The wide test font makes the existing Sort row overflow beyond this.
        size: const Size(320, 640),
        textScale: 1.2,
      );
      expect(tester.takeException(), isNull);
      final button = find
          .ancestor(of: following, matching: find.byType(InkWell))
          .first;
      expect(tester.getSize(button).width, lessThanOrEqualTo(136));
      expect(tester.getRect(button).right, lessThanOrEqualTo(320));
      expect(tester.widget<Text>(following).overflow, TextOverflow.ellipsis);
    });

    testWidgets('other venue lists show no button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [VenueListItem(venue: _venue())]),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Test Cafe Alpha'), findsOneWidget);
      expect(following, findsNothing);
      expect(follow, findsNothing);
    });
  });

  group('Sort by', () {
    Venue named(String id, String name) => Venue.fromJson({
      'id': id,
      'name': name,
      'isInDb': true,
      'latitude': 25.2,
      'longitude': 55.3,
    });
    _Venues twoVenues() => _Venues(
      () async => [named('new', 'Newest Cafe'), named('old', 'Oldest Cafe')],
    );

    Future<void> openSort(WidgetTester tester) async {
      await tester.tap(find.byTooltip('Sort'));
      await tester.pumpAndSettle();
    }

    Finder checkIn(String label) => find.descendant(
      of: find.widgetWithText(AppSheetRow, label),
      matching: find.byIcon(Icons.check_rounded),
    );

    for (final dark in [false, true]) {
      testWidgets('uses the standard sheet and marks the choice; dark=$dark', (
        tester,
      ) async {
        await _open(
          tester,
          twoVenues(),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        await openSort(tester);
        expect(find.text('Sort by'), findsOneWidget);
        expect(find.byType(ListTile), findsNothing);
        expect(
          tester.widget<BottomSheet>(find.byType(BottomSheet)).backgroundColor,
          dark ? const Color(0xFF121A2B) : Colors.white,
        );
        expect(
          [
            for (final row in tester.widgetList<AppSheetRow>(
              find.byType(AppSheetRow),
            ))
              row.title,
          ],
          ['Latest', 'Earliest'],
        );
        expect(find.text('Newest follows first'), findsOneWidget);
        expect(find.text('Oldest follows first'), findsOneWidget);
        expect(checkIn('Latest'), findsOneWidget);
        expect(checkIn('Earliest'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('choosing reorders the list and moves the tick', (
      tester,
    ) async {
      await _open(tester, twoVenues());
      expect(
        tester.getTopLeft(find.text('Newest Cafe')).dy,
        lessThan(tester.getTopLeft(find.text('Oldest Cafe')).dy),
      );
      await openSort(tester);
      await tester.tap(find.text('Earliest'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Earliest'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Oldest Cafe')).dy,
        lessThan(tester.getTopLeft(find.text('Newest Cafe')).dy),
      );
      await openSort(tester);
      expect(checkIn('Earliest'), findsOneWidget);
      expect(checkIn('Latest'), findsNothing);
    });

    testWidgets('closing without choosing keeps the order', (tester) async {
      await _open(tester, twoVenues());
      await openSort(tester);
      await tester.tapAt(const Offset(195, 40));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Latest'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('Newest Cafe')).dy,
        lessThan(tester.getTopLeft(find.text('Oldest Cafe')).dy),
      );
    });
  });

  group('card text', () {
    const prompt = 'Want to be the first to check in?';
    const description = 'Specialty coffee and live music on weekends.';
    Venue described([String? text = description]) => Venue.fromJson({
      'id': 'venue-1',
      'name': 'Test Cafe Alpha',
      'isInDb': true,
      'latitude': 25.2,
      'longitude': 55.3,
      'description': text,
    });

    for (final dark in [false, true]) {
      testWidgets('the description replaces the check-in prompt; dark=$dark', (
        tester,
      ) async {
        await _open(
          tester,
          _Venues(() async => [described()]),
          theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
        );
        expect(find.text(prompt), findsNothing);
        expect(find.text(description), findsOneWidget);
        expect(find.text('Discover Test Cafe Alpha'), findsNothing);
        expect(tester.takeException(), isNull);
      });
    }

    for (final text in [null, '   ']) {
      testWidgets('no description leaves nothing behind; text=$text', (
        tester,
      ) async {
        await _open(tester, _Venues(() async => [described(text)]));
        expect(find.text(prompt), findsNothing);
        expect(find.byType(VenueCheckinStatsRow), findsNothing);
        expect(find.text('Test Cafe Alpha'), findsOneWidget);
      });
    }

    testWidgets('a long description stays within two lines', (tester) async {
      final long = 'Long description ' * 30;
      await _open(tester, _Venues(() async => [described(long)]));
      final text = tester.widget<Text>(find.textContaining('Long description'));
      expect(text.maxLines, 2);
      expect(text.overflow, TextOverflow.ellipsis);
      expect(tester.takeException(), isNull);
    });

    testWidgets('real check-in counts still show', (tester) async {
      final busy = Venue.fromJson({
        'id': 'venue-1',
        'name': 'Test Cafe Alpha',
        'isInDb': true,
        'latitude': 25.2,
        'longitude': 55.3,
        'checkinCountActive': 3,
        'description': description,
      });
      await _open(tester, _Venues(() async => [busy]));
      expect(find.text('3'), findsOneWidget);
      expect(find.text(prompt), findsNothing);
      expect(find.text(description), findsOneWidget);
    });

    testWidgets('other venue lists keep the prompt and the Discover box', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(children: [VenueListItem(venue: described())]),
          ),
        ),
      );
      await tester.pump();
      expect(find.text(prompt), findsOneWidget);
      expect(find.text('Discover Test Cafe Alpha'), findsOneWidget);
      expect(find.text(description), findsOneWidget);
    });
  });
}
