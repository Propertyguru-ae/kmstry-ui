import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';

class _Api extends ApiClient {
  String? path;
  Map<String, dynamic>? body;
  Map<String, String>? headers;
  dynamic response = {
    'checkin_id': 'checkin-1',
    'venue_id': 'venue-1',
    'status': 'APPROVED',
    'can_join': true,
    'moderation_item_id': 'review-1',
  };
  @override
  Future<dynamic> post(
    String path, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    this.path = path;
    this.headers = headers;
    this.body = body;
    return response;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => FlutterSecureStorage.setMockInitialValues({
      'access_token': 'owner-token',
    }),
  );
  Future<CheckinActivationStatus> activate(_Api api) =>
      CheckinRepository(apiClient: api).activatePendingCheckin(
        checkinId: 'checkin-1',
        moderationItemId: 'review-1',
        latitude: 25,
        longitude: 55,
        accuracyMeters: 5,
        locationCapturedAt: DateTime.parse('2026-10-09T12:00:00+04:00'),
      );

  test(
    'sends the exact approval receipt and UTC location fix to the owner-scoped endpoint',
    () async {
      final api = _Api();
      final result = await activate(api);
      expect(api.path, '/checkins/checkin-1/activate');
      expect(api.headers?['Authorization'], 'Bearer owner-token');
      expect(api.body, {
        'moderation_item_id': 'review-1',
        'latitude': 25.0,
        'longitude': 55.0,
        'accuracy_meters': 5.0,
        'location_captured_at': '2026-10-09T08:00:00.000Z',
      });
      expect(result.state, CheckinActivationState.approved);
      expect(result.canJoin, true);
      expect(result.moderationItemId, 'review-1');
    },
  );

  test(
    'READY_TO_ACTIVATE keeps the room closed until explicitly completed',
    () {
      final result = CheckinActivationStatus.fromJson({
        'checkin_id': 'checkin-1',
        'venue_id': 'venue-1',
        'status': 'READY_TO_ACTIVATE',
        'can_join': false,
        'moderation_item_id': 'review-1',
      });
      expect(result.state, CheckinActivationState.readyToActivate);
      expect(result.canJoin, false);
      expect(result.moderationItemId, 'review-1');
    },
  );

  test('missing owner session cannot send activation', () async {
    FlutterSecureStorage.setMockInitialValues({});
    final api = _Api();
    await expectLater(activate(api), throwsStateError);
    expect(api.path, isNull);
  });

  test('a malformed activation response is not accepted', () async {
    final api = _Api()..response = 'invalid';
    await expectLater(activate(api), throwsFormatException);
  });
}
