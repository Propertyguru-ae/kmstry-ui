import 'package:kmstry_frontend/features/content_moderation/data/public_media_upload_state.dart';

class ContentModerationItem {
  const ContentModerationItem({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.mediaType,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.reasonCode,
    this.userMessage,
    this.processingIssue = false,
    this.photoPublication,
    this.publicationDisabled = false,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String mediaType;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? reasonCode;
  final String? userMessage;
  final bool processingIssue;
  final String? photoPublication;
  final bool publicationDisabled;

  MediaModerationSnapshot get moderationSnapshot => MediaModerationSnapshot(
    status: status,
    message: userMessage,
    processingIssue: processingIssue,
    photoPublication: photoPublication,
    publicationDisabled: publicationDisabled,
  );

  factory ContentModerationItem.fromJson(Map<String, dynamic> json) {
    return ContentModerationItem(
      id: json['id']?.toString() ?? '',
      targetType: json['target_type']?.toString() ?? '',
      targetId: json['target_id']?.toString() ?? '',
      mediaType: json['media_type']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      reasonCode: json['reason_code']?.toString(),
      userMessage: json['user_message']?.toString(),
      processingIssue: json['processing_issue'] == true,
      photoPublication: json['photo_publication']?.toString(),
      publicationDisabled: json['publication_disabled'] == true,
    );
  }
}

class ContentModerationPageResult {
  const ContentModerationPageResult({
    required this.items,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<ContentModerationItem> items;
  final int total;
  final int page;
  final int limit;

  factory ContentModerationPageResult.fromJson(Map<String, dynamic> json) {
    final rawItems = json['data'];
    return ContentModerationPageResult(
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map(
                  (item) => ContentModerationItem.fromJson(
                    Map<String, dynamic>.from(item),
                  ),
                )
                .toList(growable: false)
          : const [],
      total: (json['total'] as num?)?.toInt() ?? 0,
      page: (json['page'] as num?)?.toInt() ?? 1,
      limit: (json['limit'] as num?)?.toInt() ?? 20,
    );
  }
}
