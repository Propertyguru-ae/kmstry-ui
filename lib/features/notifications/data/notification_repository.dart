import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';

typedef ConnectionNoticeTarget = ({
  String otherUserId,
  String otherName,
  String? chatId,
});

class NotificationRepository {
  final ApiClient _api = ApiClient();

  Future<String?> _token() => SecureStorage.getAccessToken();

  Future<ConnectionNoticeTarget?> resolveConnectionNotice(
    String id, {
    String? version,
    DateTime? seenAt,
  }) async {
    final token = await _token();
    if (token == null) throw StateError('Not authenticated');
    final path = Uri(
      pathSegments: ['', 'notifications', 'connections', id],
      queryParameters: {
        'version': ?version,
        if (seenAt != null) 'seenAt': seenAt.toUtc().toIso8601String(),
      },
    );
    final data = await _api.get(
      path.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map || !data.containsKey('connection')) {
      throw const FormatException('Invalid connection response');
    }
    final row = data['connection'];
    if (row == null) return null;
    if (row is! Map ||
        row['otherUserId'] is! String ||
        (row['otherUserId'] as String).isEmpty) {
      throw const FormatException('Missing connection participant');
    }
    return (
      otherUserId: row['otherUserId'] as String,
      otherName: row['otherName'] as String? ?? 'Your connection',
      chatId: row['chatId'] as String?,
    );
  }

  Future<bool> isPendingInterest(
    String sender, {
    String? id,
    DateTime? version,
  }) async {
    final token = await _token();
    if (token == null) throw StateError('Not authenticated');
    final path = Uri(
      pathSegments: ['', 'notifications', 'interests', sender],
      queryParameters: id == null
          ? null
          : {'id': id, 'version': version!.toUtc().toIso8601String()},
    );
    final data = await _api.get(
      path.toString(),
      headers: {'Authorization': 'Bearer $token'},
    );
    return data is Map && data['available'] == true;
  }

  /// GET /notifications?limit=... — list for current user (JWT), created_at desc.
  Future<List<NotificationModel>> getNotifications({int limit = 50}) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final path = '/notifications?limit=$limit';
    final data = await _api.get(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );
    final items = _extractItems(data);
    return items
        .whereType<Map>()
        .map((e) => NotificationModel.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  List<dynamic> _extractItems(dynamic data) {
    if (data is List) return data;
    if (data is Map<String, dynamic>) {
      final nested =
          data['items'] ??
          data['notifications'] ??
          data['results'] ??
          (data['data'] is List
              ? data['data']
              : (data['data'] is Map<String, dynamic>
                    ? (data['data'] as Map<String, dynamic>)['items']
                    : null));
      if (nested is List) return nested;
    }
    return const [];
  }

  /// PATCH /notifications/read — mark all as read.
  Future<void> markAllAsRead() async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    await _api.patch(
      '/notifications/read',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  /// PATCH /notifications/:id/read — mark one as read.
  Future<void> markAsRead(String id) async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    await _api.patch(
      '/notifications/$id/read',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  Future<int> getUnreadCount() async {
    final token = await _token();
    if (token == null) throw Exception('Not authenticated');

    final data = await _api.get(
      '/notifications/unread-count',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is Map<String, dynamic>) {
      final raw = data['unreadCount'] ?? data['unread_count'] ?? data['count'];
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }
    return 0;
  }
}
