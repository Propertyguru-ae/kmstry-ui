import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
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

  testWidgets('another user sees text in the check-in moments viewer', (tester) async {
    await tester.pumpWidget(MaterialApp(
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
    ));
    await tester.pump();
    expect(find.byType(MediaTextOverlayView), findsOneWidget);
    expect(find.text(overlay['text'] as String), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
