import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_ui.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

class AcceptsReports extends CheckinRepository {
  final blocked = <String>[];

  @override
  Future<void> reportUser({
    String? targetUserId,
    required String reason,
    String? details,
    String? messageId,
    String? storyId,
    String? venueStoryId,
    String? checkinMediaId,
    String? venueId,
    String? venuePhotoId,
    String? venuePhotoUrl,
    String? googlePhotoToken,
    String? venueGalleryItemId,
    String? eventId,
    String? venueOfferId,
    String? venueMenuItemId,
    String? venueBenefitId,
  }) async {}

  @override
  Future<void> blockUser(String targetUserId) async =>
      blocked.add(targetUserId);
}

void main() {
  for (final reportContent in [false, true]) {
    testWidgets(
      'after reporting ${reportContent ? 'content' : 'a user'} the thanks message uses the app dialog',
      (tester) async {
        tester.view.physicalSize = const Size(393 * 3, 852 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final repo = AcceptsReports();
        bool? result;
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showReportUserSheet(
                      context,
                      targetUserId: 'mehmet',
                      storyId: reportContent ? 'story-1' : null,
                      repository: repo,
                    );
                  },
                  child: const Text('Report'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Scam or fraud'));
        await tester.pump();
        // User reports also block, so the button says so.
        expect(
          find.text(reportContent ? 'Report' : 'Report & block'),
          findsWidgets,
        );
        await tester.tap(find.byType(ReportSubmitButton));
        await tester.pumpAndSettle();

        // The report sheet closed; the standard app dialog thanks the user.
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.text('Thanks for your report'), findsOneWidget);
        expect(
          find.text(
            reportContent
                ? 'The selected content has been sent to the KMSTRY moderation team.'
                : 'This user has been blocked automatically, and messaging has been paused for your safety.',
          ),
          findsOneWidget,
        );
        expect(find.text('Not now'), findsNothing);
        expect(result, isNull);

        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(result, isTrue);
        expect(repo.blocked, reportContent ? isEmpty : ['mehmet']);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
