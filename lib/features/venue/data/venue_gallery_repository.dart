import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/network/authenticated_multipart_upload.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_gallery_model.dart';
import 'venue_gallery_upload_failure.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

class VenueGalleryRepository {
  VenueGalleryRepository({
    AuthenticatedMultipartUpload? uploads,
    PendingPublicMediaService? uploadService,
  }) : _uploads = uploads ?? AuthenticatedMultipartUpload(),
       _uploadService = uploadService ?? PendingPublicMediaService.instance;

  final ApiClient _api = ApiClient();
  final AuthenticatedMultipartUpload _uploads;
  final PendingPublicMediaService _uploadService;

  /// Galeri her değiştiğinde (yükleme/silme) artan sayaç. Home'daki galeri
  /// kartı gibi bağımsız state'ler bunu dinleyip kendini tazeleyebilir — böylece
  /// profil sayfasından eklenen medya home kartında da anında görünür.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void notifyChanged() => changes.value++;

  Future<List<VenueGalleryItem>> getGallery(String venueId) async {
    // Endpoint JwtAuthGuard ile korumalı → token gönderilmezse 401 döner ve
    // galeri boş görünür. (upload/delete zaten token gönderiyor.)
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/gallery',
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    return (data as List)
        .whereType<Map>()
        .map((e) => VenueGalleryItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Foto veya video yükler (limit yok). [thumbnail] video için önizleme karesi.
  Future<VenueGalleryItem> uploadItem(
    String venueId,
    File file, {
    File? thumbnail,
    MultipartUploadProgress? onProgress,
    int? uploadSession,
    PendingPublicMedia? pendingDraft,
  }) async {
    final revision = SecureStorage.sessionRevision;
    final session = uploadSession ?? _uploadService.sessionGeneration;
    bool isCurrentSession() =>
        revision == SecureStorage.sessionRevision &&
        _uploadService.isCurrentSession(session);
    final token = await SecureStorage.getAccessToken();
    if (!isCurrentSession()) throw StateError('UPLOAD_SESSION_CHANGED');
    if (token == null) throw VenueGalleryUploadFailure.fromResponse(401, '');
    return _uploadService.runUpload<VenueGalleryItem>(
      token: token,
      expectedGeneration: session,
      draft:
          pendingDraft ??
          PendingPublicMedia(
            id: PendingPublicMediaService.newUploadId(),
            kind: PendingPublicMediaKind.venueGallery,
            venueId: venueId,
            localPath: file.path,
            isVideo: (lookupMimeType(file.path) ?? '').startsWith('video/'),
            createdAt: DateTime.now(),
            hasServerReceipt: false,
          ),
      receiptId: (item) => item.id,
      onProgress: onProgress,
      send: (onProgress) async {
        final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/gallery');
        final response = await _uploads.send(
          initialToken: token,
          isCurrentSession: isCurrentSession,
          timeout: const Duration(minutes: 5),
          // Multipart streams are single-use. Rebuild only after a definite
          // authentication rejection; never replay a timeout or server error.
          createRequest: (headers) async {
            final request = http.MultipartRequest('POST', uri);
            request.headers.addAll(headers);
            final mimeType =
                lookupMimeType(file.path) ?? 'application/octet-stream';
            request.files.add(
              await multipartFileWithProgress(
                field: 'file',
                file: file,
                contentType: MediaType.parse(mimeType),
                onProgress: onProgress,
              ),
            );
            if (thumbnail != null) {
              request.files.add(
                await http.MultipartFile.fromPath(
                  'thumbnail',
                  thumbnail.path,
                  contentType: MediaType('image', 'jpeg'),
                ),
              );
            }
            return request;
          },
        );
        final body = response.body;
        if (response.statusCode >= 400) {
          if (response.statusCode < 500 && response.statusCode != 408) {
            throw VenueGalleryUploadFailure.fromResponse(
              response.statusCode,
              body,
            );
          }
          // Do not retain response bodies, signed URLs or private media details.
          throw HttpException(
            'Gallery upload could not be confirmed (${response.statusCode})',
          );
        }
        final json = jsonDecode(body);
        final item = VenueGalleryItem.fromJson(
          Map<String, dynamic>.from(json as Map),
        );
        // The receipt is not publication. The shared upload tracker refreshes
        // gallery lists only after the public endpoint returns this item.
        return item;
      },
    );
  }

  Future<void> deleteItem(
    String venueId,
    String itemId, {
    bool Function()? isCurrentSession,
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw StateError('Not authenticated');
    if (isCurrentSession?.call() == false) {
      throw StateError('Upload session changed');
    }
    try {
      await _api.delete(
        '/venues/$venueId/gallery/$itemId',
        headers: {'Authorization': 'Bearer $token'},
      );
    } on ApiException catch (error) {
      // A simultaneous removal/cleanup is already the requested outcome.
      if (error.statusCode != 404) rethrow;
    }
    if (isCurrentSession?.call() != false) notifyChanged();
  }
}
