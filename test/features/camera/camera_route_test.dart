import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_route.dart';
import 'package:kmstry_frontend/features/venue_stories/presentation/add_venue_story_page.dart';

void main() {
  test('venue story coordinator does not animate before opening the camera', () {
    final route = AddVenueStoryPage.route('qa-venue') as PageRouteBuilder<bool>;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(route.opaque, isFalse);
  });

  testWidgets('camera opens without a sideways page transition', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(platform: TargetPlatform.iOS),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.push<void>(
                  context,
                  cameraRoute<void>(
                    builder: (_) => const Scaffold(
                      body: Center(child: Text('Camera preview')),
                    ),
                  ),
                ),
                child: const Text('Open camera'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open camera'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final slide = tester.widget<SlideTransition>(
      find.ancestor(
        of: find.text('Camera preview'),
        matching: find.byType(SlideTransition),
      ).first,
    );
    expect(slide.position.value.dx, 0);
    expect(slide.position.value.dy, greaterThan(0));

    await tester.pumpAndSettle();
    expect(find.text('Camera preview'), findsOneWidget);
  });
}
