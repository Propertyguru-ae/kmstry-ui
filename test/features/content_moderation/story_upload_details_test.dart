import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';

PendingPublicMedia _story(
  String id,
  PendingPublicMediaState state, {
  PendingPublicMediaKind kind = PendingPublicMediaKind.personalStory,
  String venueId = 'venue-1',
  String? message,
  bool receipt = true,
}) => PendingPublicMedia(
  id: id,
  kind: kind,
  venueId: venueId,
  localPath: '',
  isVideo: true,
  createdAt: DateTime(2026, 10, 1),
  state: state,
  message: message,
  hasServerReceipt: receipt,
);

PendingPublicMediaService _service() => PendingPublicMediaService.forTest(
  publishedLookup: (_) => Completer<bool>().future,
  moderationLookup: (_) async => const MediaModerationSnapshot(),
  delay: (_) => Completer<void>().future,
);

Future<void> _render(
  WidgetTester tester,
  PendingPublicMediaService service,
  PendingPublicMedia item, {
  VoidCallback? onRetake,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StoryUploadDetails(
          item: item,
          service: service,
          onRetake: onRetake,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'checking story has a quiet label and owner-only explanation, no spinner',
    (tester) async {
      final service = _service();
      addTearDown(service.clear);
      final item = _story('story-1', PendingPublicMediaState.checking);
      service.track(item);
      await _render(tester, service, item);
      expect(find.text('Your uploads'), findsOneWidget);
      expect(find.text('Sharing'), findsOneWidget);
      expect(
        find.text('Only you can see this for now. You can keep using KMSTRY.'),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'long wait explicitly says story is not public and not to upload again',
    (tester) async {
      final service = _service();
      addTearDown(service.clear);
      final item = _story('slow', PendingPublicMediaState.delayed);
      service.track(item);
      await _render(tester, service, item);
      expect(find.text('Taking longer'), findsOneWidget);
      expect(find.textContaining('not visible to others yet'), findsOneWidget);
      expect(
        find.textContaining('do not need to upload it again'),
        findsOneWidget,
      );
    },
  );

  testWidgets('manual review keeps the preview and explains visibility', (
    tester,
  ) async {
    final service = _service();
    addTearDown(service.clear);
    final item = _story('review', PendingPublicMediaState.underReview);
    service.track(item);
    await _render(tester, service, item);
    expect(find.text('Under review'), findsOneWidget);
    expect(find.byType(PendingPublicMediaPreview), findsOneWidget);
    expect(find.textContaining('Only you can see it for now'), findsOneWidget);
  });

  testWidgets('rejected story removes image but keeps reason until dismissed', (
    tester,
  ) async {
    final service = _service();
    addTearDown(service.clear);
    final item = _story(
      'rejected',
      PendingPublicMediaState.rejected,
      message: 'Disallowed text in image.',
    );
    service.track(item);
    await _render(tester, service, item, onRetake: () {});
    expect(find.byType(PendingPublicMediaPreview), findsNothing);
    expect(find.byType(Image), findsNothing);
    expect(find.text('Disallowed text in image.'), findsOneWidget);
    expect(find.text('Not shared'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pump();
    expect(service.items, isEmpty);
    expect(find.text('No pending story uploads.'), findsOneWidget);
  });

  testWidgets('uncertain transfer does not offer a duplicate retry', (
    tester,
  ) async {
    final service = _service();
    addTearDown(service.clear);
    final item = _story(
      'uncertain',
      PendingPublicMediaState.connectionIssue,
      receipt: false,
    );
    service.track(item);
    await _render(tester, service, item, onRetake: () {});
    expect(find.text('Check upload'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
    expect(find.text('Dismiss'), findsOneWidget);
  });

  testWidgets(
    'venue upload details show only that venue, never personal or other venues',
    (tester) async {
      final service = _service();
      addTearDown(service.clear);
      final item = _story(
        'venue-1-story',
        PendingPublicMediaState.rejected,
        kind: PendingPublicMediaKind.venueStory,
        message: 'Current venue reason',
      );
      service.track(item);
      service.track(
        _story(
          'other-venue',
          PendingPublicMediaState.rejected,
          kind: PendingPublicMediaKind.venueStory,
          venueId: 'venue-2',
          message: 'Other venue reason',
        ),
      );
      service.track(
        _story(
          'personal',
          PendingPublicMediaState.rejected,
          message: 'Personal reason',
        ),
      );
      await _render(tester, service, item);
      expect(find.text('Current venue reason'), findsOneWidget);
      expect(find.text('Other venue reason'), findsNothing);
      expect(find.text('Personal reason'), findsNothing);
    },
  );

  testWidgets('small preview label does not overflow or animate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 58,
            child: StoryUploadStatus(
              item: _story('slow', PendingPublicMediaState.delayed),
              overlay: true,
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Taking longer'), findsOneWidget);
  });

  testWidgets('owner story preview has no dimming veil or moderation shield', (
    tester,
  ) async {
    final item = PendingPublicMedia(
      id: 'color-story',
      kind: PendingPublicMediaKind.personalStory,
      venueId: null,
      localPath: '/camera/photo.jpg',
      isVideo: false,
      createdAt: DateTime(2026, 10, 1),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 80,
            height: 80,
            child: PendingPublicMediaPreview(item: item),
          ),
        ),
      ),
    );
    expect(find.byType(Image), findsOneWidget);
    expect(find.byIcon(Icons.shield_outlined), findsNothing);
    final overlays = tester.widgetList<ColoredBox>(
      find.descendant(
        of: find.byType(PendingPublicMediaPreview),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(
      overlays.any((box) => box.color == Colors.black.withValues(alpha: .42)),
      false,
    );
  });

  testWidgets(
    'published stories remain accessible while another story is being checked',
    (tester) async {
      final service = _service();
      addTearDown(service.clear);
      final item = _story('checking', PendingPublicMediaState.checking);
      service.track(item);
      var viewed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => StoryUploadDetails(
                    item: item,
                    service: service,
                    onViewPublished: () {
                      viewed = true;
                    },
                  ),
                ),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('View shared stories'));
      await tester.tap(find.text('View shared stories'));
      await tester.pumpAndSettle();
      expect(viewed, true);
      expect(find.byType(StoryUploadDetails), findsNothing);
      expect(service.byId(item.id), isNotNull);
    },
  );
}
