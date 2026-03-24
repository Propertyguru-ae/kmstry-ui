import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/username_search_item_model.dart';

class MatchListResult {
  final List<MatchItem> items;
  final String? nextCursor;
  final bool hasMore;

  const MatchListResult({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });
}

class MatchRepository {
  final ApiClient _api = ApiClient();

  Future<String?> _token() => SecureStorage.getAccessToken();

  /// GET /matches — list people the current user has matched with.
  Future<List<MatchItem>> getMatches() async {
    final result = await getMatchesPage();
    return result.items;
  }

  /// GET /matches with optional query + keyset pagination.
  Future<MatchListResult> getMatchesPage({
    String? query,
    int limit = 20,
    String? cursor,
  }) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final params = <String>[];
    final trimmedQuery = query?.trim() ?? '';
    if (trimmedQuery.isNotEmpty) {
      params.add('query=${Uri.encodeQueryComponent(trimmedQuery)}');
    }
    if (limit > 0) {
      params.add('limit=$limit');
    }
    if (cursor != null && cursor.trim().isNotEmpty) {
      params.add('cursor=${Uri.encodeQueryComponent(cursor.trim())}');
    }

    final path = params.isEmpty ? '/matches' : '/matches?${params.join('&')}';
    final data = await _api.get(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );

    return _parseMatchListResult(data);
  }

  MatchListResult _parseMatchListResult(dynamic data) {
    if (data is List) {
      final items = data
          .whereType<Map>()
          .map((e) => MatchItem.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      return MatchListResult(
        items: items,
        nextCursor: null,
        hasMore: false,
      );
    }

    if (data is Map<String, dynamic>) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? Map<String, dynamic>.from(data['data'] as Map)
          : data;
      final rawItems = payload['items'];
      final items = rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((e) => MatchItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
          : const <MatchItem>[];
      final rawCursor = payload['nextCursor'] ?? payload['next_cursor'];
      final nextCursor = rawCursor?.toString();
      final rawHasMore = payload['hasMore'] ?? payload['has_more'];
      final hasMore = rawHasMore is bool ? rawHasMore : nextCursor != null;
      return MatchListResult(
        items: items,
        nextCursor: nextCursor,
        hasMore: hasMore,
      );
    }

    return const MatchListResult(items: [], nextCursor: null, hasMore: false);
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

  Future<List<UsernameSearchItem>> findByUsername(String query) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    final encoded = Uri.encodeQueryComponent(trimmed);
    final data = await _api.get(
      '/users/find-by-username?username=$encoded',
      headers: {'Authorization': 'Bearer $token'},
    );

    List<dynamic> items = const [];
    if (data is Map<String, dynamic>) {
      final nested = data['items'];
      if (nested is List) {
        items = nested;
      } else if (data['data'] is Map<String, dynamic>) {
        final nestedData = (data['data'] as Map<String, dynamic>)['items'];
        if (nestedData is List) {
          items = nestedData;
        }
      }
    }

    return items
        .whereType<Map>()
        .map((e) => UsernameSearchItem.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => e.id.isNotEmpty && e.username.isNotEmpty)
        .toList();
  }

  Future<String?> getChatIdForUser(String userId) async {
    final matches = await getMatches();
    for (final m in matches) {
      if (m.userId == userId && m.chatId != null && m.chatId!.isNotEmpty) {
        return m.chatId;
      }
    }
    return null;
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
