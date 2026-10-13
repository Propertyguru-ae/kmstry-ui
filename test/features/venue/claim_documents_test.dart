import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/venue/data/claim_document_policy.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_upload_docs_page.dart';

class _ClaimApi extends ApiClient {
  final calls = <({String path, Map<String, dynamic>? body})>[];

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    calls.add((path: path, body: body));
    return {'ok': true, 'status': 'PENDING'};
  }

  @override
  Future<dynamic> put(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    calls.add((path: path, body: body));
    return {'data': <String, dynamic>{}};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-token',
    }),
  );

  test('licence is the only required document, video cannot replace it', () {
    expect(ClaimDocumentPolicy.ownershipVideoEnabled, isFalse);
    expect(ClaimDocumentPolicy.requiredDocumentCount, 1);
    expect(ClaimDocumentPolicy.hasRequiredDocuments('licence.pdf'), isTrue);
    expect(ClaimDocumentPolicy.hasRequiredDocuments(null, 'old.mp4'), isFalse);
    expect(ClaimDocumentPolicy.hasRequiredDocuments('  '), isFalse);
  });

  test('new claim sends licence but never an old restored video', () async {
    final api = _ClaimApi();
    await VenueRepository(apiClient: api).claimVenue(
      venueId: 'venue-a',
      ownerNote: 'Owner contact',
      tradeLicenceUrl: 'https://fixture.example/licence.pdf',
      ownerVideoUrl: 'https://fixture.example/old.mp4',
      hasDocuments: true,
    );
    expect(api.calls.single.path, '/venues/claim');
    expect(
      api.calls.single.body,
      containsPair('tradeLicenceUrl', 'https://fixture.example/licence.pdf'),
    );
    expect(api.calls.single.body, isNot(contains('ownerVideoUrl')));
  });

  test('pending claims submit documents without ownership video', () async {
    final api = _ClaimApi();
    await VenueRepository(apiClient: api).submitClaimDocuments(
      tradeLicenceUrl: 'https://fixture.example/licence.pdf',
      ownerVideoUrl: 'old.mp4',
    );
    expect(api.calls.single.path, '/venues/claim/documents');
    expect(api.calls.single.body, {
      'tradeLicenceUrl': 'https://fixture.example/licence.pdf',
    });
  });

  test('saving draft does not resubmit or erase an old stored video', () async {
    final api = _ClaimApi();
    await VenueRepository(apiClient: api).upsertClaimDraft(
      tradeLicenceUrl: 'https://fixture.example/licence.pdf',
      ownerVideoUrl: 'old.mp4',
      currentStep: 3,
    );
    expect(api.calls.single.path, '/venues/claim-draft');
    expect(api.calls.single.body, isNot(contains('owner_video_url')));
    expect(
      api.calls.single.body,
      containsPair('trade_licence_url', 'https://fixture.example/licence.pdf'),
    );
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'document screen hides video in $brightness theme and asks only for licence',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: const VenueUploadDocsPage(venueName: 'Test Cafe'),
          ),
        );
        expect(find.text('Trade Licence'), findsOneWidget);
        expect(find.text('Ownership Video'), findsNothing);
        expect(find.text('MP4'), findsNothing);
        await tester.ensureVisible(find.text('Submit Documents'));
        await tester.tap(find.text('Submit Documents'));
        await tester.pump();
        expect(
          find.text('Please upload your trade licence first.'),
          findsOneWidget,
        );
        expect(
          find.text('Please upload your ownership video first.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
