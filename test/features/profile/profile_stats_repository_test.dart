import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/profile/data/profile_stats_repository.dart';

class _Api extends ApiClient {
  final paths = <String>[];
  dynamic response = {'friendCount': 45, 'followedVenueCount': 7};
  @override
  Future<dynamic> get(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    paths.add(path);
    expect(headers?['Authorization'], 'Bearer test');
    return response;
  }
}

void main() {
  test(
    'loads counts without lists or pagination and does not cap at 20',
    () async {
      final api = _Api();
      final stats = await ProfileStatsRepository(
        api: api,
        tokenProvider: () async => 'test',
      ).load();
      expect(stats.friends, 45);
      expect(stats.venues, 7);
      expect(api.paths, ['/users/me/social-stats']);
    },
  );
  test('invalid/unavailable counts are not silently shown as zero', () async {
    final api = _Api()..response = {};
    await expectLater(
      ProfileStatsRepository(
        api: api,
        tokenProvider: () async => 'test',
      ).load(),
      throwsFormatException,
    );
  });
}
