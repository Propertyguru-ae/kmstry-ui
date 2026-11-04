import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/child_safety_report.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_ui.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

class _ReportApi extends ApiClient {
  final requests = <String>[];
  Map<String, dynamic>? reportBody;

  @override
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    requests.add(path);
    if (path == '/reports/users') reportBody = body;
    return {'success': true};
  }
}

const _hint = 'Help us understand what happened';

Future<void> _openOther(
  WidgetTester tester,
  _ReportApi api, {
  ThemeData? theme,
  String? messageId,
  Size size = const Size(393, 852),
}) async {
  await _openSheet(tester, api, theme: theme, messageId: messageId, size: size);
  await _selectReason(tester, 'Other');
}

Future<void> _openSheet(
  WidgetTester tester,
  _ReportApi api, {
  ThemeData? theme,
  String? messageId,
  Size size = const Size(393, 852),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.darkTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showReportUserSheet(
              context,
              repository: CheckinRepository(apiClient: api),
              targetUserId: 'target',
              messageId: messageId,
            ),
            child: const Text('Open report'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open report'));
  await tester.pumpAndSettle();
}

Future<void> _selectReason(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    find.text(label),
    100,
    // The text field has its own Scrollable; the list's comes first.
    scrollable: find
        .descendant(
          of: find.byType(ListView),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.ensureVisible(find.text(label));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

VoidCallback? _submit(WidgetTester tester) => tester
    .widget<ReportSubmitButton>(find.byType(ReportSubmitButton))
    .onPressed;

void main() {
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-token',
    }),
  );

  for (final dark in [false, true]) {
    testWidgets('Other asks for the reporter\'s words and sends them; '
        'dark=$dark', (tester) async {
      final api = _ReportApi();
      await _openOther(
        tester,
        api,
        theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
      );
      expect(find.text(_hint), findsOneWidget);
      expect(find.text('0/150'), findsOneWidget);
      expect(_submit(tester), isNull);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();
      expect(_submit(tester), isNull);

      await tester.enterText(find.byType(TextField), '  Keeps following me  ');
      await tester.pump();
      expect(_submit(tester), isNotNull);

      await tester.tap(find.byType(ReportSubmitButton));
      await tester.pumpAndSettle();
      expect(api.reportBody!['reason'], 'OTHER');
      expect(api.reportBody!['details'], 'Keeps following me');
      expect(api.requests, ['/reports/users', '/blocks']);
      expect(find.text('Thanks for your report'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Other on selected content reports without blocking', (
    tester,
  ) async {
    final api = _ReportApi();
    await _openOther(tester, api, messageId: 'message-1');
    await tester.enterText(find.byType(TextField), 'Something else');
    await tester.pump();
    await tester.tap(find.byType(ReportSubmitButton));
    await tester.pumpAndSettle();
    expect(api.reportBody!['details'], 'Something else');
    expect(api.requests, ['/reports/users']);
  });

  for (final (label, reason) in [
    ('Fake profile', 'FAKE_PROFILE'),
    ('Underage account', 'UNDERAGE_ACCOUNT'),
  ]) {
    testWidgets('account reports can say $label', (tester) async {
      final api = _ReportApi();
      await _openSheet(tester, api);
      await _selectReason(tester, label);
      await tester.tap(find.byType(ReportSubmitButton));
      await tester.pumpAndSettle();
      expect(api.reportBody!['reason'], reason);
      expect(api.reportBody!['details'], label);
      expect(api.requests, ['/reports/users', '/blocks']);
    });
  }

  testWidgets('content reports leave out the account-only reasons', (
    tester,
  ) async {
    await _openSheet(tester, _ReportApi(), messageId: 'message-1');
    expect(find.text(childSafetyReportLabel), findsOneWidget);
    expect(find.text('Fake profile'), findsNothing);
    expect(find.text('Underage account'), findsNothing);
  });

  testWidgets('Other stops at the 150 characters the backend accepts', (
    tester,
  ) async {
    final api = _ReportApi();
    await _openOther(tester, api);
    await tester.enterText(find.byType(TextField), 'a' * 200);
    await tester.pump();
    expect(find.text('150/150'), findsOneWidget);
    await tester.tap(find.byType(ReportSubmitButton));
    await tester.pumpAndSettle();
    expect(api.reportBody!['details'], 'a' * 150);
  });

  testWidgets('choosing another reason hides the text and keeps its label', (
    tester,
  ) async {
    final api = _ReportApi();
    await _openOther(tester, api);
    await tester.enterText(find.byType(TextField), 'Typed first');
    await tester.pump();
    await _selectReason(tester, 'Spam');
    expect(find.text(_hint), findsNothing);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.byType(ReportSubmitButton));
    await tester.pumpAndSettle();
    expect(api.reportBody!['reason'], 'SPAM_SCAM');
    expect(api.reportBody!['details'], 'Spam');
  });

  testWidgets('with the keyboard open on a small phone it still fits', (
    tester,
  ) async {
    final api = _ReportApi();
    await _openOther(tester, api, size: const Size(320, 568));
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(TextField).hitTestable(), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Short note');
    await tester.pump();
    final submit = tester.getRect(find.byType(ReportSubmitButton));
    expect(submit.bottom, lessThanOrEqualTo(568 - 260));
    expect(_submit(tester), isNotNull);
    expect(find.byType(ReportSubmitButton).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
