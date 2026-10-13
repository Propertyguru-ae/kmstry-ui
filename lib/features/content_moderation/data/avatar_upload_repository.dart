import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'pending_public_media.dart';

class AvatarUploadRepository {
  Future<Map<String, dynamic>> upload({
    required File file,
    required PendingPublicMedia draft,
    required int session,
  }) async {
    if ((draft.kind != PendingPublicMediaKind.personalAvatar &&
            draft.kind != PendingPublicMediaKind.venueAvatar) ||
        (draft.kind == PendingPublicMediaKind.venueAvatar &&
            (draft.venueId?.isEmpty ?? true))) {
      throw ArgumentError('Invalid avatar target');
    }
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    return PendingPublicMediaService.instance.runUpload<Map<String, dynamic>>(
      draft: draft,
      token: token,
      expectedGeneration: session,
      receiptId: (json) {
        final source = json['venue'] is Map ? json['venue'] as Map : json;
        // No fallback to user/venue ID: that could match an older approval.
        return source['moderation_item_id']?.toString();
      },
      send: (progress) async {
        final path = draft.kind == PendingPublicMediaKind.personalAvatar
            ? '/users/me/photo'
            : '/venues/${draft.venueId}/photo';
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}$path'),
        );
        request.headers.addAll(
          await AppRequestHeaders.build(accessToken: token),
        );
        request.files.add(
          await multipartFileWithProgress(
            field: 'file',
            file: file,
            contentType: MediaType.parse(
              lookupMimeType(file.path) ?? 'image/jpeg',
            ),
            onProgress: progress,
          ),
        );
        final response = await sendMultipartRequest(request);
        final body = await response.stream.bytesToString();
        if (response.statusCode >= 400) {
          if (response.statusCode < 500 && response.statusCode != 408) {
            throw PublicMediaUploadRejected(
              'Photo upload rejected (${response.statusCode})',
            );
          }
          throw const HttpException('Photo upload could not be confirmed');
        }
        return Map<String, dynamic>.from(jsonDecode(body) as Map);
      },
    );
  }
}
