import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/core/checkin/checkin_renewal_prompts.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';

const _here = (lat: 25.2048, lng: 55.2708);
final _expiry = DateTime(2026, 10, 6, 14);
final _alpha = CheckinRenewalInfo(
  checkinId: 'checkin-1',
  venueId: 'venue-a',
  venueName: 'Cafe Alpha',
  expiresAt: _expiry,
  position: _here,
  userId: 'handan',
);

void main() {
  group('CheckinRenewalPrompts', () {
    late DateTime now;
    late CheckinRenewalPrompts prompts;

    setUp(() {
      now = DateTime(2026, 10, 6, 14);
      prompts = CheckinRenewalPrompts(clock: () => now);
    });

    test(
      'a prompt deferred on the venue account is asked once back on personal',
      () {
        prompts.defer(_alpha, userId: 'handan');

        final deferred = prompts.takeDeferred(
          userId: 'handan',
          position: _here,
        );
        expect(deferred?.checkinId, 'checkin-1');
        expect(prompts.claim('checkin-1'), isTrue);

        // Never asked twice for the same check-in.
        expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
        expect(prompts.claim('checkin-1'), isFalse);
      },
    );

    test('a deferred prompt is dropped after the 6h renewal window', () {
      prompts.defer(_alpha, userId: 'handan');
      now = now.add(const Duration(hours: 6, minutes: 1));
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
    });

    test('another signed-in user never gets the deferred prompt', () {
      prompts.defer(_alpha, userId: 'handan');
      expect(
        prompts.takeDeferred(userId: 'someone-else', position: _here),
        isNull,
      );
      // Consumed: it does not come back for the original user later either.
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
    });

    test(
      'a check-in already asked about on personal is not deferred again',
      () {
        expect(prompts.claim('checkin-1'), isTrue);
        prompts.defer(_alpha, userId: 'handan');
        expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
      },
    );

    test(
      'it is still asked when the user stayed where the check-in expired',
      () {
        prompts.defer(_alpha, userId: 'handan');
        // ~20 m away: still at the venue.
        final deferred = prompts.takeDeferred(
          userId: 'handan',
          position: (lat: 25.2050, lng: 55.2708),
        );
        expect(deferred?.checkinId, 'checkin-1');
      },
    );

    test('it is dropped when the user has left since the check-in expired', () {
      prompts.defer(_alpha, userId: 'handan');
      // ~1 km away: "you're still at Cafe Alpha" would be wrong.
      expect(
        prompts.takeDeferred(
          userId: 'handan',
          position: (lat: 25.2138, lng: 55.2708),
        ),
        isNull,
      );
    });

    test('a new check-in or logout clears the waiting prompt', () {
      prompts.defer(_alpha, userId: 'handan');
      prompts.clearDeferred();
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
    });

    test('late detection does not restart the window from defer time', () {
      now = _expiry.add(const Duration(hours: 5, minutes: 59));
      prompts.defer(_alpha, userId: 'handan');
      now = now.add(const Duration(minutes: 2));
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
    });

    test('exactly six hours after actual expiry is still eligible', () {
      prompts.defer(_alpha, userId: 'handan');
      now = _expiry.add(const Duration(hours: 6));
      expect(prompts.takeDeferred(userId: 'handan', position: _here), _alpha);
    });

    test('unknown expiry or future expiry never produces a prompt', () {
      const unknown = CheckinRenewalInfo(checkinId: 'legacy', venueId: 'a');
      prompts.defer(unknown, userId: 'handan');
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
      now = _expiry.subtract(const Duration(seconds: 1));
      prompts.defer(_alpha, userId: 'handan');
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
    });

    test('missing GPS fails closed but can retry with a fresh fix', () {
      prompts.defer(_alpha, userId: 'handan');
      expect(prompts.takeDeferred(userId: 'handan'), isNull);
      expect(prompts.takeDeferred(userId: 'handan', position: _here), _alpha);
    });

    test('missing or mismatched account cannot defer a prompt', () {
      prompts.defer(_alpha, userId: null);
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
      prompts.defer(_alpha, userId: 'another-user');
      expect(
        prompts.takeDeferred(userId: 'another-user', position: _here),
        isNull,
      );
    });

    test('discarded deferred check-in cannot resurface through cold start', () {
      prompts.defer(_alpha, userId: 'handan');
      prompts.clearDeferred();
      expect(prompts.wasPrompted('checkin-1'), isTrue);
      expect(prompts.claim('checkin-1'), isFalse);
    });

    test('invalid GPS coordinates are not treated as nearby', () {
      expect(_alpha.isNear((lat: double.nan, lng: 55)), isFalse);
      expect(_alpha.isNear((lat: 250, lng: 55)), isFalse);
    });
  });

  group('renewal lifecycle wiring', () {
    late CheckinRenewalPrompts prompts;
    setUp(() {
      FlutterSecureStorage.setMockInitialValues({});
      SharedPreferences.setMockInitialValues({});
      ActiveCheckinService().clear();
      PendingPublicMediaService.instance.clear();
      prompts = CheckinRenewalPrompts(clock: () => _expiry, watchState: true);
    });
    tearDown(() => prompts.dispose());

    test(
      'new check-in invalidates old deferred prompt even if new one ends',
      () {
        prompts.defer(_alpha, userId: 'handan');
        final revision = prompts.revision;
        ActiveCheckinService().setActiveCheckin('new', userId: 'handan');
        ActiveCheckinService().clear();
        expect(prompts.revision, greaterThan(revision));
        expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
        expect(prompts.wasPrompted('checkin-1'), isTrue);
      },
    );

    test('session generation reset clears deferred and claimed state', () {
      prompts.claim('already-asked');
      prompts.defer(_alpha, userId: 'handan');
      final revision = prompts.revision;
      // The same centralized call is used by logout, forced expiry and env switch.
      PendingPublicMediaService.instance.clear();
      expect(prompts.revision, greaterThan(revision));
      expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
      expect(prompts.wasPrompted('already-asked'), isFalse);
    });

    test(
      'direct credential cleanup also invalidates pending attempts',
      () async {
        prompts.defer(_alpha, userId: 'handan');
        final revision = prompts.revision;
        await SecureStorage.clearSession();
        expect(prompts.revision, greaterThan(revision));
        expect(prompts.takeDeferred(userId: 'handan', position: _here), isNull);
      },
    );

    test('media refresh does not invalidate the active identity', () {
      ActiveCheckinService().setActiveCheckin('same', userId: 'handan');
      final identity = ActiveCheckinService().identityRevision;
      final revision = prompts.revision;
      ActiveCheckinService().notifyMediaUpdated();
      expect(ActiveCheckinService().identityRevision, identity);
      expect(prompts.revision, revision);
    });
  });

  group('fresh renewal location', () {
    Position position({DateTime? timestamp, double accuracy = 10}) => Position(
      latitude: _here.lat,
      longitude: _here.lng,
      timestamp: timestamp ?? _expiry,
      accuracy: accuracy,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
    test('fresh and accurate fix is accepted', () {
      expect(isFreshRenewalPosition(position(), _expiry), isTrue);
    });
    test('stale, future-dated or inaccurate fix is not accepted', () {
      expect(
        isFreshRenewalPosition(
          position(timestamp: _expiry.subtract(const Duration(minutes: 2))),
          _expiry,
        ),
        isFalse,
      );
      expect(
        isFreshRenewalPosition(
          position(timestamp: _expiry.add(const Duration(minutes: 2))),
          _expiry,
        ),
        isFalse,
      );
      expect(isFreshRenewalPosition(position(accuracy: 100), _expiry), isFalse);
    });
  });

  group('renewal result', () {
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (c) {
                context = c;
                return const SizedBox.expand();
              },
            ),
          ),
        ),
      );
      return context;
    }

    testWidgets('renewed check-in uses the app success toast, not a snackbar', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      showCheckinRenewalResult(
        context,
        renewed: true,
        venueLabel: 'Cafe Alpha',
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text('You\'re checked in at Cafe Alpha for 3 more hours.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('failed renewal uses the app error toast', (tester) async {
      final context = await pumpHost(tester);
      showCheckinRenewalResult(
        context,
        renewed: false,
        venueLabel: 'Cafe Alpha',
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        find.text(
          'Couldn\'t renew your check-in. Make sure you\'re at the venue.',
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('new check-in or logout dismisses only the renewal dialog', (
      tester,
    ) async {
      final context = await pumpHost(tester);
      final eligibility = ValueNotifier<bool>(true);
      final result = showCheckinExpiredDialog(
        context,
        venueLabel: 'Cafe Alpha',
        canRenew: () => eligibility.value,
        eligibilityChanges: eligibility,
      );
      await tester.pumpAndSettle();
      expect(find.text('Renew check-in'), findsOneWidget);
      eligibility.value = false;
      await tester.pumpAndSettle();
      expect(await result, isFalse);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(Scaffold), findsOneWidget);
      eligibility.dispose();
    });
  });
}
