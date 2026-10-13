import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

StoryItem _story(String id, {bool placeholder = false}) => StoryItem(
  id: id,
  mediaUrl: 'https://example.test/$id.jpg',
  mediaType: 'photo',
  expiresAt: DateTime.now().add(const Duration(hours: 3)),
  createdAt: DateTime.now(),
  isUploadingPlaceholder: placeholder,
);

StoryGroup _group(String userId, List<StoryItem> stories) => StoryGroup(
  user: StoryUser(id: userId),
  stories: stories,
);

void main() {
  test('picks only the viewed profile user\'s stories from the venue', () {
    final groups = [
      _group('alice', [_story('a1')]),
      _group('bob', [_story('b1'), _story('b2')]),
    ];

    final match = profileStoryGroupFor(groups, 'bob');

    expect(match, isNotNull);
    expect(match!.user.id, 'bob');
    expect(match.stories.map((s) => s.id), ['b1', 'b2']);
  });

  test('no ring when the user has no story at the venue', () {
    final groups = [
      _group('alice', [_story('a1')]),
    ];
    expect(profileStoryGroupFor(groups, 'bob'), isNull);
    expect(profileStoryGroupFor(const [], 'bob'), isNull);
  });

  test('uploading placeholders are never shown as a story', () {
    final onlyUploading = [
      _group('bob', [_story('__uploading__', placeholder: true)]),
    ];
    expect(profileStoryGroupFor(onlyUploading, 'bob'), isNull);

    final mixed = [
      _group('bob', [_story('b1'), _story('__uploading__', placeholder: true)]),
    ];
    expect(profileStoryGroupFor(mixed, 'bob')!.stories.map((s) => s.id), [
      'b1',
    ]);
  });
}
