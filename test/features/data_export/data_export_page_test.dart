import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_model.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_reauthentication.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_repository.dart';
import 'package:kmstry_frontend/features/data_export/presentation/data_export_page.dart';

void main() {
  testWidgets('keeps account/legal mandatory and location off by default', (
    tester,
  ) async {
    final repository = _PageRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DataExportPage(
          repository: repository,
          reauthentication: _NoopReauthentication(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(_checkbox(tester, 'Account and profile').value, isTrue);
    expect(_checkbox(tester, 'Account and profile').onChanged, isNull);
    expect(_checkbox(tester, 'Legal consents').value, isTrue);
    expect(_checkbox(tester, 'Legal consents').onChanged, isNull);
    expect(_checkbox(tester, 'Precise location history').value, isFalse);
    expect(find.text('Low quality'), findsNothing);
    expect(find.text('Medium quality'), findsNothing);
  });

  testWidgets('submits explicitly selected categories', (tester) async {
    final repository = _PageRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: DataExportPage(
          repository: repository,
          reauthentication: _NoopReauthentication(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final messagesTile = find.widgetWithText(CheckboxListTile, 'Messages');
    await tester.ensureVisible(messagesTile);
    await tester.pumpAndSettle();
    await tester.tap(messagesTile);
    await _scrollTo(tester, find.text('Create export'));
    await tester.tap(find.text('Create export'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(repository.createdCategories, {'ACCOUNT', 'LEGAL', 'MESSAGES'});
    expect(repository.createdMediaQuality, 'NONE');
    expect(find.text('Export added to queue'), findsNothing);
    await _scrollTo(tester, find.text('Your exports'));
    await tester.pump();
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('Export queued'), findsWidgets);
  });

  testWidgets('shows separate download and share actions for ready exports', (
    tester,
  ) async {
    final repository = _PageRepository()
      ..requests = [
        DataExportRequestModel.fromJson({
          'id': '22222222-2222-4222-8222-222222222222',
          'status': 'READY',
          'categories': ['ACCOUNT', 'LEGAL'],
          'scope': 'PERSONAL',
          'venueIds': <String>[],
          'requestedAt': '2026-08-31T12:00:00.000Z',
          'expiresAt': '2026-09-04T12:00:00.000Z',
          'fileSizeBytes': '1024',
          'canCancel': true,
          'canRetry': false,
        }),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: DataExportPage(
          repository: repository,
          reauthentication: _NoopReauthentication(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byTooltip('Download'));

    expect(find.byTooltip('Download'), findsOneWidget);
    expect(find.byTooltip('Share'), findsOneWidget);
    expect(find.text('Download & share'), findsNothing);
  });

  testWidgets('requires identity verification before every download', (
    tester,
  ) async {
    final repository = _PageRepository()
      ..requests = [
        DataExportRequestModel.fromJson({
          'id': '22222222-2222-4222-8222-222222222222',
          'status': 'READY',
          'categories': ['ACCOUNT', 'LEGAL'],
          'scope': 'PERSONAL',
          'venueIds': <String>[],
          'requestedAt': '2026-08-31T12:00:00.000Z',
          'expiresAt': '2026-09-04T12:00:00.000Z',
          'fileSizeBytes': '1024',
          'canCancel': true,
          'canRetry': false,
        }),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: DataExportPage(
          repository: repository,
          reauthentication: _NoopReauthentication(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await _scrollTo(tester, find.byTooltip('Download'));
    await tester.tap(find.byTooltip('Download'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Verify it’s you'), findsOneWidget);
  });

  testWidgets('shows a friendly wait message when create is rate limited', (
    tester,
  ) async {
    final repository = _PageRepository()
      ..createError = ApiException(
        statusCode: 429,
        data: const {'message': 'Too Many Requests'},
      );
    await tester.pumpWidget(
      MaterialApp(
        home: DataExportPage(
          repository: repository,
          reauthentication: _NoopReauthentication(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _scrollTo(tester, find.text('Create export'));
    await tester.tap(find.text('Create export'));
    await tester.pump();

    expect(find.text('Please wait a moment'), findsOneWidget);
    expect(
      find.text(
        'Too many requests were made in a short time. Please wait a moment, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Something went wrong'), findsNothing);
    expect(find.text('Too Many Requests'), findsNothing);
  });
}

CheckboxListTile _checkbox(WidgetTester tester, String title) {
  return tester.widget<CheckboxListTile>(
    find.widgetWithText(CheckboxListTile, title),
  );
}

Future<void> _scrollTo(WidgetTester tester, Finder target) async {
  await tester.dragUntilVisible(
    target,
    find.byType(ListView),
    const Offset(0, -450),
  );
  await tester.pumpAndSettle();
}

class _PageRepository extends DataExportRepository {
  Set<String>? createdCategories;
  String? createdMediaQuality;
  List<DataExportRequestModel> requests = const [];
  Object? createError;

  @override
  Future<List<DataExportRequestModel>> list() async => requests;

  @override
  Future<DataExportCapabilities> capabilities() async =>
      const DataExportCapabilities(
        hasPersonalProfile: true,
        hasVenueProfile: false,
        availableScopes: [DataExportScope.personal],
        venues: [],
        requiresScopeSelection: false,
        requiresVenueSelection: false,
      );

  @override
  Future<DataExportRequestModel> create({
    required Set<String> categories,
    required DataExportScope scope,
    required Set<String> venueIds,
    required String mediaQuality,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    if (createError case final error?) throw error;
    createdCategories = Set.of(categories);
    createdMediaQuality = mediaQuality;
    return DataExportRequestModel.fromJson({
      'id': '11111111-1111-4111-8111-111111111111',
      'status': 'PENDING',
      'categories': categories.toList(),
      'scope': scope.apiValue,
      'venueIds': venueIds.toList(),
      'requestedAt': '2026-08-27T12:00:00.000Z',
      'canCancel': true,
      'canRetry': false,
    });
  }
}

class _NoopReauthentication extends DataExportReauthentication {
  @override
  Future<void> withApple() async {}

  @override
  Future<void> withGoogle() async {}

  @override
  Future<void> withPassword({
    required String email,
    required String password,
  }) async {}
}
