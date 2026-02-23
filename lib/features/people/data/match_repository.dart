import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';

class MatchRepository {
  final ApiClient _api = ApiClient();

  Future<String?> _token() => SecureStorage.getAccessToken();

  /// GET /matches — list people the current user has matched with.
  Future<List<MatchItem>> getMatches() async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.get(
      '/matches',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (data is! List) return [];
    return data
        .map((e) => MatchItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<BlockedUser>> getBlockedUsers() async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    dynamic data;
    try {
      data = await _api.get(
        '/blocks/me',
        headers: {'Authorization': 'Bearer $token'},
      );
    } catch (_) {
      data = await _api.get(
        '/blocks/me',
        headers: {'Authorization': 'Bearer $token'},
      );
    }
    final list = _extractList(data);
    return list
        .whereType<Map>()
        .map((e) => BlockedUser.fromJson(Map<String, dynamic>.from(e)))
        .where((u) => u.userId.isNotEmpty)
        .toList();
  }

  List<dynamic> _extractList(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final nested =
          data['items'] ??
          data['data'] ??
          data['blocks'] ??
          data['blocked'] ??
          data['results'];
      if (nested is List) return nested;
    }
    return const [];
  }

 Future<void> unblockUser(String userId) async {
  final token = await _token();
  if (token == null) throw Exception('Not authenticated');

  await _api.delete(
    '/blocks/$userId',
    headers: {'Authorization': 'Bearer $token'},
  );
}
}
