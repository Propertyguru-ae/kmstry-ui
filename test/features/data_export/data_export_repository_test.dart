import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_model.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_repository.dart';

void main() {
  group('DataExportDownload', () {
    test('accepts only a valid HTTPS signed-download contract', () {
      final model = DataExportDownload.fromJson({
        'url':
            'https://kmstry-test.fra1.digitaloceanspaces.com/export.zip?signature=secret',
        'expiresAt': '2026-08-27T12:05:00.000Z',
        'filename': 'kmstry-data-export.zip',
        'fileSizeBytes': '123',
        'checksumSha256': _checksum,
      });
      expect(model.fileSizeBytes, 123);
      expect(model.url.scheme, 'https');
    });

    test('rejects insecure URLs and malformed integrity metadata', () {
      expect(
        () => DataExportDownload.fromJson({
          'url': 'http://private.example/export.zip',
          'expiresAt': '2026-08-27T12:05:00.000Z',
          'fileSizeBytes': '123',
          'checksumSha256': _checksum,
        }),
        throwsFormatException,
      );
      expect(
        () => DataExportDownload.fromJson({
          'url': 'https://kmstry-test.fra1.digitaloceanspaces.com/export.zip',
          'expiresAt': '2026-08-27T12:05:00.000Z',
          'fileSizeBytes': '123',
          'checksumSha256': 'invalid',
        }),
        throwsFormatException,
      );
    });
  });

  group('DataExportRepository', () {
    late _FakeTransport transport;
    late DataExportRepository repository;

    setUp(() {
      transport = _FakeTransport();
      repository = DataExportRepository(
        transport: transport,
        tokenProvider: () async => 'access-token',
        timezoneProvider: () async => 'Asia/Dubai',
      );
    });

    test('creates a sorted, authenticated export request', () async {
      transport.nextResponse = _requestJson(status: 'PENDING');
      await repository.create(
        categories: {'MESSAGES', 'ACCOUNT', 'LEGAL'},
        scope: DataExportScope.personal,
        venueIds: const {},
        mediaQuality: 'NONE',
        dateFrom: DateTime.utc(2026, 1, 1),
        dateTo: DateTime.utc(2026, 8, 1),
      );

      expect(transport.lastMethod, 'POST');
      expect(transport.lastPath, '/users/me/data-exports');
      expect(transport.lastHeaders, {'Authorization': 'Bearer access-token'});
      expect(transport.lastBody, {
        'categories': ['ACCOUNT', 'LEGAL', 'MESSAGES'],
        'scope': 'PERSONAL',
        'timezone': 'Asia/Dubai',
        'format': 'JSON',
        'mediaQuality': 'NONE',
        'dateFrom': '2026-01-01T00:00:00.000Z',
        'dateTo': '2026-08-01T00:00:00.000Z',
      });
    });

    test(
      'parses paginated status records without exposing storage keys',
      () async {
        transport.nextResponse = {
          'items': [
            {
              ..._requestJson(status: 'READY'),
              'objectKey': 'must-not-be-used-by-client',
            },
          ],
          'pagination': {'page': 1},
        };
        final items = await repository.list();
        expect(items.single.status, DataExportStatus.ready);
        expect(items.single.fileSizeBytes, 123);
      },
    );

    test('uses dedicated retry, cancel and download endpoints', () async {
      transport.nextResponse = _requestJson(status: 'PENDING');
      await repository.retry('export-id');
      expect(transport.lastPath, '/users/me/data-exports/export-id/retry');

      transport.nextResponse = {};
      await repository.cancel('export-id');
      expect(transport.lastMethod, 'DELETE');
      expect(transport.lastPath, '/users/me/data-exports/export-id');

      transport.nextResponse = {
        'url':
            'https://kmstry-test.fra1.digitaloceanspaces.com/export.zip?signature=secret',
        'expiresAt': '2026-08-27T12:05:00.000Z',
        'filename': 'kmstry-data-export.zip',
        'fileSizeBytes': '123',
        'checksumSha256': _checksum,
      };
      await repository.createDownload('export-id');
      expect(transport.lastPath, '/users/me/data-exports/export-id/download');
    });
  });
}

Map<String, dynamic> _requestJson({required String status}) => {
  'id': '11111111-1111-4111-8111-111111111111',
  'status': status,
  'categories': ['ACCOUNT', 'LEGAL'],
  'requestedAt': '2026-08-27T12:00:00.000Z',
  'expiresAt': '2026-08-31T12:00:00.000Z',
  'fileSizeBytes': '123',
  'canCancel': status == 'READY',
  'canRetry': status == 'FAILED',
};

final _checksum = List.filled(64, 'a').join();

class _FakeTransport implements DataExportTransport {
  dynamic nextResponse;
  String? lastMethod;
  String? lastPath;
  Map<String, String>? lastHeaders;
  Map<String, dynamic>? lastBody;

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) async {
    lastMethod = 'DELETE';
    lastPath = path;
    lastHeaders = headers;
    return nextResponse;
  }

  @override
  Future<dynamic> get(String path, {Map<String, String>? headers}) async {
    lastMethod = 'GET';
    lastPath = path;
    lastHeaders = headers;
    return nextResponse;
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) async {
    lastMethod = 'POST';
    lastPath = path;
    lastHeaders = headers;
    lastBody = body;
    return nextResponse;
  }
}
