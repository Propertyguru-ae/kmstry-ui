import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_stats_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

void main() {
  const overlay = {
    'text': 'Hello from the cafe',
    'color': 0xFFFFFFFF,
    'fontSizeNorm': 0.07,
    'xNorm': 0.5,
    'yNorm': 0.5,
  };

  test('check-in text survives parsing and featured status updates', () {
    final media = CheckinProfileMedia.fromJson({
      'id': 'media-1',
      'url': '',
      'media_type': 'video',
      'text_overlay': overlay,
    });
    expect(media.textOverlay?.text, overlay['text']);
    expect(media.copyWith(isFeatured: true).textOverlay, media.textOverlay);
  });

  test('old media without text continues to parse', () {
    final media = CheckinProfileMedia.fromJson({'id': 'old', 'url': ''});
    expect(media.textOverlay, isNull);
  });

  test('venue guest story preserves text for the shared story viewer', () {
    final guest = VenueActiveGuest.fromJson({
      'id': 'guest',
      'stories': [
        {'id': 'story', 'mediaUrl': '', 'textOverlay': overlay},
      ],
    });
    expect(guest.stories.single.textOverlay?.text, overlay['text']);
  });

  testWidgets('another user sees text in the check-in moments viewer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MomentsViewerPage(
          initialIndex: 0,
          allowFeature: false,
          media: [
            CheckinProfileMedia.fromJson({
              'id': 'media-1',
              'url': '',
              'media_type': 'photo',
              'text_overlay': overlay,
            }),
          ],
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(MediaTextOverlayView), findsOneWidget);
    expect(find.text(overlay['text'] as String), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('warns before deleting the last Moment', (tester) async {
    final repository = _FakeCheckinRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: MomentsViewerPage(
          initialIndex: 0,
          allowFeature: true,
          repository: repository,
          media: [
            CheckinProfileMedia(
              id: 'last-moment',
              url: '',
              mediaType: MediaType.photo,
              isFeatured: true,
            ),
          ],
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Delete your last moment?'), findsOneWidget);
    expect(
      find.text(
        'Your check-in stays active only while you have at least one moment. '
        'Deleting this will end your check-in.',
      ),
      findsOneWidget,
    );
    expect(find.text('Delete & end check-in'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repository.deleteCalls, 0);
  });
}

class _FakeCheckinRepository extends CheckinRepository {
  int deleteCalls = 0;

  @override
  Future<bool> deletePhoto(String photoId) async {
    deleteCalls++;
    return true;
  }
}
