import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/push/push_deep_link_handler.dart';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/push/push_audience.dart';

class _Unavailable extends NotificationRepository {
  @override
  Future<ConnectionNoticeTarget?> resolveConnectionNotice(
    String id, {
    String? version,
    DateTime? seenAt,
  }) async {
    expect(id, 'notice');
    expect(version, 'old');
    return null;
  }
}

void main() {
  setUp(() {
    final claims = base64Url.encode(
      utf8.encode(jsonEncode({'sub': 'reviewer'})),
    );
    FlutterSecureStorage.setMockInitialValues({
      'access_token': 'header.$claims.signature',
      'refresh_token': 'refresh',
      'registered_push_session': 'login-one',
    });
    PushAudience.resume();
  });
  testWidgets('an old Connection made push stays on the current screen', (
    tester,
  ) async {
    final key = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        home: const Scaffold(body: Text('Home')),
      ),
    );
    await PushDeepLinkHandler.forTest(_Unavailable()).routeFromData(key, {
      'type': 'match_created',
      'recipientUserId': 'reviewer',
      'pushSessionId': 'login-one',
      'notification_id': 'notice',
      'connection_version': 'old',
    });
    await tester.pump();
    expect(find.text('This connection is no longer active.'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
  });

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
        'recipientUserId': 'reviewer',
        'pushSessionId': 'login-one',
        'route': 'data_export',
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Download your data'), findsWidgets);
    });
  }

  testWidgets('report_update opens the moderation warning details', (
    tester,
  ) async {
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: const Scaffold(body: Text('Home')),
      ),
    );

    await PushDeepLinkHandler.instance.routeFromData(navigatorKey, {
      'type': 'report_update',
      'recipientUserId': 'reviewer',
      'pushSessionId': 'login-one',
      'route': 'moderation_warning',
      'contentRemoved': 'true',
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Community Guidelines warning'), findsWidgets);
    expect(
      find.text(
        'The reported message has been removed. Your account remains active.',
      ),
      findsOneWidget,
    );
  });

  for (final scenario in [
    'logged out',
    'different user',
    'previous login',
    'missing audience',
  ]) {
    testWidgets('notification tap is ignored: $scenario', (tester) async {
      final key = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(navigatorKey: key, home: const Text('Home')),
      );
      if (scenario == 'logged out') {
        FlutterSecureStorage.setMockInitialValues({});
      }
      await PushDeepLinkHandler.instance.routeFromData(key, {
        'type': 'report_update',
        if (scenario != 'missing audience')
          'recipientUserId': scenario == 'different user'
              ? 'old-user'
              : 'reviewer',
        if (scenario != 'missing audience')
          'pushSessionId': scenario == 'previous login'
              ? 'old-login'
              : 'login-one',
      });
      await tester.pumpAndSettle();
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Community Guidelines warning'), findsNothing);
    });
  }
}
