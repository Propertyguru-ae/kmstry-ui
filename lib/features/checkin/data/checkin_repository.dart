import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:kmstry_frontend/core/config/app_config.dart';

import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_intent_selection.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/features/stories/data/story_visibility.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'moment_upload_failure.dart';
import '../services/active_checkin_service.dart';

class CheckinMediaUploadTarget {
  final String uploadUrl;
  final String publicUrl;
  final Map<String, String> headers;

  const CheckinMediaUploadTarget({
    required this.uploadUrl,
    required this.publicUrl,
    required this.headers,
  });

  factory CheckinMediaUploadTarget.fromJson(Map<String, dynamic> json) {
    final rawHeaders = json['headers'];
    return CheckinMediaUploadTarget(
      uploadUrl: json['uploadUrl']?.toString() ?? '',
      publicUrl: json['publicUrl']?.toString() ?? '',
      headers: rawHeaders is Map
          ? rawHeaders.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const <String, String>{},
    );
  }
}

enum CheckinActivationState {
  pending,
  processing,
  approved,
  readyToActivate,
  needsReview,
  rejected,
  error,
  expired,
  activationExpired,
  cancelled,
  unknown,
}

class CheckinActivationStatus {
  const CheckinActivationStatus({
    required this.checkinId,
    required this.venueId,
    required this.state,
    required this.canJoin,
    this.reasonCode,
    this.userMessage,
    this.moderationItemId,
  });

  final String checkinId;
  final String venueId;
  final CheckinActivationState state;
  final bool canJoin;
  final String? reasonCode;
  final String? userMessage;
  final String? moderationItemId;

  factory CheckinActivationStatus.fromJson(Map<String, dynamic> json) {
    final rawStatus = json['status']?.toString().toUpperCase() ?? '';
    final state = switch (rawStatus) {
      'PENDING' => CheckinActivationState.pending,
      'PROCESSING' => CheckinActivationState.processing,
      'APPROVED' => CheckinActivationState.approved,
      'READY_TO_ACTIVATE' => CheckinActivationState.readyToActivate,
      'NEEDS_REVIEW' => CheckinActivationState.needsReview,
      'REJECTED' => CheckinActivationState.rejected,
      'ERROR' => CheckinActivationState.error,
      'EXPIRED' => CheckinActivationState.expired,
      'ACTIVATION_EXPIRED' => CheckinActivationState.activationExpired,
      'CANCELLED' => CheckinActivationState.cancelled,
      _ => CheckinActivationState.unknown,
    };
    return CheckinActivationStatus(
      checkinId: json['checkin_id']?.toString() ?? '',
      venueId: json['venue_id']?.toString() ?? '',
      state: state,
      canJoin: json['can_join'] == true,
      reasonCode: json['reason_code']?.toString(),
      userMessage: json['user_message']?.toString(),
      moderationItemId: json['moderation_item_id']?.toString(),
    );
  }
}

class CheckinRepository {
  CheckinRepository({ApiClient? apiClient}) : _api = apiClient ?? ApiClient();
  final ApiClient _api;

