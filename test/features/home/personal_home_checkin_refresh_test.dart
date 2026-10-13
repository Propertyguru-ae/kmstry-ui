import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/home/presentation/personal_home_page.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _SlowStoryRepository extends StoryRepository {
  final response = Completer<List<StoryGroup>>();
  @override
  Future<List<StoryGroup>> getHomeStories() => response.future;
  @override
  Future<List<StoryItem>> getMyStories() async => [];
}

class _SlowEventRepository extends VenueEventRepository {
  final response = Completer<List<TodayEvent>>();
  @override
  Future<List<TodayEvent>> getMyTodayEvents() => response.future;
}

class _FakeCheckinRepository extends VenueCheckinRepository {
  ActiveCheckin? current;
  int calls = 0;

  @override
  Future<ActiveCheckin?> getActiveCheckin() async {
    calls++;
    return current;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'slow stories/events do not hold Home check-in controls behind loading',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues(const <String, String>{});
      SharedPreferences.setMockInitialValues(const <String, Object>{});
      final stories = _SlowStoryRepository();
      final events = _SlowEventRepository();
      final checkins = _FakeCheckinRepository()
        ..current = ActiveCheckin(
          id: 'active',
          venueId: 'venue',
          venueName: 'QA Venue',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: PersonalHomePage(
            checkinRepository: checkins,
            storyRepository: stories,
            eventRepository: events,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(stories.response.isCompleted, false);
      expect(events.response.isCompleted, false);
      expect(find.text('Active check-in'), findsOneWidget);
      expect(find.text('Stories'), findsOneWidget);
      expect(find.text('Catch the vibe'), findsNothing);
      stories.response.complete([]);
      events.response.complete([]);
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('Home responds to check-in changes without a pull', (
    tester,
  ) async {
    FlutterSecureStorage.setMockInitialValues(const <String, String>{});
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    final checkins = _FakeCheckinRepository();

    await tester.pumpWidget(
      MaterialApp(home: PersonalHomePage(checkinRepository: checkins)),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Stories'), findsOneWidget);
    expect(find.text('Active check-in'), findsNothing);
    expect(find.text('Catch the vibe'), findsOneWidget);
    expect(find.text('Share your first story here.'), findsNothing);

    checkins.current = ActiveCheckin(
      id: 'qa-checkin',
      venueId: 'qa-venue',
      venueName: 'QA Venue',
    );
    ActiveCheckinService().setActiveCheckin('qa-checkin', venueId: 'qa-venue');
    await tester.pumpAndSettle();

    expect(checkins.calls, greaterThanOrEqualTo(2));
    expect(find.text('Active check-in'), findsOneWidget);
    expect(find.text('Catch the vibe'), findsNothing);
    expect(find.byIcon(Icons.add_rounded), findsWidgets);
    expect(find.text('Share your first story here.'), findsNothing);

    checkins.current = null;
    ActiveCheckinService().clear();
    await tester.pumpAndSettle();
    expect(find.text('Active check-in'), findsNothing);
    expect(find.text('Catch the vibe'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
