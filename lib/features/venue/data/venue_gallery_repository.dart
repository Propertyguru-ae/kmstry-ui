import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/app_request_headers.dart';
import 'package:kmstry_frontend/core/network/multipart_upload.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'venue_gallery_model.dart';

class VenueGalleryRepository {
  final ApiClient _api = ApiClient();

  /// Galeri her değiştiğinde (yükleme/silme) artan sayaç. Home'daki galeri
  /// kartı gibi bağımsız state'ler bunu dinleyip kendini tazeleyebilir — böylece
  /// profil sayfasından eklenen medya home kartında da anında görünür.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void _notifyChanged() => changes.value++;

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
  }) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/gallery');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeParts = mimeType.split('/');
    request.files.add(
      await multipartFileWithProgress(
        field: 'file',
        file: file,
        contentType: MediaType(
          mimeParts[0],
          mimeParts.length > 1 ? mimeParts[1] : 'octet-stream',
        ),
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

    final response = await sendMultipartRequest(
      request,
      timeout: const Duration(minutes: 5),
    );
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw Exception('Upload failed (${response.statusCode}): $body');
    }
    final json = jsonDecode(body);
    final item = VenueGalleryItem.fromJson(
      Map<String, dynamic>.from(json as Map),
    );
    _notifyChanged();
    return item;
  }

  Future<void> deleteItem(String venueId, String itemId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/gallery/$itemId',
      headers: {'Authorization': 'Bearer $token'},
    );
    _notifyChanged();
  }
}
