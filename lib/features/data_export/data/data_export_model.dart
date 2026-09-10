enum DataExportStatus {
  pending,
  processing,
  ready,
  failed,
  expired,
  cancelled;

  static DataExportStatus parse(Object? value) {
    return DataExportStatus.values.firstWhere(
      (item) => item.name.toUpperCase() == value?.toString().toUpperCase(),
      orElse: () => DataExportStatus.failed,
    );
  }
}

enum DataExportScope {
  all,
  personal,
  venue;

  String get apiValue => name.toUpperCase();

  static DataExportScope parse(Object? value) {
    return DataExportScope.values.firstWhere(
      (item) => item.apiValue == value?.toString().toUpperCase(),
      orElse: () => DataExportScope.all,
    );
  }
}

class DataExportVenueCapability {
  const DataExportVenueCapability({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
  });

  final String id;
  final String name;
  final String role;
  final String status;

  factory DataExportVenueCapability.fromJson(Map<String, dynamic> json) =>
      DataExportVenueCapability(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Venue',
        role: json['role']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
      );
}

class DataExportCapabilities {
  const DataExportCapabilities({
    required this.hasPersonalProfile,
    required this.hasVenueProfile,
    required this.availableScopes,
    required this.venues,
    required this.requiresScopeSelection,
    required this.requiresVenueSelection,
  });

  final bool hasPersonalProfile;
  final bool hasVenueProfile;
  final List<DataExportScope> availableScopes;
  final List<DataExportVenueCapability> venues;
  final bool requiresScopeSelection;
  final bool requiresVenueSelection;

  DataExportScope get defaultScope =>
      availableScopes.isEmpty ? DataExportScope.all : availableScopes.first;

  factory DataExportCapabilities.fromJson(Map<String, dynamic> json) {
    final rawScopes = json['availableScopes'];
    final rawVenues = json['venues'];
    return DataExportCapabilities(
      hasPersonalProfile: json['hasPersonalProfile'] == true,
      hasVenueProfile: json['hasVenueProfile'] == true,
      availableScopes: rawScopes is List
          ? rawScopes.map(DataExportScope.parse).toList(growable: false)
          : const [DataExportScope.all],
      venues: rawVenues is List
          ? rawVenues
                .whereType<Map>()
                .map(
                  (venue) => DataExportVenueCapability.fromJson(
                    Map<String, dynamic>.from(venue),
                  ),
                )
                .where((venue) => venue.id.isNotEmpty)
                .toList(growable: false)
          : const [],
      requiresScopeSelection: json['requiresScopeSelection'] == true,
      requiresVenueSelection: json['requiresVenueSelection'] == true,
    );
  }
}

class DataExportRequestModel {
  const DataExportRequestModel({
    required this.id,
    required this.status,
    required this.categories,
    required this.scope,
    required this.venueIds,
    required this.requestedAt,
    required this.expiresAt,
    required this.fileSizeBytes,
    required this.canCancel,
    required this.canRetry,
  });

  final String id;
  final DataExportStatus status;
  final List<String> categories;
  final DataExportScope scope;
  final List<String> venueIds;
  final DateTime requestedAt;
  final DateTime? expiresAt;
  final int? fileSizeBytes;
  final bool canCancel;
  final bool canRetry;

  bool get includesLocation => categories.contains('LOCATION_HISTORY');
  bool get isActive =>
      status == DataExportStatus.pending ||
      status == DataExportStatus.processing;

  factory DataExportRequestModel.fromJson(Map<String, dynamic> json) {
    final rawCategories = json['categories'];
    return DataExportRequestModel(
      id: json['id']?.toString() ?? '',
      status: DataExportStatus.parse(json['status']),
      categories: rawCategories is List
          ? rawCategories.map((item) => item.toString()).toList(growable: false)
          : const [],
      scope: DataExportScope.parse(json['scope']),
      venueIds: json['venueIds'] is List
          ? (json['venueIds'] as List)
                .map((item) => item.toString())
                .toList(growable: false)
          : const [],
      requestedAt:
          DateTime.tryParse(json['requestedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      expiresAt: DateTime.tryParse(json['expiresAt']?.toString() ?? ''),
      fileSizeBytes: int.tryParse(json['fileSizeBytes']?.toString() ?? ''),
      canCancel: json['canCancel'] == true,
      canRetry: json['canRetry'] == true,
    );
  }
}

class DataExportDownload {
  const DataExportDownload({
    required this.url,
    required this.expiresAt,
    required this.filename,
    required this.fileSizeBytes,
    required this.checksumSha256,
  });

  final Uri url;
  final DateTime expiresAt;
  final String filename;
  final int fileSizeBytes;
  final String checksumSha256;

  factory DataExportDownload.fromJson(Map<String, dynamic> json) {
    final url = Uri.tryParse(json['url']?.toString() ?? '');
    final expiresAt = DateTime.tryParse(json['expiresAt']?.toString() ?? '');
    final size = int.tryParse(json['fileSizeBytes']?.toString() ?? '');
    final checksum = json['checksumSha256']?.toString() ?? '';
    final ownedStorageHost =
        url != null &&
        (url.host == 'digitaloceanspaces.com' ||
            url.host.endsWith('.digitaloceanspaces.com'));
    if (url == null ||
        url.scheme != 'https' ||
        !ownedStorageHost ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        expiresAt == null ||
        size == null ||
        size < 1 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(checksum)) {
      throw const FormatException('Invalid data export download response');
    }
    return DataExportDownload(
      url: url,
      expiresAt: expiresAt,
      filename: json['filename']?.toString() ?? 'kmstry-data-export.zip',
      fileSizeBytes: size,
      checksumSha256: checksum,
    );
  }
}
