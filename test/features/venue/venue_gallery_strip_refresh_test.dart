import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_gallery_section.dart';

class _FakeGalleryRepository extends VenueGalleryRepository {
  List<VenueGalleryItem> items = const [
    VenueGalleryItem(id: 'removed-media', url: '', mediaType: 'video'),
  ];
  int calls = 0;

  @override
  Future<List<VenueGalleryItem>> getGallery(String venueId) async {
    calls++;
    return items;
  }
}

void main() {
  testWidgets('venue gallery reloads after a detail-page refresh', (
    tester,
  ) async {
    final repository = _FakeGalleryRepository();
    final counts = <int>[];

    Widget page(int refreshEpoch) => MaterialApp(
      home: Scaffold(
        body: VenueGalleryStrip(
          venueId: 'qa-venue',
          refreshEpoch: refreshEpoch,
          repository: repository,
          onCountChanged: counts.add,
        ),
      ),
    );

    await tester.pumpWidget(page(0));
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(counts.last, 1);
    expect(find.byIcon(Icons.play_circle_fill), findsOneWidget);

    repository.items = const [];
    await tester.pumpWidget(page(1));
    await tester.pumpAndSettle();

    expect(repository.calls, 2);
    expect(counts.last, 0);
    expect(find.byIcon(Icons.play_circle_fill), findsNothing);
  });
}
