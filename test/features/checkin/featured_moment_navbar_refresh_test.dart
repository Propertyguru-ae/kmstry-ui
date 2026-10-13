import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

class _Repo extends CheckinRepository {
  final featured = <String>[];
  @override
  Future<void> setFeaturedPhoto(String photoId) async => featured.add(photoId);
}

class _DelayedRepo extends CheckinRepository {
  final result = Completer<void>();
  @override
  Future<void> setFeaturedPhoto(String photoId) => result.future;
}

void main() {
  for (final changeSession in [false, true]) {
    testWidgets(
      'feature result after viewer closes; session changed=$changeSession',
      (tester) async {
        final uploads = PendingPublicMediaService.forTest(
          publishedLookup: (_) async => false,
          moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
          delay: (_) => Completer<void>().future,
        );
        addTearDown(uploads.clear);
        final active = ActiveCheckinService();
        active.setActiveCheckin('checkin', userId: 'me');
        addTearDown(active.clear);
        final repo = _DelayedRepo();
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MomentsViewerPage(
                      initialIndex: 0,
                      allowFeature: true,
                      checkinId: 'checkin',
                      repository: repo,
                      uploads: uploads,
                      media: [
                        CheckinProfileMedia(
                          id: 'photo-b',
                          url: '',
                          mediaType: MediaType.photo,
                          isFeatured: false,
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.star_border_rounded));
        await tester.pump();
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        if (changeSession) {
          uploads.clear();
          active.setActiveCheckin('new-account-checkin', userId: 'other');
        }
        repo.result.complete();
        await tester.pumpAndSettle();
        expect(active.featuredMediaId, changeSession ? isNull : 'photo-b');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
  testWidgets(
    'starring a Moment tells the app shell to refresh the navbar avatar',
    (tester) async {
      final uploads = PendingPublicMediaService.forTest(
        publishedLookup: (_) async => false,
        moderationLookup: (_) => Completer<MediaModerationSnapshot>().future,
        delay: (_) => Completer<void>().future,
      );
      addTearDown(uploads.clear);
      final repo = _Repo();
      final media = CheckinProfile.fromJson({
        'checkin': {'id': 'checkin', 'venueId': 'venue'},
        'user': {'id': 'me'},
        'media': [
          {'id': 'photo-a', 'url': '', 'media_type': 'photo'},
        ],
      }).media;

      await tester.pumpWidget(
        MaterialApp(
          home: MomentsViewerPage(
            media: media,
            initialIndex: 0,
            allowFeature: true,
            // No check-in id → the optional avatar crop prompt is skipped.
            checkinId: '',
            uploads: uploads,
            repository: repo,
          ),
        ),
      );
      await tester.pump();

      final before = ActiveCheckinService.changes.value;
      await tester.tap(find.byIcon(Icons.star_border_rounded));
      await tester.pump();
      await tester.pump();

      expect(repo.featured, ['photo-a']);
      expect(ActiveCheckinService.changes.value, greaterThan(before));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
