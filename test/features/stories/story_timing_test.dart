import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_display_timer.dart';
import 'package:kmstry_frontend/features/media/media_text_overlay.dart';

StoryItem story(String id, {bool video = false}) => StoryItem(
  id: id,
  mediaUrl: '',
  mediaType: video ? 'video' : 'photo',
  createdAt: DateTime(2026),
  expiresAt: DateTime(2030),
  textOverlay: MediaTextOverlay(
    text: id,
    colorValue: 0xFFFFFFFF,
    fontSizeNorm: 0.07,
  ),
);

Future<void> openStories(WidgetTester tester, {bool video = false}) async {
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    MaterialApp(
      home: StoryViewerPage(
        groups: [
          StoryGroup(
            user: const StoryUser(id: 'test-author'),
            stories: [
              story('first', video: video),
              story('second'),
              story('third'),
            ],
          ),
        ],
      ),
    ),
  );
}

void main() {
  for (final reduced in [false, true]) {
    testWidgets('photo stays five seconds with reduce animations=$reduced', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: reduced);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openStories(tester);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('first'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 4699));
      expect(find.text('first'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 1));
      expect(find.text('second'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'visual completion and a mid-story reduced-motion change cannot advance content',
    (tester) async {
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await openStories(tester);
      final progress = tester
          .widgetList<AnimatedBuilder>(find.byType(AnimatedBuilder))
          .map((w) => w.animation)
          .whereType<AnimationController>()
          .singleWhere((c) => c.duration == const Duration(seconds: 5));
      progress.value = 1;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('first'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('second'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('unavailable video fallback also waits five seconds', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openStories(tester, video: true);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('second'), findsNothing);
    await tester.pump(const Duration(milliseconds: 4700));
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('holding pauses content even with animations disabled', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await openStories(tester);
    final gesture = await tester.startGesture(const Offset(650, 300));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('first'), findsOneWidget);
    // Cancellation resumes without invoking the short-tap navigation action.
    await gesture.cancel();
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('second'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('manual next cancels the previous story deadline', (
    tester,
  ) async {
    await openStories(tester);
    await tester.pump(const Duration(seconds: 2));
    await tester.tapAt(const Offset(650, 300));
    await tester.pump();
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('third'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'backgrounding pauses content and disposal cancels pending advance',
    (tester) async {
      await openStories(tester);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('first'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 10));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('content clock preserves remaining time across repeated pauses', (
    tester,
  ) async {
    final epoch = tester.binding.clock.now();
    var completed = 0;
    final timer = StoryDisplayTimer(
      duration: const Duration(seconds: 5),
      onComplete: () => completed++,
      elapsedClock: () => tester.binding.clock.now().difference(epoch),
    );
    timer.resume();
    timer.resume();
    await tester.pump(const Duration(seconds: 2));
    timer.pause();
    timer.pause();
    await tester.pump(const Duration(seconds: 20));
    expect(completed, 0);
    timer.resume();
    await tester.pump(const Duration(seconds: 1));
    timer.pause();
    await tester.pump(const Duration(seconds: 20));
    timer.resume();
    await tester.pump(const Duration(milliseconds: 1999));
    expect(completed, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(completed, 1);
    timer.resume();
    await tester.pump(const Duration(seconds: 5));
    expect(completed, 1);
    timer.dispose();
  });
}
