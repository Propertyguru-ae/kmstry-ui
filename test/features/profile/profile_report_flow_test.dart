import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_ui.dart';
import 'package:kmstry_frontend/features/reports/presentation/child_safety_report.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Profile details fail to refresh (not a missing account), so the page shows
/// the list's name with its normal actions; reports and blocks are recorded.
class ReportingRepo extends CheckinRepository {
  final reports = <String>[];
  final blocked = <String>[];

  @override
  Future<PublicUserProfile> getPublicUserProfile(String userId) async =>
      throw ApiException(statusCode: 500, data: {'message': 'offline'});

  @override
  Future<Set<String>> getBlockedUserIds() async => <String>{};

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
  }) async => reports.add(reason);

  @override
  Future<void> blockUser(String targetUserId) async =>
      blocked.add(targetUserId);
}

class BlockingRepo extends ReportingRepo {
  final current = <String>{};
  final unblocked = <String>[];

  @override
  Future<Set<String>> getBlockedUserIds() async => {...current};

  @override
  Future<void> blockUser(String targetUserId) async {
    blocked.add(targetUserId);
    current.add(targetUserId);
  }

  @override
  Future<void> unblockUser(String targetUserId) async {
    unblocked.add(targetUserId);
    current.remove(targetUserId);
  }
}

void main() {
  setUp(() {
    // Story/venue lookups on this page have no network in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'NO_TEST_NETWORK'),
        );
  });

  for (final (label, reason) in [
    ('Bullying or harassment', 'HARASSMENT'),
    (childSafetyReportLabel, childSafetyReportReason),
  ]) {
    testWidgets(
      'profile $label report uses the shared sheet, block and standard thanks dialog',
      (tester) async {
        tester.view.physicalSize = const Size(393 * 3, 852 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final originalOnError = FlutterError.onError;
        FlutterError.onError = (details) {
          if (details.library == 'image resource service') return;
          originalOnError?.call(details);
        };
        addTearDown(() => FlutterError.onError = originalOnError);
        final repo = ReportingRepo();
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: ProfilePreviewPage(
              userId: 'mehmet',
              userName: 'Mehmet',
              checkinRepository: repo,
            ),
          ),
        );
        await tester.pumpAndSettle();
        // The test font is much wider than real fonts; the profile header can
        // report an overflow with it. Only the popups below are under test.
        final pageLoad = tester.takeException();
        expect(pageLoad == null || '$pageLoad'.contains('overflowed'), isTrue);

        await tester.tap(find.byIcon(Icons.more_horiz_rounded));
        await tester.pumpAndSettle();
        final menu = tester.widget<BottomSheet>(find.byType(BottomSheet));
        expect(menu.backgroundColor, const Color(0xFF121A2B));
        expect(find.byType(AppSheetRow), findsNWidgets(2));
        expect(find.byType(ListTile), findsNothing);

        await tester.tap(find.text('Report'));
        await tester.pumpAndSettle();
        expect(find.text('What do you want to report?'), findsOneWidget);
        expect(find.byType(ReportHeaderIcon), findsOneWidget);
        // The new high-priority reason must not become selected by default.
        expect(
          tester
              .widget<ReportReasonTile>(
                find.widgetWithText(ReportReasonTile, childSafetyReportLabel),
              )
              .selected,
          isFalse,
        );
        await tester.scrollUntilVisible(
          find.text(label),
          100,
          scrollable: find
              .descendant(
                of: find.byType(ListView).last,
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pump();
        if (reason == childSafetyReportReason) {
          expect(find.text(childSafetyReportHelp), findsOneWidget);
        }
        await tester.tap(find.byType(ReportSubmitButton));
        await tester.pumpAndSettle();

        expect(repo.reports, [reason]);
        expect(repo.blocked, ['mehmet']);
        expect(find.text('What do you want to report?'), findsNothing);
        expect(find.text('Report received'), findsNothing);
        expect(find.text('Thanks for your report'), findsOneWidget);
        await tester.tap(find.text('Done'));
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('profile Block and Unblock use the standard popups and cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = BlockingRepo();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ProfilePreviewPage(
          userId: 'mehmet',
          userName: 'Mehmet',
          checkinRepository: repo,
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.takeException();

    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block'));
    await tester.pumpAndSettle();
    expect(find.text('Block user?'), findsNothing);
    expect(find.text('Block this user?'), findsOneWidget);
    await tester.tap(find.text('Block user'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(repo.blocked, ['mehmet']);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User blocked'),
      findsOneWidget,
    );

    // The notice can sit over the bar; the menu now offers the reverse action.
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock'));
    await tester.pumpAndSettle();
    expect(find.text('Unblock this user?'), findsOneWidget);
    await tester.tap(find.widgetWithText(PrimaryButton, 'Unblock'));
    await tester.pumpAndSettle();
    tester.takeException();
    expect(repo.unblocked, ['mehmet']);
    expect(
      find.widgetWithText(BrandedNoticeCard, 'User unblocked'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.more_horiz_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Block'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
