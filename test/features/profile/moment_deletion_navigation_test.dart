import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

class _Repo extends CheckinRepository {
  final result = Completer<bool>();
  @override
  Future<bool> deletePhoto(String photoId) => result.future;
}

void main() {
  for (final changeSession in [false, true]) {
    testWidgets(
      'delete result after viewer closed; session changed=$changeSession',
      (tester) async {
        final repo = _Repo();
        final deleted = <String>[];
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
                      repository: repo,
                      onDeleted: (id, _) => deleted.add(id),
                      media: [
                        CheckinProfileMedia(
                          id: 'first',
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
        await tester.tap(find.byIcon(Icons.delete_outline_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Delete & end check-in'));
        await tester.pump();
        // Finish the confirmation-dialog reverse transition before closing viewer.
        await tester.pump(const Duration(milliseconds: 350));
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await tester.pumpAndSettle();
        if (changeSession) {
          PendingPublicMediaService.instance.clear();
          ActiveCheckinService().setActiveCheckin('new-account-checkin');
        }
        repo.result.complete(true);
        await tester.pumpAndSettle();
        expect(deleted, changeSession ? isEmpty : ['first']);
        if (changeSession) {
          expect(ActiveCheckinService().activeCheckinId, 'new-account-checkin');
        }
        await tester.pumpWidget(const SizedBox.shrink());
        ActiveCheckinService().clear();
      },
    );
  }
}
