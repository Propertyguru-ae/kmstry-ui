/// Model for GET /notifications list item.
/// Backend returns snake_case (is_read, created_at, dedupe_key).
class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final Map<String, dynamic>? data;
  final bool isRead;
  final DateTime createdAt;
  final String? dedupeKey;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.data,
    this.isRead = false,
    required this.createdAt,
    this.dedupeKey,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    DateTime parseCreatedAt(dynamic v) {
      if (v == null) return DateTime.now();
      if (v is DateTime) return v;
      if (v is String) {
        try {
          return DateTime.parse(v);
        } catch (_) {
          return DateTime.now();
        }
      }
      return DateTime.now();
    }

    final isReadRaw = json['is_read'] ?? json['isRead'] ?? false;
    final createdAtRaw = json['created_at'] ?? json['createdAt'];
    final dataRaw = json['data'];
    Map<String, dynamic>? dataMap;
    if (dataRaw is Map) {
      dataMap = Map<String, dynamic>.from(dataRaw as Map);
    }

    return NotificationModel(
      id: json['id'] as String,
      type: (json['type'] as String?) ?? 'unknown',
      title: (json['title'] as String?) ?? '',
      body: (json['body'] as String?) ?? '',
      data: dataMap,
      isRead: isReadRaw == true,
      createdAt: parseCreatedAt(createdAtRaw),
      dedupeKey: json['dedupe_key'] as String? ?? json['dedupeKey'] as String?,
    );
  }
}
