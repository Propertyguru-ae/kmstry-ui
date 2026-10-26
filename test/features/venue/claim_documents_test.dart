import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/venue/data/claim_document_policy.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_upload_docs_page.dart';

class _ClaimApi extends ApiClient {
  final calls = <({String path, Map<String, dynamic>? body})>[];
  Map<String, dynamic>? draft = {
    'venue_id': 'venue-a',
    'owner_full_name': 'Registered Owner',
    'owner_phone': '+971501234567',
  };
  bool failRead = false;
  bool failSubmit = false;
  int deleted = 0;

  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (failRead) throw ApiException(statusCode: 503, data: {});
    return {'success': true, 'data': draft};
  }

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) async {
    deleted++;
    return {'success': true};
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    calls.add((path: path, body: body));
    if (failSubmit) throw ApiException(statusCode: 503, data: {});
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

  test(
    'client cannot submit a documentless claim even when hasDocuments is true',
    () async {
      final api = _ClaimApi();
      await expectLater(
        VenueRepository(apiClient: api).claimVenue(
          venueId: 'venue-a',
          ownerNote: 'Private contact',
          hasDocuments: true,
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.calls, isEmpty);
    },
  );

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

  test(
    'saved registration submits the selected venue with its stored contact and uploaded licence',
    () async {
      final api = _ClaimApi();
      await VenueRepository(apiClient: api).submitRegistrationDocuments(
        venueId: 'venue-a',
        tradeLicenceUrl: 'https://fixture.example/licence.pdf',
      );
      expect(api.calls.single.path, '/venues/claim');
      expect(api.calls.single.body, containsPair('venueId', 'venue-a'));
      expect(
        api.calls.single.body,
        containsPair('ownerFullName', 'Registered Owner'),
      );
      expect(
        api.calls.single.body,
        containsPair('tradeLicenceUrl', 'https://fixture.example/licence.pdf'),
      );
      expect(api.deleted, 1);
    },
  );

  test(
    'draft read failure is not treated as an empty or new registration',
    () async {
      final api = _ClaimApi()..failRead = true;
      final repo = VenueRepository(apiClient: api);
      await expectLater(repo.getClaimDraft(), throwsA(isA<ApiException>()));
      await expectLater(
        repo.submitRegistrationDocuments(
          venueId: 'venue-a',
          tradeLicenceUrl: 'https://fixture.example/licence.pdf',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.calls, isEmpty);
      expect(api.deleted, 0);
    },
  );

  test(
    'another venue draft cannot be submitted from the open document page',
    () async {
      final api = _ClaimApi();
      await expectLater(
        VenueRepository(apiClient: api).submitRegistrationDocuments(
          venueId: 'venue-b',
          tradeLicenceUrl: 'https://fixture.example/licence.pdf',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.calls, isEmpty);
      expect(api.deleted, 0);
    },
  );

  test(
    'failed claim submission keeps the saved registration for retry',
    () async {
      final api = _ClaimApi()..failSubmit = true;
      await expectLater(
        VenueRepository(apiClient: api).submitRegistrationDocuments(
          venueId: 'venue-a',
          tradeLicenceUrl: 'https://fixture.example/licence.pdf',
        ),
        throwsA(isA<ApiException>()),
      );
      expect(api.deleted, 0);
    },
  );

  test(
    'existing pending claim document submission includes its selected venue',
    () async {
      final api = _ClaimApi();
      await VenueRepository(apiClient: api).submitClaimDocuments(
        venueId: 'venue-b',
        tradeLicenceUrl: 'https://fixture.example/licence.pdf',
      );
      expect(api.calls.single.path, '/venues/claim/documents');
      expect(api.calls.single.body, containsPair('venueId', 'venue-b'));
      expect(api.deleted, 0);
    },
  );

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
