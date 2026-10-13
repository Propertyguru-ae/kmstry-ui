import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';

class _Api extends ApiClient {
  String? path;
  Map<String, dynamic>? sentBody;
  Map<String, String>? sentHeaders;
  @override
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    this.path = path;
    sentBody = body;
    sentHeaders = headers;
    return {'success': true};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'test-viewer',
    }),
  );

  test(
    'Google photo goes to KMSTRY with the signed token and no fabricated user',
    () async {
      final api = _Api();
      await CheckinRepository(apiClient: api).reportUser(
        reason: 'INAPPROPRIATE_CONTENT',
        googlePhotoToken: 'payload.signature',
      );
      expect(api.path, '/reports/users');
      expect(api.sentHeaders?['Authorization'], 'Bearer test-viewer');
      expect(api.sentBody, {
        'reason': 'INAPPROPRIATE_CONTENT',
        'google_photo_token': 'payload.signature',
      });
    },
  );

  test(
    'owner photo keeps the exact venue and displayed image target',
    () async {
      final api = _Api();
      await CheckinRepository(apiClient: api).reportUser(
        reason: 'INAPPROPRIATE_CONTENT',
        venuePhotoId: 'venue-1',
        venuePhotoUrl: 'https://media.test/venue-photos/current.jpg',
      );
      expect(api.sentBody, {
        'reason': 'INAPPROPRIATE_CONTENT',
        'venue_photo_id': 'venue-1',
        'venue_photo_url': 'https://media.test/venue-photos/current.jpg',
      });
    },
  );
}
