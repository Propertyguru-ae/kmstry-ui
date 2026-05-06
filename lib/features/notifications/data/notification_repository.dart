import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';

class NotificationRepository {
  final ApiClient _api = ApiClient();

  Future<String?> _token() => SecureStorage.getAccessToken();

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
}
