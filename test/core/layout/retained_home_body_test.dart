import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/layout/retained_home_body.dart';

class _Home extends StatefulWidget {
  const _Home({required this.onInit, this.label = 'Home'});
  final VoidCallback onInit;
  final String label;
  @override
  State<_Home> createState() => _HomeState();
}

class _HomeState extends State<_Home> {
  int count = 0;
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => count++),
    child: Text('${widget.label} $count'),
  );
}

void main() {
  testWidgets(
    'venue Home/Profile survive Guests and Manage; venue/login changes start lazily',
    (tester) async {
      var home = 0;
      var profile = 0;
      Widget shell(String tab, String venue, int session) => MaterialApp(
        home: RetainedHomeBody(
          key: ValueKey(('venue', venue, session)),
          isHome: tab == 'home',
          isProfile: tab == 'profile',
          home: _Home(onInit: () => home++),
          profile: _Home(label: 'Profile', onInit: () => profile++),
          destination: Text(tab),
        ),
      );
      await tester.pumpWidget(shell('home', 'a', 1));
      await tester.pumpWidget(shell('profile', 'a', 1));
      await tester.tap(find.text('Profile 0'));
      await tester.pump();
      await tester.pumpWidget(shell('guests', 'a', 1));
      expect(find.text('guests'), findsOneWidget);
      await tester.pumpWidget(shell('manage', 'a', 1));
      await tester.pumpWidget(shell('profile', 'a', 1));
      expect(find.text('Profile 1'), findsOneWidget);
      expect(home, 1);
      expect(profile, 1);
      await tester.pumpWidget(shell('profile', 'b', 1));
      expect(find.text('Profile 0'), findsOneWidget);
      expect(home, 1);
      expect(profile, 2);
      await tester.pumpWidget(shell('home', 'b', 2));
      expect(home, 2);
      expect(profile, 2);
      expect(find.text('Profile 0'), findsNothing);
    },
  );

  testWidgets(
    'only the visible retained page has enabled tickers; destinations are disposed on tab exit',
    (tester) async {
      Widget shell(String tab) => MaterialApp(
        home: RetainedHomeBody(
          isHome: tab == 'home',
          isProfile: tab == 'profile',
          home: const Text('Home'),
          profile: const Text('Profile'),
          destination: const Text('Guests'),
        ),
      );
      await tester.pumpWidget(shell('home'));
      await tester.pumpWidget(shell('profile'));
      expect(
        TickerMode.of(tester.element(find.text('Home', skipOffstage: false))),
        false,
      );
      expect(TickerMode.of(tester.element(find.text('Profile'))), true);
      await tester.pumpWidget(shell('guests'));
      expect(
        TickerMode.of(
          tester.element(find.text('Profile', skipOffstage: false)),
        ),
        false,
      );
      await tester.pumpWidget(shell('home'));
      expect(find.text('Guests', skipOffstage: false), findsNothing);
    },
  );
  testWidgets('Profile is lazy, retained with Home, and reset with account', (
    tester,
  ) async {
    var homeLoads = 0;
    var profileLoads = 0;
    Widget shell(String tab, {String account = 'one'}) => MaterialApp(
      home: RetainedHomeBody(
        key: ValueKey(account),
        isHome: tab == 'home',
        isProfile: tab == 'profile',
        home: _Home(onInit: () => homeLoads++),
        profile: _Home(label: 'Profile', onInit: () => profileLoads++),
        destination: const Text('Messages'),
      ),
    );
    await tester.pumpWidget(shell('home'));
    expect(profileLoads, 0);
    await tester.pumpWidget(shell('profile'));
    await tester.tap(find.text('Profile 0'));
    await tester.pump();
    await tester.pumpWidget(shell('home'));
    expect(find.text('Profile 1'), findsNothing);
    await tester.pumpWidget(shell('messages'));
    expect(find.text('Messages'), findsOneWidget);
    await tester.pumpWidget(shell('profile'));
    expect(find.text('Profile 1'), findsOneWidget);
    expect(profileLoads, 1);
    expect(homeLoads, 1);
    await tester.pumpWidget(shell('profile', account: 'two'));
    expect(find.text('Profile 0'), findsOneWidget);
    expect(profileLoads, 2);
  });

  testWidgets(
    'Home loads lazily, survives tab changes, and resets with context',
    (tester) async {
      var loads = 0;
      Widget shell(bool home, {String account = 'personal'}) => MaterialApp(
        home: RetainedHomeBody(
          key: ValueKey(account),
          isHome: home,
          home: _Home(onInit: () => loads++),
          destination: const Text('Messages'),
        ),
      );
      await tester.pumpWidget(shell(false));
      expect(loads, 0);
      await tester.pumpWidget(shell(true));
      await tester.tap(find.text('Home 0'));
      await tester.pump();
      await tester.pumpWidget(shell(false));
      expect(find.text('Home 1'), findsNothing);
      expect(find.text('Messages'), findsOneWidget);
      await tester.pumpWidget(shell(true));
      expect(find.text('Home 1'), findsOneWidget);
      expect(loads, 1);
      await tester.pumpWidget(shell(true, account: 'different-account'));
      expect(find.text('Home 0'), findsOneWidget);
      expect(loads, 2);
    },
  );
}
