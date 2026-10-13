import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/content_moderation_item.dart';

void main() {
  test('keeps the historical approval separate from paused publication', () {
    final item = ContentModerationItem.fromJson({
      'status': 'APPROVED',
      'media_type': 'VIDEO',
      'publication_disabled': true,
    });
    expect(item.status, 'APPROVED');
    expect(item.moderationSnapshot.publicationDisabled, true);
    expect(ContentModerationItem.fromJson({}).publicationDisabled, false);
  });

  test('parses the safe user moderation response', () {
    final result = ContentModerationPageResult.fromJson({
      'data': [
        {
          'id': 'moderation-1',
          'target_type': 'VENUE_GALLERY',
          'target_id': 'gallery-1',
          'media_type': 'IMAGE',
          'status': 'REJECTED',
          'reason_code': 'PERSONAL_INFORMATION',
          'user_message': 'This upload may expose personal information.',
          'created_at': '2026-09-28T08:00:00.000Z',
          'updated_at': '2026-09-28T08:02:00.000Z',
        },
      ],
      'total': 1,
      'page': 1,
      'limit': 20,
    });

    expect(result.total, 1);
    expect(result.items, hasLength(1));
    expect(result.items.single.status, 'REJECTED');
    expect(result.items.single.targetType, 'VENUE_GALLERY');
    expect(result.items.single.reasonCode, 'PERSONAL_INFORMATION');
    expect(result.items.single.updatedAt, isNotNull);
    expect(result.items.single.processingIssue, isFalse);
  });

  test(
    'parses the safe provider issue flag without guessing from reason text',
    () {
      final item = ContentModerationItem.fromJson({
        'status': 'NEEDS_REVIEW',
        'processing_issue': true,
      });
      expect(item.moderationSnapshot.processingIssue, isTrue);
      expect(item.moderationSnapshot.status, 'NEEDS_REVIEW');
      expect(item.reasonCode, isNull);
    },
  );

  test('uses safe defaults for a malformed optional payload', () {
    final result = ContentModerationPageResult.fromJson({'data': const []});

    expect(result.items, isEmpty);
    expect(result.total, 0);
    expect(result.page, 1);
    expect(result.limit, 20);
  });
}
