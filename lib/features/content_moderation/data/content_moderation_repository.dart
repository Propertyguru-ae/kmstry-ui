import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_item.dart';

class ContentModerationRepository {
  ContentModerationRepository({ApiClient? apiClient})
    : _api = apiClient ?? ApiClient();

  final ApiClient _api;

  Future<void> removeEventPhotoUpload({
    required String venueId,
    required String itemId,
    required bool Function() isCurrentSession,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) throw StateError('Not authenticated');
    if (!isCurrentSession()) throw StateError('Upload session changed');
    await _api.delete(
      '/venues/${Uri.encodeComponent(venueId)}/events/photo-uploads/${Uri.encodeComponent(itemId)}',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> cancelStoryUpload({
    required String uploadId,
    String? checkinId,
    String? venueId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) throw StateError('Not authenticated');
    if (venueId == null && checkinId == null) {
      throw StateError('Missing story context');
    }
    final path = venueId != null
        ? '/venues/$venueId/venue-stories/uploads/${Uri.encodeComponent(uploadId)}'
        : '/checkins/$checkinId/story-uploads/${Uri.encodeComponent(uploadId)}';
    await _api.delete(path, headers: {'Authorization': 'Bearer $token'});
  }

  Future<ContentModerationPageResult> listMyItems({
    int page = 1,
    int limit = 20,
    int? recentDays,
    String? status,
    String? targetType,
    String? targetId,
    String? itemId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Not authenticated');
    }

    final query = Uri(
      path: '/content-moderation/me',
      queryParameters: {
        'page': page.toString(),
        'limit': limit.toString(),
        if (recentDays != null) 'recentDays': recentDays.toString(),
        if (status != null && status.isNotEmpty) 'status': status,
        if (targetType != null && targetType.isNotEmpty)
          'targetType': targetType,
        if (targetId != null && targetId.isNotEmpty) 'targetId': targetId,
        if (itemId != null && itemId.isNotEmpty) 'itemId': itemId,
      },
    ).toString();
    final raw = await _api.get(
      query,
      headers: {'Authorization': 'Bearer $token'},
    );
    if (raw is! Map) throw const FormatException('Invalid moderation response');
    return ContentModerationPageResult.fromJson(Map<String, dynamic>.from(raw));
  }
}
