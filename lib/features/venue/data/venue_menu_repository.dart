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
import 'venue_menu_model.dart';

class VenueMenuRepository {
  final ApiClient _api = ApiClient();

  /// Menü her değiştiğinde artan sayaç — bağımsız ekranlar (profil/listeleme)
  /// bunu dinleyip kendini tazeleyebilir.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static void _notifyChanged() => changes.value++;

  Future<List<VenueMenuItem>> getMenu(String venueId) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.get(
      '/venues/$venueId/menu',
      headers: token != null ? {'Authorization': 'Bearer $token'} : null,
    );
    final items = (data is Map ? data['items'] : data);
    if (items is! List) return [];
    return items
        .whereType<Map>()
        .map((e) => VenueMenuItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  /// Tek bir menü foto'su yükler, kalıcı public URL döner.
  Future<String> uploadPhoto(String venueId, File file) async {
    final token = await SecureStorage.getAccessToken();
    if (token == null) throw Exception('Not authenticated');

    final uri = Uri.parse('${AppConfig.baseUrl}/venues/$venueId/menu/photo');
    final request = http.MultipartRequest('POST', uri);
    request.headers.addAll(await AppRequestHeaders.build(accessToken: token));

    final mimeType = lookupMimeType(file.path) ?? 'application/octet-stream';
    final mimeParts = mimeType.split('/');
    request.files.add(
      await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: MediaType(
          mimeParts[0],
          mimeParts.length > 1 ? mimeParts[1] : 'octet-stream',
        ),
      ),
    );

    final response = await sendMultipartRequest(request);
    final body = await response.stream.bytesToString();
    if (response.statusCode >= 400) {
      throw Exception('Upload failed (${response.statusCode}): $body');
    }
    final json = jsonDecode(body) as Map;
    return json['url'].toString();
  }

  Future<VenueMenuItem> createItem(
    String venueId, {
    required VenueMenuCategory category,
    required String title,
    String? description,
    double? price,
    String currency = 'TRY',
    List<String> photoUrls = const [],
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.post(
      '/venues/$venueId/menu',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        'category': category.apiValue,
        'title': title,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (price != null) 'price': price,
        'currency': currency,
        'photoUrls': photoUrls,
      },
    );
    _notifyChanged();
    return VenueMenuItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<VenueMenuItem> updateItem(
    String venueId,
    String itemId, {
    VenueMenuCategory? category,
    String? title,
    String? description,
    double? price,
    bool clearPrice = false,
    String? currency,
    List<String>? photoUrls,
  }) async {
    final token = await SecureStorage.getAccessToken();
    final data = await _api.patch(
      '/venues/$venueId/menu/$itemId',
      headers: {'Authorization': 'Bearer $token'},
      body: {
        if (category != null) 'category': category.apiValue,
        if (title != null) 'title': title,
        if (description != null) 'description': description,
        if (clearPrice) 'price': null else if (price != null) 'price': price,
        if (currency != null) 'currency': currency,
        if (photoUrls != null) 'photoUrls': photoUrls,
      },
    );
    _notifyChanged();
    return VenueMenuItem.fromJson(Map<String, dynamic>.from(data as Map));
  }

  Future<void> deleteItem(String venueId, String itemId) async {
    final token = await SecureStorage.getAccessToken();
    await _api.delete(
      '/venues/$venueId/menu/$itemId',
      headers: {'Authorization': 'Bearer $token'},
    );
    _notifyChanged();
  }
}
