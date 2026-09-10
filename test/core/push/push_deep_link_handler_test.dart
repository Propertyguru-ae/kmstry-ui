import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/push/push_deep_link_handler.dart';

void main() {
  for (final type in const ['data_export_ready', 'data_export_failed']) {
    testWidgets('$type opens Download your data', (tester) async {
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      await PushDeepLinkHandler.instance.routeFromData(navigatorKey, {
        'type': type,
        'route': 'data_export',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Download your data'), findsWidgets);
    });
  }
}