  /// 1️⃣ Check-in oluştur (JSON)
  Future<String> createCheckin({
    required String venueId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? locationCapturedAt,
    required String vibe,
    required List<String> whatBringsYou,
    bool showOnProfile = false,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final selectedReasons = normalizeRequiredCheckinIntents(whatBringsYou);

    final body = <String, dynamic>{
      'venue_id': venueId,
      'checkin_method': 'gps',
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (locationCapturedAt != null)
        'location_captured_at': locationCapturedAt.toUtc().toIso8601String(),
      'vibe': vibe,
      'show_on_profile': showOnProfile,
      'what_brings_to_kmstry': selectedReasons,
    };

    final data = await _api.post(
      '/checkins',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );

    final checkinId = data is Map ? data['id']?.toString() : null;
    if (checkinId == null || checkinId.isEmpty) {
      throw Exception('Check-in could not be created: missing id');
    }
    return checkinId;
  }

  Future<String> createPendingCheckin({
    required String venueId,
    required double latitude,
    required double longitude,
    double? accuracyMeters,
    DateTime? locationCapturedAt,
    required String vibe,
    required List<String> whatBringsYou,
    bool showOnProfile = false,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final selectedReasons = normalizeRequiredCheckinIntents(whatBringsYou);

    final body = <String, dynamic>{
      'venue_id': venueId,
      'checkin_method': 'gps',
      'latitude': latitude,
      'longitude': longitude,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
      if (locationCapturedAt != null)
        'location_captured_at': locationCapturedAt.toUtc().toIso8601String(),
      'vibe': vibe,
      'show_on_profile': showOnProfile,
      'what_brings_to_kmstry': selectedReasons,
    };

    final data = await _api.post(
      '/checkins/pending',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );

    final checkinId = data is Map ? data['id']?.toString() : null;
    if (checkinId == null || checkinId.isEmpty) {
      throw Exception('Check-in could not be created: missing id');
    }
    return checkinId;
  }

  Future<List<String>> getWhatBringsOptions() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    final data = await _api.get(
      '/checkins/options/what-brings',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (data is Map && data['options'] is List) {
      return List<String>.from(data['options']);
    }

    return [];
  }

  Future<CheckinActivationStatus> getCheckinActivationStatus(
    String checkinId,
  ) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) {
      throw StateError('Not authenticated');
    }
    final data = await _api.get(
      '/checkins/$checkinId/activation-status',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (data is! Map) {
      throw const FormatException('Invalid check-in status response');
    }
    return CheckinActivationStatus.fromJson(Map<String, dynamic>.from(data));
  }

  /// Complete a delayed approval with the same Moment and a fresh location.
  Future<CheckinActivationStatus> activatePendingCheckin({
    required String checkinId,
    required String moderationItemId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime locationCapturedAt,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) throw StateError('Not authenticated');
    final data = await _api.post(
      '/checkins/$checkinId/activate',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'moderation_item_id': moderationItemId,
        'latitude': latitude,
        'longitude': longitude,
        'accuracy_meters': accuracyMeters,
        'location_captured_at': locationCapturedAt.toUtc().toIso8601String(),
      },
    );
    if (data is! Map) {
      throw const FormatException('Invalid check-in activation response');
    }
    return CheckinActivationStatus.fromJson(Map<String, dynamic>.from(data));
  }

  /// 2️⃣ Foto yükle (MULTIPART)
  Future<void> uploadCheckinPhoto({
    required String checkinId,
    required File file,
    required bool isFeatured,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final uri = Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/photos');

    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    request.files.add(await http.MultipartFile.fromPath('file', file.path));

    request.fields['isFeatured'] = isFeatured.toString();

    final response = await sendMultipartRequest(request);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      throw Exception('Upload failed (${response.statusCode}): $responseBody');
    }
  }

