import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/home/presentation/personal_home_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';

class _Api extends ApiClient {
  bool fail = false;
  Future<dynamic> _write(bool following) async {
    if (fail) throw StateError('offline');
    return {'ok': true, 'isFollowing': following, 'followerCount': 2};
  }

  @override
  Future<dynamic> post(
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? headers,
  }) => _write(true);
  @override
  Future<dynamic> delete(String path, {Map<String, String>? headers}) =>
      _write(false);
}

class _Context extends VenueContextRepository {
  _Context(_Api api) : super(apiClient: api);
  final reads = <Completer<List<Venue>>>[];
  @override
  Future<List<Venue>> getFollowedVenues() {
    final read = Completer<List<Venue>>();
    reads.add(read);
    return read.future;
  }
}

class _Checks extends VenueCheckinRepository {
  int calls = 0;
  @override
  Future<ActiveCheckin?> getActiveCheckin() async {
    calls++;
    return null;
  }
}

class _Stories extends StoryRepository {
  final reads = <Completer<List<StoryGroup>>>[];
  int ownCalls = 0;
  @override
  Future<List<StoryGroup>> getHomeStories() {
    final read = Completer<List<StoryGroup>>();
    reads.add(read);
    return read.future;
  }

  @override
  Future<List<StoryItem>> getMyStories() async {
    ownCalls++;
    return [];
  }
}

class _Events extends VenueEventRepository {
  final followedReads = <Completer<List<TodayEvent>>>[];
  final nearbyReads = <Completer<List<TodayEvent>>>[];
  List<TodayEvent> saved = [];
  int todayCalls = 0;
  @override
  Future<List<TodayEvent>> getMyTodayEvents() async {
    todayCalls++;
    return saved;
  }

  @override
  Future<List<TodayEvent>> getFollowedVenuesEvents({int limit = 20}) {
    final read = Completer<List<TodayEvent>>();
    followedReads.add(read);
    return read.future;
  }

  @override
  Future<List<TodayEvent>> getDiscoverEvents({
    double? latitude,
    double? longitude,
    int limit = 20,
    int offset = 0,
    String? platform,
    String? when,
    DateTime? from,
    DateTime? to,
    String? scope,
  }) {
    final read = Completer<List<TodayEvent>>();
    nearbyReads.add(read);
    return read.future;
  }
}

TodayEvent _event(String venue, {String? title}) {
  final start = DateTime.now().add(const Duration(hours: 4));
  return TodayEvent(
    event: VenueUpcomingEvent(
      id: title ?? venue,
      title: title ?? '$venue event',
      startAt: start,
      endAt: start.add(const Duration(hours: 1)),
      description: 'Full event details',
    ),
    venueId: venue,
    venueName: 'Venue $venue',
  );
}

StoryGroup _story(String id, {bool venue = true}) => StoryGroup(
  user: StoryUser(id: id, fullName: venue ? '$id story' : 'Friend story'),
  venueLabel: venue ? '$id story' : null,
  stories: [
    StoryItem(
      id: 'story-$id-$venue',
      mediaUrl: '',
      mediaType: 'photo',
      venueId: 'alpha',
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    ),
  ],
);

