import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_ui.dart';
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

void main() {
  setUp(() {
    // Story/venue lookups on this page have no network in tests.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'NO_TEST_NETWORK'),
        );
  });

  testWidgets(
    'profile menu and report use the app sheet and report design, then the standard thanks dialog',
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
      expect(find.text('Report this user'), findsOneWidget);
      expect(find.byType(ReportHeaderIcon), findsOneWidget);
      expect(find.byType(ReportReasonTile), findsNWidgets(6));
      await tester.tap(find.text('Harassment'));
      await tester.pump();
      await tester.tap(find.byType(ReportSubmitButton));
      await tester.pumpAndSettle();

      expect(repo.reports, ['HARASSMENT']);
      expect(repo.blocked, ['mehmet']);
      expect(find.text('Report this user'), findsNothing);
      expect(find.text('Report received'), findsNothing);
      expect(find.text('Thanks for your report'), findsOneWidget);
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