  Future<String?> uploadCheckinAvatar({
    required String checkinId,
    required File file,
  }) async {
    final uploads = PendingPublicMediaService.instance;
    final session = uploads.sessionGeneration;
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    await uploads.restoreAuthenticatedSession(
      token,
      expectedGeneration: session,
    );
    if (!uploads.isCurrentSession(session)) {
      throw StateError('UPLOAD_SESSION_CHANGED');
    }

    final uri = Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/avatar');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));
    final mimeType = lookupMimeType(file.path) ?? 'image/jpeg';
    final mimeSplit = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        filename: 'checkin-avatar.jpg',
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
      ),
    );

    final response = await sendMultipartRequest(request);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      throw Exception(
        'Avatar upload failed (${response.statusCode}): $responseBody',
      );
    }

    final data = responseBody.isNotEmpty
        ? jsonDecode(responseBody) as Map<String, dynamic>
        : const <String, dynamic>{};
    if (!uploads.isCurrentSession(session) ||
        ActiveCheckinService().activeCheckinId != checkinId) {
      return null;
    }
    final receipt = data['moderation'];
    final itemId = receipt is Map ? receipt['id']?.toString() : null;
    if (itemId != null && itemId.isNotEmpty) {
      for (final previous in uploads.forKind(
        PendingPublicMediaKind.checkinAvatar,
      )) {
        if (previous.checkinId == checkinId) uploads.dismiss(previous.id);
      }
      uploads.track(
        PendingPublicMedia(
          id: itemId,
          kind: PendingPublicMediaKind.checkinAvatar,
          venueId: null,
          checkinId: checkinId,
          localPath: file.path,
          isVideo: false,
          createdAt: DateTime.now(),
        ),
      );
    }
    ActiveCheckinService().notifyMediaUpdated();
    return (data['avatarPhoto'] ?? data['avatar_photo'])?.toString();
  }

  Future<String?> uploadCheckinMedia({
    required String checkinId,
    required File file,
    required bool isFeatured,
    String? textOverlayJson,
    MultipartUploadProgress? onProgress,
    // Retake: yeni medya kaydedilince backend bu medyayı siler (limitten hariç).
    String? replaceMediaId,
    bool trackInBackground = false,
    String? venueId,
    int? uploadSession,
    PendingPublicMedia? pendingDraft,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (trackInBackground) {
      if (token == null) throw Exception('Not authenticated');
      return PendingPublicMediaService.instance.runUpload<String?>(
        token: token,
        expectedGeneration: uploadSession,
        draft:
            pendingDraft ??
            PendingPublicMedia(
              id: PendingPublicMediaService.newUploadId(),
              kind: PendingPublicMediaKind.checkinMoment,
              venueId: venueId,
              checkinId: checkinId,
              localPath: file.path,
              isVideo: (lookupMimeType(file.path) ?? '').startsWith('video/'),
              createdAt: DateTime.now(),
              hasServerReceipt: false,
            ),
        receiptId: (id) => id,
        onProgress: onProgress,
        send: (progress) => _sendCheckinMedia(
          checkinId: checkinId,
          file: file,
          isFeatured: isFeatured,
          textOverlayJson: textOverlayJson,
          onProgress: progress,
          replaceMediaId: replaceMediaId,
          token: token,
        ),
      );
    }
    return _sendCheckinMedia(
      checkinId: checkinId,
      file: file,
      isFeatured: isFeatured,
      textOverlayJson: textOverlayJson,
      onProgress: onProgress,
      replaceMediaId: replaceMediaId,
      token: token,
    );
  }

  Future<String?> _sendCheckinMedia({
    required String checkinId,
    required File file,
    required bool isFeatured,
    required String? token,
    String? textOverlayJson,
    MultipartUploadProgress? onProgress,
    String? replaceMediaId,
  }) async {
    final uri = Uri.parse('${AppConfig.baseUrl}/checkins/$checkinId/media');

    final request = http.MultipartRequest('POST', uri);

    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    // ✅ MIME TYPE FIX
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeSplit = mimeType.split('/');

    request.files.add(
      await multipartFileWithProgress(
        field: 'file',
        file: file,
        contentType: http_parser.MediaType(mimeSplit[0], mimeSplit[1]),
        onProgress: onProgress,
      ),
    );

    request.fields['isFeatured'] = isFeatured.toString();
    if (textOverlayJson != null && textOverlayJson.isNotEmpty) {
      request.fields['textOverlay'] = textOverlayJson;
    }
    if (replaceMediaId != null && replaceMediaId.isNotEmpty) {
      request.fields['replaceMediaId'] = replaceMediaId;
    }

    final response = await sendMultipartRequest(request);
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode >= 400) {
      if (response.statusCode < 500 && response.statusCode != 408) {
        throw MomentUploadFailure.fromResponse(
          response.statusCode,
          responseBody,
        );
      }
      if (kDebugMode) {
        debugPrint(
          '[MomentUpload] response status=${response.statusCode}; outcome=unconfirmed',
        );
      }
      throw Exception('Media upload failed (${response.statusCode})');
    }

    if (responseBody.isEmpty) return null;
    final data = jsonDecode(responseBody);
    return data is Map ? data['id']?.toString() : null;
  }

  Future<CheckinMediaUploadTarget> createCheckinMediaUploadUrl({
    required String checkinId,
    required File file,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final sizeBytes = await file.length();

    final data = await _api.post(
      '/checkins/$checkinId/media/upload-url',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'mimeType': mimeType,
        'fileName': file.uri.pathSegments.isNotEmpty
            ? file.uri.pathSegments.last
            : 'media',
        'sizeBytes': sizeBytes,
      },
    );

    return CheckinMediaUploadTarget.fromJson(data as Map<String, dynamic>);
  }

  Future<void> uploadFileToSignedUrl({
    required CheckinMediaUploadTarget target,
    required File file,
  }) async {
    // NOT: Önceden StreamedRequest kullanılıyordu ama send()'den önce
    // sink.addStream çağrıldığı için büyük dosyalarda deadlock oluyordu
    // (tüketici başlamadan iç buffer doluyordu). Dosyayı belleğe okuyup tek
    // seferde PUT ediyoruz — sıkıştırılmış video/720px foto için boyut güvenli.
    final bytes = await file.readAsBytes();
    final client = http.Client();
    late final http.Response response;
    try {
      response = await client
          .put(
            Uri.parse(target.uploadUrl),
            headers: target.headers,
            body: bytes,
          )
          .timeout(const Duration(minutes: 2));
    } finally {
      // A timeout must also abort the underlying socket. The shared top-level
      // http.put helper cannot be explicitly closed by the caller.
      client.close();
    }

    if (response.statusCode >= 400) {
      throw Exception(
        'Direct media upload failed (${response.statusCode}): ${response.body}',
      );
    }
  }

  Future<void> confirmCheckinMediaUpload({
    required String checkinId,
    required CheckinMediaUploadTarget target,
    required File file,
    required bool isFeatured,
    String? textOverlayJson,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final sizeBytes = await file.length();

    await _api.post(
      '/checkins/$checkinId/media/confirm',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'url': target.publicUrl,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'isFeatured': isFeatured,
        if (textOverlayJson != null && textOverlayJson.isNotEmpty)
          'textOverlay': textOverlayJson,
      },
    );
  }

  Future<List<dynamic>> getMyCheckinMedia() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    final data = await _api.get(
      '/users/me/checkin-media',
      headers: {'Authorization': 'Bearer $token'},
    );

    if (data is! List) return [];

    return data;
  }

  /// Logged-in user's check-in photos (for own profile moments list).
  /// Tries GET /users/me/checkin-photos; response: list of { url } or list of url strings.
  Future<List<String>> getMyCheckinPhotos() async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) return [];

    try {
      final data = await _api.get(
        '/users/me/checkin-photos',
        headers: {'Authorization': 'Bearer $token'},
      );
      if (data is! List) return [];
      final list = data;
      return list
          .map((e) {
            if (e is String) return e;
            if (e is Map && e['url'] != null) return e['url'] as String;
            return null;
          })
          .whereType<String>()
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<CheckinProfile> getCheckinProfile(String checkinId) async {
    final token = await SecureStorage.getAccessToken();

    final data = await _api.get(
      '/checkins/$checkinId/profile',
      headers: {'Authorization': 'Bearer $token'},
    );

    return CheckinProfile.fromJson(data);
  }

  Future<PublicUserProfile> getPublicUserProfile(String userId) async {
    final token = await SecureStorage.getAccessToken();

    final data = await _api.get(
      '/users/$userId/public-profile',
      headers: {'Authorization': 'Bearer $token'},
    );

    return PublicUserProfile.fromJson(data as Map<String, dynamic>);
  }

  Future<List<CheckinVisitedPlace>> getMyProfileHistory() async {
    final token = await SecureStorage.getAccessToken();

    final data = await _api.get(
      '/checkins/me/profile-history',
      headers: {'Authorization': 'Bearer $token'},
    );

    final items = data is Map ? data['items'] : data;
    return CheckinVisitedPlace.listFromJson(items);
  }

  Future<void> updateProfileVisibility({
    required String checkinId,
    required bool showOnProfile,
  }) async {
    final token = await SecureStorage.getAccessToken();

    await _api.patch(
      '/checkins/$checkinId/profile-visibility',
      headers: {'Authorization': 'Bearer $token'},
      body: {'show_on_profile': showOnProfile},
    );
  }

  Future<void> deleteVisitedPlace(String checkinId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.delete(
      '/checkins/$checkinId/history',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> setFeaturedPhoto(String photoId) async {
    final token = await SecureStorage.getAccessToken();

    await _api.patch(
      '/checkins/photos/$photoId/feature',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> updateVibe({
    required String checkinId,
    required String vibe,
  }) async {
    final token = await SecureStorage.getAccessToken();

    await _api.patch(
      '/checkins/$checkinId/vibe',
      headers: {'Authorization': 'Bearer $token'},
      body: {"vibe": vibe},
    );
  }

  /// Aktif check-in'in "what brings you to Kmstry" seçimlerini günceller.
  /// Backend doğrulanmış listeyi döndürür (max 3, enum'a uygun).
  Future<List<String>> updateWhatBrings({
    required String checkinId,
    required List<String> values,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.patch(
      '/checkins/$checkinId/what-brings',
      headers: {'Authorization': 'Bearer $token'},
      body: {'what_brings_to_kmstry': values},
    );
    final raw = (data is Map)
        ? (data['what_brings_to_kmstry'] ?? data['whatBringsToKmstry'])
        : null;
    if (raw is List) {
      return raw
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }
    return values;
  }

  Future<bool> deletePhoto(String photoId) async {
    final token = await SecureStorage.getAccessToken();

    final response = await _api.delete(
      '/checkins/photos/$photoId',
      headers: {'Authorization': 'Bearer $token'},
    );
    if (response is! Map) return false;
    return response['checkin_inactivated'] == true ||
        response['checkinInactivated'] == true;
  }

  Future<void> sendFeedAction({
    required String targetUserId,
    String? venueId,
    // required String checkinId,
    required String action,
  }) async {
    final token = await SecureStorage.getAccessToken();

    final body = <String, dynamic>{
      'target_user_id': targetUserId,
      //'checkin_id': checkinId,
      'action': action,
    };
    if (venueId != null && venueId.isNotEmpty) {
      body['venue_id'] = venueId;
    }

    await _api.post(
      '/feed/actions',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );
  }

  /// Rewind/undo the current user's last action (pass OR interested) toward
  /// [targetUserId] so the profile becomes actionable again. Backend enforces
  /// the daily rewind quota (403 REWIND_LIMIT_REACHED) and blocks undoing an
  /// interested once matched (409 MATCH_EXISTS).
  Future<void> undoAction(String targetUserId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/feed/actions/$targetUserId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<void> blockUser(String targetUserId) async {
    final token = await SecureStorage.getAccessToken();

    await _api.post(
      '/blocks',
      headers: {'Authorization': 'Bearer $token'},
      body: {'blocked_id': targetUserId},
    );
    StoryVisibility.changed(targetUserId, blocked: true);
  }

  Future<void> reportUser({
    String? targetUserId,
    required String reason,
    String? details,
    String? messageId,
    String? storyId,
    String? venueStoryId,
    String? checkinMediaId,
    String? venueId,
    String? venuePhotoId,
    String? venuePhotoUrl,
    String? googlePhotoToken,
    String? venueGalleryItemId,
    String? eventId,
    String? venueOfferId,
    String? venueMenuItemId,
    String? venueBenefitId,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final body = <String, dynamic>{
      if (targetUserId != null && targetUserId.trim().isNotEmpty)
        'reported_user_id': targetUserId.trim(),
      'reason': reason,
      if (details != null && details.trim().isNotEmpty)
        'details': details.trim(),
      if (messageId != null && messageId.trim().isNotEmpty)
        'message_id': messageId.trim(),
      if (storyId != null && storyId.trim().isNotEmpty)
        'story_id': storyId.trim(),
      if (venueStoryId != null && venueStoryId.trim().isNotEmpty)
        'venue_story_id': venueStoryId.trim(),
      if (checkinMediaId != null && checkinMediaId.trim().isNotEmpty)
        'checkin_media_id': checkinMediaId.trim(),
      if (venueId != null && venueId.trim().isNotEmpty)
        'venue_id': venueId.trim(),
      if (venuePhotoId != null && venuePhotoId.trim().isNotEmpty)
        'venue_photo_id': venuePhotoId.trim(),
      if (venuePhotoUrl != null && venuePhotoUrl.trim().isNotEmpty)
        'venue_photo_url': venuePhotoUrl.trim(),
      if (googlePhotoToken != null && googlePhotoToken.trim().isNotEmpty)
        'google_photo_token': googlePhotoToken.trim(),
      if (venueGalleryItemId != null && venueGalleryItemId.trim().isNotEmpty)
        'venue_gallery_item_id': venueGalleryItemId.trim(),
      if (eventId != null && eventId.trim().isNotEmpty)
        'event_id': eventId.trim(),
      if (venueOfferId != null && venueOfferId.trim().isNotEmpty)
        'venue_offer_id': venueOfferId.trim(),
      if (venueMenuItemId != null && venueMenuItemId.trim().isNotEmpty)
        'venue_menu_item_id': venueMenuItemId.trim(),
      if (venueBenefitId != null && venueBenefitId.trim().isNotEmpty)
        'venue_benefit_id': venueBenefitId.trim(),
    };

    await _api.post(
      '/reports/users',
      headers: {'Authorization': 'Bearer $token'},
      body: body,
    );
    final reportsSelectedContent =
        messageId != null ||
        storyId != null ||
        venueStoryId != null ||
        checkinMediaId != null ||
        venueId != null ||
        venuePhotoId != null ||
        googlePhotoToken != null ||
        venueGalleryItemId != null ||
        eventId != null ||
        venueOfferId != null ||
        venueMenuItemId != null ||
        venueBenefitId != null;
    if (!reportsSelectedContent &&
        targetUserId != null &&
        targetUserId.trim().isNotEmpty) {
      StoryVisibility.changed(targetUserId, blocked: true);
    }
  }

  Future<void> unblockUser(String targetUserId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    await _api.delete(
      '/blocks/$targetUserId',
      headers: {'Authorization': 'Bearer $token'},
    );
    StoryVisibility.changed(targetUserId, blocked: false);
  }

  Future<Set<String>> getBlockedUserIds() async {
    final token = await SecureStorage.getAccessToken();
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
    final result = <String>{};
    for (final raw in list) {
      if (raw is! Map) continue;
      final json = Map<String, dynamic>.from(raw);
      final user = json['user'] is Map
          ? Map<String, dynamic>.from(json['user'] as Map)
          : null;
      final id =
          json['user_id'] as String? ??
          json['blocked_id'] as String? ??
          json['blocked_user_id'] as String? ??
          json['target_user_id'] as String? ??
          json['userId'] as String? ??
          user?['id'] as String?;
      if (id != null && id.isNotEmpty) result.add(id);
    }
    return result;
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

  /// Kullanıcının aktif check-in'ini manuel olarak kapatır.
  /// Backend: DELETE /checkins/:id
  Future<void> checkout(String checkinId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.delete(
      '/checkins/$checkinId',
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  /// Withdraw the first Moment and close its check-in, even after late approval.
  /// Normal checkout deliberately keeps the user's completed Moment history.
  Future<void> cancelPendingCheckin(String checkinId) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');
    await _api.delete(
      '/checkins/$checkinId/pending',
      headers: {'Authorization': 'Bearer $token'},
    );
  }
}
