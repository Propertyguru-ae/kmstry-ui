import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
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
    return (data as List)
        .map((e) => MatchItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
