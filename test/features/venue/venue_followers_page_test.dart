import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/data/venue_follower_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_followers_page.dart';

class _Followers extends VenueOwnerRepository {
  @override
  Future<List<VenueFollower>> getFollowers(
    String venueId, {
    String sort = 'latest',
  }) async => const [
    VenueFollower(userId: 'zoe', fullName: 'Zoe', username: 'zoe_test'),
    VenueFollower(userId: 'alex', fullName: 'Alex', username: 'alex_test'),
  ];
}

Future<void> _pump(
  WidgetTester tester, {
  Brightness brightness = Brightness.light,
  GlobalKey<NavigatorState>? navigatorKey,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigatorKey,
      theme: ThemeData(brightness: brightness),
      home: VenueFollowersPage(venueId: 'alpha', repository: _Followers()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
  });
  tearDown(() => PendingPublicMediaService.instance.clear());

  for (final brightness in Brightness.values) {
    testWidgets('venue followers are read-only in ${brightness.name} mode', (
      tester,
    ) async {
      final navigator = GlobalKey<NavigatorState>();
      await _pump(tester, brightness: brightness, navigatorKey: navigator);

      expect(find.text('Zoe'), findsOneWidget);
      expect(find.text('@zoe_test'), findsOneWidget);
      for (final tile in tester.widgetList<ListTile>(find.byType(ListTile))) {
        expect(tile.onTap, isNull);
        expect(tile.onLongPress, isNull);
        expect(tile.trailing, isNull);
      }
      expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

      await tester.tap(find.text('Zoe'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CircleAvatar).first);
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Zoe'));
      await tester.pumpAndSettle();

      expect(navigator.currentState!.canPop(), isFalse);
      expect(find.byType(VenueFollowersPage), findsOneWidget);
      expect(find.text('Interested'), findsNothing);
      expect(find.text('Pass'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('read-only followers keep search and sorting', (tester) async {
    await _pump(tester);
    expect(
      tester.getTopLeft(find.text('Zoe')).dy,
      lessThan(tester.getTopLeft(find.text('Alex')).dy),
    );

    await tester.enterText(find.byType(TextField), 'alex_test');
    await tester.pump();
    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('Zoe'), findsNothing);

    await tester.enterText(find.byType(TextField), 'missing');
    await tester.pump();
    expect(find.text('No followers match "missing".'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.tap(find.byTooltip('Sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Name (A–Z)'));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Alex')).dy,
      lessThan(tester.getTopLeft(find.text('Zoe')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}
