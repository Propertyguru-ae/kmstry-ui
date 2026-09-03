import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/data_export/data/data_export_model.dart';

abstract interface class DataExportTransport {
  Future<dynamic> get(String path, {Map<String, String>? headers});
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  });
  Future<dynamic> delete(String path, {Map<String, String>? headers});
}

class ApiClientDataExportTransport implements DataExportTransport {
  ApiClientDataExportTransport([ApiClient? client])
    : _client = client ?? ApiClient();
  final ApiClient _client;

  @override
  Future<dynamic> get(String path, {Map<String, String>? headers}) =>
      _client.get(path, headers: headers);

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => _client.post(path, body: body, headers: headers);

  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _client.delete(path, headers: headers);
}

class DataExportRepository {
  DataExportRepository({
    DataExportTransport? transport,
    Future<String?> Function()? tokenProvider,
    Future<String> Function()? timezoneProvider,
  }) : _transport = transport ?? ApiClientDataExportTransport(),
       _tokenProvider = tokenProvider ?? SecureStorage.getAccessToken,
       _timezoneProvider = timezoneProvider ?? _deviceTimezone;

  final DataExportTransport _transport;
  final Future<String?> Function() _tokenProvider;
  final Future<String> Function() _timezoneProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) throw Exception('Not authenticated');
    return {'Authorization': 'Bearer $token'};
  }

  Future<List<DataExportRequestModel>> list() async {
    final response = await _transport.get(
      '/users/me/data-exports?page=1&limit=20',
      headers: await _headers(),
    );
    final map = _asMap(response);
    final rawItems = map['items'];
    if (rawItems is! List) return const [];
    return rawItems
        .whereType<Map>()
        .map(
          (item) =>
              DataExportRequestModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<DataExportCapabilities> capabilities() async {
    final response = await _transport.get(
      '/users/me/data-exports/capabilities',
      headers: await _headers(),
    );
    return DataExportCapabilities.fromJson(_asMap(response));
  }

  Future<DataExportRequestModel> create({
    required Set<String> categories,
    required DataExportScope scope,
    required Set<String> venueIds,
    required String mediaQuality,
    DateTime? dateFrom,
    DateTime? dateTo,
  }) async {
    if ((dateFrom == null) != (dateTo == null)) {
      throw ArgumentError('Both export dates are required');
    }
    final timezone = await _timezoneProvider();
    final response = await _transport.post(
      '/users/me/data-exports',
      headers: await _headers(),
      body: {
        'categories': categories.toList()..sort(),
        'scope': scope.apiValue,
        if (scope == DataExportScope.venue)
          'venueIds': venueIds.toList()..sort(),
        'timezone': timezone,
        'format': 'JSON',
        'mediaQuality': mediaQuality,
        if (dateFrom != null) 'dateFrom': dateFrom.toUtc().toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toUtc().toIso8601String(),
      },
    );
    return DataExportRequestModel.fromJson(_asMap(response));
  }

  static Future<String> _deviceTimezone() async {
    try {
      return (await FlutterTimezone.getLocalTimezone()).identifier;
    } catch (_) {
      return 'UTC';
    }
  }

  Future<void> cancel(String id) async {
    await _transport.delete(
      '/users/me/data-exports/${Uri.encodeComponent(id)}',
      headers: await _headers(),
    );
  }

  Future<DataExportRequestModel> retry(String id) async {
    final response = await _transport.post(
      '/users/me/data-exports/${Uri.encodeComponent(id)}/retry',
      headers: await _headers(),
    );
    return DataExportRequestModel.fromJson(_asMap(response));
  }

  Future<DataExportDownload> createDownload(String id) async {
    final response = await _transport.post(
      '/users/me/data-exports/${Uri.encodeComponent(id)}/download',
      headers: await _headers(),
    );
    return DataExportDownload.fromJson(_asMap(response));
  }

  Map<String, dynamic> _asMap(dynamic response) {
    if (response is Map<String, dynamic>) return response;
    if (response is Map) return Map<String, dynamic>.from(response);
    throw const FormatException('Invalid data export response');
  }
}
