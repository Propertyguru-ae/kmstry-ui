import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/theme/theme_provider.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/profile/data/settings_device_permissions.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_screen.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_offers_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_team_page.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_calendar_entry.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_events_list_page.dart';

class NoEvents extends VenueEventRepository {
  @override
  Future<List<VenueUpcomingEvent>> listEventMonth(
    String venueId,
    DateTime month,
  ) async => [];

  @override
  Future<List<VenueEventCalendarEntry>> getEventCalendar(
    String venueId,
  ) async => [];
}

class SignedInUser extends AuthRepository {
  @override
  Future<Map<String, dynamic>> getMe({bool forceRefresh = false}) async => {
    'fullName': 'Alex',
    'hasPersonalProfile': true,
    'lastActiveContext': 'PERSONAL',
  };
}

void main() {
  setUp(() async {
    // No network in tests: every authenticated call fails fast.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => throw PlatformException(code: 'NO_TEST_NETWORK'),
        );
    VenueSession.instance.clear();
    await VenueSession.instance.load('venue-a', VenueMemberRole.owner);
  });
  tearDown(() => VenueSession.instance.clear());

  // Every Manage destination uses the app's standard page title (Settings,
  // Followers, Manage …): 18 / w700 in the theme's text colour.
  final pages = <String, Widget Function()>{
    'Analytics': () => const VenueAnalyticsScreen(venueId: 'venue-a'),
    'Events': () => VenueEventsListPage(
      venueId: 'venue-a',
      events: const [],
      repository: NoEvents(),
      onRefresh: () {},
    ),
    'Deals & Discounts': () =>
        const VenueOffersPage(venueId: 'venue-a', venueName: 'Cafe'),
    'Team Management': () => const VenueTeamPage(
      venueId: 'venue-a',
      callerRole: VenueMemberRole.owner,
    ),
    'Settings': () {
      // The theme toggle reads secure storage on start; give it an empty one.
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      return ChangeNotifierProvider(
        create: (_) => ThemeProvider(),
        child: SettingsPage(
          authRepository: SignedInUser(),
          permissionsReader: () async => const SettingsDevicePermissions(
            camera: true,
            location: true,
            notifications: true,
          ),
        ),
      );
    },
  };

  for (final brightness in Brightness.values) {
    for (final entry in pages.entries) {
      testWidgets('${entry.key} title matches the standard (${brightness.name})', (
        tester,
      ) async {
        final theme = brightness == Brightness.dark
            ? AppTheme.darkTheme
            : AppTheme.lightTheme;
        await tester.pumpWidget(
          MaterialApp(theme: theme, home: entry.value()),
        );
        await tester.pump();
        final title = find.descendant(
          of: find.byType(AppBar),
          matching: find.text(entry.key),
        );
        expect(title, findsOneWidget);
        final style = tester.renderObject<RenderParagraph>(title).text.style!;
        expect(style.fontSize, 18);
        expect(style.fontWeight, FontWeight.w700);
        expect(style.color, theme.colorScheme.onSurface);
        expect(tester.widget<AppBar>(find.byType(AppBar).first).centerTitle ??
            theme.appBarTheme.centerTitle, isTrue);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      });
    }
  }
}
