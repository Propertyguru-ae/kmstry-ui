import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';

class _Access extends VenueMemberRepository {
  _Access(this.permissions);
  List<VenuePermission> permissions;
  @override
  Future<MyVenueAccess> getMyPermissions(String venueId) async => MyVenueAccess(
    permissions: permissions,
    plan: VenuePlan.free,
    planUntil: null,
    features: {},
  );
}

final _viewers = <Map<String, dynamic>>[
  {
    'story_id': 'story',
    'view_count': 7,
    'viewers': [
      {
        'user': {'id': 'guest', 'full_name': 'Test Guest'},
      },
    ],
  },
];

class _Stories extends VenueStoryRepository {
  int calls = 0;
  Future<List<Map<String, dynamic>>> Function(int)? read;
  @override
  Future<List<Map<String, dynamic>>> getViewers(String venueId) {
    calls++;
    return read?.call(calls) ?? Future.value(_viewers);
  }
}

Future<void> _open(
  WidgetTester tester,
  _Stories repo, {
  required bool allowed,
  bool serverAllowed = true,
  VenueSession? session,
}) async {
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
  await tester.pumpWidget(
    MaterialApp(
      home: StoryViewerPage(
        groups: [
          StoryGroup(
            user: const StoryUser(id: 'venue'),
            stories: [
              StoryItem(
                id: 'story',
                mediaUrl: '',
                mediaType: 'photo',
                expiresAt: DateTime(2030),
                createdAt: DateTime(2026),
                isVenueStory: true,
                venueId: 'venue',
                viewCount: 7,
                canViewStats: serverAllowed,
              ),
            ],
          ),
        ],
        venueId: 'venue',
        showViewers: allowed,
        isManagedVenueContent: true,
        venueStoryRepository: repo,
        venueSession: session,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({});
    VenueSession.instance.clear();
  });

  test(
    'stats access requires loaded matching venue and explicit permission',
    () async {
      final repo = _Access([VenuePermission.storyManage]);
      final session = VenueSession.forTest(repository: repo);
      expect(session.canViewStoryStats('venue'), false);
      await session.load('venue', VenueMemberRole.admin);
      expect(session.canViewStoryStats('venue'), false);
      repo.permissions = [VenuePermission.storyViewStats];
      await session.retry();
      expect(session.canViewStoryStats('venue'), true);
      expect(session.canViewStoryStats('other'), false);
      repo.permissions = [];
      await session.retry();
      expect(session.canViewStoryStats('venue'), false);
      // Stale owner context does not override a server-denied membership.
      await session.load('venue', VenueMemberRole.owner);
      expect(session.canViewStoryStats('venue'), false);
      repo.permissions = VenuePermission.values;
      await session.retry();
      expect(session.canViewStoryStats('venue'), true);
      session.clear();
      expect(session.canViewStoryStats('venue'), false);
    },
  );

  test('server permission is explicit and survives copying a viewed story', () {
    final json = <String, dynamic>{
      'id': 'story',
      'media_url': '',
      'media_type': 'photo',
      'created_at': '2026-10-13',
      'expires_at': '2030-01-01',
      'view_count': 7,
    };
    expect(VenueStoryItem.fromJson(json).canViewStats, false);
    json['can_view_stats'] = true;
    expect(
      VenueStoryItem.fromJson(json).copyWith(viewedByMe: true).canViewStats,
      true,
    );
  });

  for (final allowed in [false, true]) {
    for (final serverAllowed in [false, true]) {
      testWidgets(
        'eye and count require both permissions: local=$allowed server=$serverAllowed',
        (tester) async {
          final repo = _Stories();
          await _open(
            tester,
            repo,
            allowed: allowed,
            serverAllowed: serverAllowed,
          );
          final visible = allowed && serverAllowed;
          expect(
            find.byIcon(Icons.remove_red_eye_outlined),
            visible ? findsOneWidget : findsNothing,
          );
          expect(find.text('7'), visible ? findsOneWidget : findsNothing);
          expect(repo.calls, visible ? 1 : 0);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets('authorized team member opens the viewer list', (tester) async {
    final repo = _Stories();
    await _open(tester, repo, allowed: true);
    await tester.tap(find.byIcon(Icons.remove_red_eye_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('Test Guest'), findsOneWidget);
    expect(repo.calls, 2);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('403 during prefetch hides statistics, without an error popup', (
    tester,
  ) async {
    final repo = _Stories()
      ..read = (_) async => throw ApiException(
        statusCode: 403,
        data: {'message': 'Access denied'},
      );
    await _open(tester, repo, allowed: true);
    await tester.pump();
    expect(find.byIcon(Icons.remove_red_eye_outlined), findsNothing);
    expect(find.textContaining('Access denied'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('403 opening the list closes it and removes the eye/count', (
    tester,
  ) async {
    final repo = _Stories()
      ..read = (call) async {
        if (call > 1) {
          throw ApiException(
            statusCode: 403,
            data: {'message': 'Access denied'},
          );
        }
        return _viewers;
      };
    await _open(tester, repo, allowed: true);
    await tester.tap(find.byIcon(Icons.remove_red_eye_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byIcon(Icons.remove_red_eye_outlined), findsNothing);
    expect(find.textContaining('Access denied'), findsNothing);
    expect(find.byType(StoryViewerPage), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('account switch closes the sheet and ignores its late response', (
    tester,
  ) async {
    final session = VenueSession.forTest(
      repository: _Access([VenuePermission.storyViewStats]),
    );
    await session.load('venue', VenueMemberRole.staff);
    final lateResponse = Completer<List<Map<String, dynamic>>>();
    final repo = _Stories()
      ..read = (call) =>
          call == 1 ? Future.value(_viewers) : lateResponse.future;
    await _open(tester, repo, allowed: true, session: session);
    await tester.tap(find.byIcon(Icons.remove_red_eye_outlined));
    await tester.pump(const Duration(milliseconds: 400));
    session.clear();
    lateResponse.complete(_viewers);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Test Guest'), findsNothing);
    expect(find.byIcon(Icons.remove_red_eye_outlined), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