Venue _venue(String id) => Venue.fromJson({'id': id, 'name': 'Venue $id'});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Api api;
  late _Context context;
  late _Checks checks;
  late _Stories stories;
  late _Events events;
  const permissionChannel = MethodChannel(
    'flutter.baseflow.com/permissions/methods',
  );
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({'access_token': 'test-user'});
    SharedPreferences.setMockInitialValues({});
    PendingPublicMediaService.instance.clear();
    VenueContextRepository.followChanges.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, (_) async => 0);
    api = _Api();
    context = _Context(api);
    checks = _Checks();
    stories = _Stories();
    events = _Events();
  });
  tearDown(() {
    PendingPublicMediaService.instance.clear();
    VenueContextRepository.followChanges.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(permissionChannel, null);
  });

  Future<void> openHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: PersonalHomePage(
          checkinRepository: checks,
          storyRepository: stories,
          eventRepository: events,
          venueContextRepository: context,
          isActive: false,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(stories.reads, hasLength(1));
    expect(events.followedReads, hasLength(1));
    expect(events.nearbyReads, hasLength(1));
  }

  Future<void> seed(
    WidgetTester tester, {
    List<StoryGroup> groups = const [],
    List<TodayEvent> followed = const [],
    List<TodayEvent> nearby = const [],
    List<Venue> follows = const [],
  }) async {
    stories.reads.first.complete(groups);
    events.followedReads.first.complete(followed);
    events.nearbyReads.first.complete(nearby);
    await tester.pumpAndSettle();
    if (context.reads.isNotEmpty) {
      context.reads.first.complete(follows);
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
  }

  Finder sectionEvent(String section, String title) => find.descendant(
    of: find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == section,
    ),
    matching: find.text(title),
  );

  void expectOnlyFollowSectionsRefreshed({int reads = 2}) {
    expect(stories.reads, hasLength(reads));
    expect(events.followedReads, hasLength(reads));
    expect(events.nearbyReads, hasLength(reads));
    expect(checks.calls, 1);
    expect(stories.ownCalls, 1);
    expect(events.todayCalls, 1);
  }

  testWidgets(
    'follow immediately moves known nearby events and refreshes venue stories on retained Home',
    (tester) async {
      final alpha = _event('alpha');
      final beta = _event('beta');
      await openHome(tester);
      await seed(
        tester,
        groups: [_story('beta')],
        followed: [beta],
        nearby: [alpha],
      );
      await context.followVenue('alpha');
      await tester.pumpAndSettle();
      expectOnlyFollowSectionsRefreshed();
      expect(
        sectionEvent('_DiscoverEventsList', alpha.event.title),
        findsNothing,
      );
      expect(
        sectionEvent('_FollowedEventsRow', alpha.event.title),
        findsOneWidget,
      );
      expect(find.text('beta story'), findsOneWidget);
      stories.reads.last.complete([_story('alpha'), _story('beta')]);
      events.followedReads.last.complete([alpha, beta]);
      events.nearbyReads.last.complete([]);
      await tester.pumpAndSettle();
      expect(find.text('alpha story'), findsOneWidget);
      expect(find.text(alpha.event.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'unfollow removes only the venue story and followed events immediately, preserving friends and saved events',
    (tester) async {
      final alpha = _event('alpha');
      final beta = _event('beta');
      events.saved = [_event('alpha', title: 'Saved Alpha today')];
      await openHome(tester);
      await seed(
        tester,
        groups: [
          _story('alpha'),
          _story('beta'),
          _story('alpha', venue: false),
        ],
        followed: [alpha, beta],
      );
      await context.unfollowVenue('alpha');
      await tester.pumpAndSettle();
      expectOnlyFollowSectionsRefreshed();
      expect(find.text('alpha story'), findsNothing);
      expect(find.text('beta story'), findsOneWidget);
      expect(find.text('Friend story'), findsOneWidget);
      expect(find.text(alpha.event.title), findsNothing);
      expect(find.text(beta.event.title), findsOneWidget);
      expect(find.text('Saved Alpha today'), findsOneWidget);
      stories.reads.last.complete([
        _story('beta'),
        _story('alpha', venue: false),
      ]);
      events.followedReads.last.complete([beta]);
      events.nearbyReads.last.complete([alpha]);
      await tester.pumpAndSettle();
      expect(
        sectionEvent('_DiscoverEventsList', alpha.event.title),
        findsOneWidget,
      );
      expect(
        sectionEvent('_FollowedEventsRow', alpha.event.title),
        findsNothing,
      );
      expect(find.text('Saved Alpha today'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'rapid follow then unfollow ignores the earlier follow-dependent responses',
    (tester) async {
      final alpha = _event('alpha');
      final beta = _event('beta');
      await openHome(tester);
      await seed(
        tester,
        groups: [_story('beta')],
        followed: [beta],
        nearby: [alpha],
      );
      await context.followVenue('alpha');
      await context.unfollowVenue('alpha');
      await tester.pumpAndSettle();
      expectOnlyFollowSectionsRefreshed(reads: 3);
      stories.reads[1].complete([_story('alpha'), _story('beta')]);
      events.followedReads[1].complete([alpha, beta]);
      events.nearbyReads[1].complete([_event('wrong-old-response')]);
      await tester.pumpAndSettle();
      expect(find.text('alpha story'), findsNothing);
      expect(find.text(alpha.event.title), findsNothing);
      expect(find.text('wrong-old-response event'), findsNothing);
      stories.reads.last.complete([_story('beta')]);
      events.followedReads.last.complete([beta]);
      events.nearbyReads.last.complete([alpha]);
      await tester.pumpAndSettle();
      expect(
        sectionEvent('_DiscoverEventsList', alpha.event.title),
        findsOneWidget,
      );
      expect(
        sectionEvent('_FollowedEventsRow', alpha.event.title),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed follow does not remove nearby events or refresh Home', (
    tester,
  ) async {
    final alpha = _event('alpha');
    await openHome(tester);
    await seed(tester, nearby: [alpha]);
    api.fail = true;
    await expectLater(context.followVenue('alpha'), throwsStateError);
    await tester.pumpAndSettle();
    expectOnlyFollowSectionsRefreshed(reads: 1);
    expect(
      sectionEvent('_DiscoverEventsList', alpha.event.title),
      findsOneWidget,
    );
    expect(VenueContextRepository.followChanges.value, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'unfollowing the last known venue immediately updates the empty-state message',
    (tester) async {
      await openHome(tester);
      await seed(tester, follows: [_venue('alpha')]);
      expect(
        find.text('No upcoming events at the venues you follow.'),
        findsOneWidget,
      );
      await context.unfollowVenue('alpha');
      await tester.pumpAndSettle();
      expect(
        find.text("Follow your favorite spots and never miss what's next."),
        findsOneWidget,
      );
      stories.reads.last.complete([]);
      events.followedReads.last.complete([]);
      events.nearbyReads.last.complete([]);
      await tester.pumpAndSettle();
      context.reads.last.complete([]);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'an older followed-venues empty check cannot undo a confirmed follow',
    (tester) async {
      await openHome(tester);
      stories.reads.first.complete([]);
      events.followedReads.first.complete([]);
      events.nearbyReads.first.complete([]);
      await tester.pumpAndSettle();
      expect(context.reads, hasLength(1));
      await context.followVenue('alpha');
      context.reads.first.complete([]);
      await tester.pumpAndSettle();
      expect(
        find.text('No upcoming events at the venues you follow.'),
        findsOneWidget,
      );
      expect(
        find.text("Follow your favorite spots and never miss what's next."),
        findsNothing,
      );
      stories.reads.last.complete([]);
      events.followedReads.last.complete([]);
      events.nearbyReads.last.complete([]);
      await tester.pumpAndSettle();
      context.reads.last.complete([_venue('alpha')]);
      await tester.pumpAndSettle();
      expect(
        find.text('No upcoming events at the venues you follow.'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'late reads and follow signals from another login do not change Home',
    (tester) async {
      final beta = _event('beta');
      await openHome(tester);
      await seed(tester, groups: [_story('beta')], followed: [beta]);
      await context.followVenue('alpha');
      await tester.pumpAndSettle();
      final oldSession = PendingPublicMediaService.instance.sessionGeneration;
      PendingPublicMediaService.instance.clear();
      VenueContextRepository.followChanges.value = VenueFollowChange(
        venueId: 'beta',
        following: false,
        session: oldSession,
      );
      stories.reads.last.complete([_story('alpha')]);
      events.followedReads.last.complete([_event('alpha')]);
      events.nearbyReads.last.complete([_event('wrong-login')]);
      await tester.pumpAndSettle();
      expectOnlyFollowSectionsRefreshed();
      expect(find.text('beta story'), findsOneWidget);
      expect(find.text(beta.event.title), findsOneWidget);
      expect(find.text('alpha story'), findsNothing);
      expect(find.text('alpha event'), findsNothing);
      expect(find.text('wrong-login event'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'disposed Home ignores late reads and removes its follow listener',
    (tester) async {
      await openHome(tester);
      await tester.pumpWidget(const SizedBox.shrink());
      stories.reads.first.complete([_story('alpha')]);
      events.followedReads.first.complete([_event('alpha')]);
      events.nearbyReads.first.complete([_event('beta')]);
      await context.followVenue('alpha');
      await tester.pumpAndSettle();
      expectOnlyFollowSectionsRefreshed(reads: 1);
      expect(tester.takeException(), isNull);
    },
  );
}
