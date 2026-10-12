import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_upload_failure.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

class VenueStoryRepository {
  VenueStoryRepository({
    AuthenticatedMultipartUpload? uploads,
    PendingPublicMediaService? uploadService,
  }) : _uploads = uploads ?? AuthenticatedMultipartUpload(),
       _uploadService = uploadService ?? PendingPublicMediaService.instance;

  final ApiClient _api = ApiClient();
  final AuthenticatedMultipartUpload _uploads;
  final PendingPublicMediaService _uploadService;

  /// Venue story'leri değiştiğinde (paylaşma/silme) artan sayaç. Home'daki story
  /// kartı bunu dinleyip kendini tazeler.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void _notifyChanged() => changes.value++;

  Future<VenueStoryItem> createVenueStory({
    required String venueId,
    required File file,
    required String mediaType,
    String? textOverlayJson,
    MultipartUploadProgress? onProgress,
    int? uploadSession,
    PendingPublicMedia? pendingDraft,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    final session = uploadSession ?? _uploadService.sessionGeneration;
    final draft =
        pendingDraft ??
        PendingPublicMedia(
          id: PendingPublicMediaService.newUploadId(),
          kind: PendingPublicMediaKind.venueStory,
          venueId: venueId,
          localPath: file.path,
          isVideo: mediaType == 'video',
          createdAt: DateTime.now(),
          hasServerReceipt: false,
          textOverlay: MediaTextOverlay.fromJson(textOverlayJson),
        );
    return _uploadService.runUpload<VenueStoryItem>(
      token: token,
      expectedGeneration: session,
      draft: draft,
      receiptId: (item) => item.id,
      onProgress: onProgress,
      send: (onProgress) async {
        final uri = Uri.parse(
          '${AppConfig.baseUrl}/venues/$venueId/venue-stories',
        );

        final response = await _uploads.send(
          initialToken: token,
          isCurrentSession: () => _uploadService.isCurrentSession(session),
          timeout: const Duration(minutes: 5),
          cancellation: _uploadService.storyCancellation(draft.id),
          createRequest: (headers) async {
            final request = http.MultipartRequest('POST', uri);
            request.headers.addAll(headers);
            final mimeType =
                lookupMimeType(file.path) ?? 'application/octet-stream';
            final mimeSplit = mimeType.split('/');
            request.files.add(
              await multipartFileWithProgress(
                field: 'file',
                file: file,
                contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
                onProgress: onProgress,
              ),
            );
            request.fields['media_type'] = mediaType;
            request.fields['upload_id'] = draft.id;
            if (textOverlayJson != null && textOverlayJson.trim().isNotEmpty) {
              request.fields['textOverlay'] = textOverlayJson;
            }
            return request;
          },
        );
        final body = response.body;

        if (response.statusCode >= 400) {
          if (response.statusCode < 500 && response.statusCode != 408) {
            throw StoryUploadFailure.fromResponse(response.statusCode, body);
          }
          throw Exception('Venue story upload failed (${response.statusCode})');
        }

        final item = VenueStoryItem.fromJson(
          jsonDecode(body) as Map<String, dynamic>,
        );
        // Moderation publication, not the upload receipt, refreshes story lists.
        return item;
      },
    );
  }

  Future<List<VenueStoryItem>> getVenueStories(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/venue-stories',
      headers: {'Authorization': 'Bearer $token'},
    );

    final list = data is List ? data : (data['data'] as List? ?? []);
    return list
        .map((e) => VenueStoryItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordView(String venueId, String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.post(
      '/venues/$venueId/venue-stories/$storyId/view',
      headers: {'Authorization': 'Bearer $token'},
      body: {},
    );
  }

  Future<void> deleteStory(String venueId, String storyId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/venue-stories/$storyId',
      headers: {'Authorization': 'Bearer $token'},
    );
    _notifyChanged();
  }

  Future<List<Map<String, dynamic>>> getViewers(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/venue-stories/viewers',
      headers: {'Authorization': 'Bearer $token'},
    );
    final list = data is List ? data : (data['data'] as List? ?? []);
    return list.cast<Map<String, dynamic>>();
  }
}
