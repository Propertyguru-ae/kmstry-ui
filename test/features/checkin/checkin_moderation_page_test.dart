import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_moderation_page.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';

CheckinActivationStatus status(
  CheckinActivationState state, {
  bool canJoin = false,
  String id = 'checkin-1',
  String? message,
  String? receipt = 'review-1',
}) => CheckinActivationStatus(
  checkinId: id,
  venueId: 'venue-1',
  state: state,
  canJoin: canJoin,
  userMessage: message,
  moderationItemId: receipt,
);

class FakeCheckinRepository extends CheckinRepository {
  Future<CheckinActivationStatus> Function() load = () async =>
      status(CheckinActivationState.pending);
  Future<void> Function() cancel = () async {};
  int checkoutCalls = 0;
  int activationCalls = 0;
  Map<String, Object>? activationRequest;
  Future<CheckinActivationStatus> Function() activate = () async =>
      status(CheckinActivationState.approved, canJoin: true);
  @override
  Future<CheckinActivationStatus> activatePendingCheckin({
    required String checkinId,
    required String moderationItemId,
    required double latitude,
    required double longitude,
    required double accuracyMeters,
    required DateTime locationCapturedAt,
  }) {
    activationCalls++;
    activationRequest = {
      'checkinId': checkinId,
      'moderationItemId': moderationItemId,
      'latitude': latitude,
      'longitude': longitude,
      'accuracyMeters': accuracyMeters,
      'locationCapturedAt': locationCapturedAt,
    };
    return activate();
  }

  @override
  Future<CheckinActivationStatus> getCheckinActivationStatus(String id) =>
      load();
  @override
  Future<void> checkout(String id) async {
    checkoutCalls++;
    await cancel();
  }
}

void main() {
  late FakeCheckinRepository repository;
  late DateTime now;
  late Future<Position> Function() readLocation;
  late int locationCalls;
  CheckinModerationFlowResult? result;
  setUp(() {
    repository = FakeCheckinRepository();
    now = DateTime(2026, 10, 1, 12);
    result = null;
    locationCalls = 0;
    readLocation = () async => Position(
      latitude: 25,
      longitude: 55,
      timestamp: now,
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  });
  Future<void> open(WidgetTester tester, {String? preview}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.push<CheckinModerationFlowResult>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => CheckinModerationPage(
                      checkinId: 'checkin-1',
                      repository: repository,
                      now: () => now,
                      previewPath: preview,
                      readLocation: () {
                        locationCalls++;
                        return readLocation();
                      },
                    ),
                  ),
                );
              },
              child: const Text('Origin'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Origin'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
  }

  test('maps server moderation and activation separately', () {
    final parsed = CheckinActivationStatus.fromJson({
      'checkin_id': 'checkin-1',
      'venue_id': 'venue-1',
      'status': 'NEEDS_REVIEW',
      'can_join': false,
      'user_message': 'Text requires a contextual review.',
    });
    expect(parsed.state, CheckinActivationState.needsReview);
    expect(parsed.canJoin, false);
    expect(parsed.userMessage, 'Text requires a contextual review.');
  });
  for (final state in [
    CheckinActivationState.rejected,
    CheckinActivationState.needsReview,
    CheckinActivationState.error,
  ]) {
    testWidgets(
      'first Moment shows the backend explanation for $state without joining',
      (tester) async {
        repository.load = () async =>
            status(state, message: 'Specific safe moderation explanation.');
        await open(tester);
        expect(
          find.textContaining('Specific safe moderation explanation.'),
          findsOneWidget,
        );
        expect(
          find.textContaining('Your check-in has not started'),
          findsOneWidget,
        );
        expect(result, isNull);
        await close(tester);
      },
    );
  }
  testWidgets('waiting is inline with no spinning indicator or popup', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('Checking your Moment'), findsOneWidget);
    expect(find.textContaining('Only you can see'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(repository.checkoutCalls, 0);
    await close(tester);
  });
  testWidgets(
    '30 seconds is a delay, not rejection or automatic cancellation',
    (tester) async {
      await open(tester);
      now = now.add(const Duration(seconds: 31));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.text('Taking a little longer'), findsOneWidget);
      expect(find.text('Retake Moment'), findsNothing);
      expect(repository.checkoutCalls, 0);
      expect(result, isNull);
      await close(tester);
    },
  );
  testWidgets('manual review keeps room closed and can later become approved', (
    tester,
  ) async {
    repository.load = () async => status(CheckinActivationState.needsReview);
    await open(tester);
    expect(find.text('Your Moment needs a review'), findsOneWidget);
    expect(repository.checkoutCalls, 0);
    expect(result, isNull);
    repository.load = () async =>
        status(CheckinActivationState.approved, canJoin: true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.approved);
    expect(repository.checkoutCalls, 0);
    await close(tester);
  });
  testWidgets('APPROVED without can_join cannot enter the room', (
    tester,
  ) async {
    repository.load = () async => status(CheckinActivationState.approved);
    await open(tester);
    expect(result, isNull);
    expect(find.text('Checking your Moment'), findsOneWidget);
    await close(tester);
  });
  testWidgets('approval does not pop a different screen above the check-in', (
    tester,
  ) async {
    await open(tester);
    final navigator = Navigator.of(
      tester.element(find.byType(CheckinModerationPage)),
    );
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Other screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repository.load = () async =>
        status(CheckinActivationState.approved, canJoin: true);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Other screen'), findsOneWidget);
    expect(result, isNull);
    navigator.pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.approved);
    await close(tester);
  });
  testWidgets('a response for another check-in is never accepted', (
    tester,
  ) async {
    repository.load = () async =>
        status(CheckinActivationState.approved, canJoin: true, id: 'other');
    await open(tester);
    expect(result, isNull);
    expect(find.text('Reconnecting'), findsOneWidget);
    await close(tester);
  });
  testWidgets('network failure is not rejected and retries status reads only', (
    tester,
  ) async {
    repository.load = () async => throw StateError('offline');
    await open(tester);
    expect(find.text('Reconnecting'), findsOneWidget);
    expect(find.text('Retake Moment'), findsNothing);
    expect(repository.checkoutCalls, 0);
    repository.load = () async =>
        status(CheckinActivationState.approved, canJoin: true);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.approved);
    await close(tester);
  });
  testWidgets('rejected Moment is hidden and retake waits for cancellation', (
    tester,
  ) async {
    repository.load = () async => status(CheckinActivationState.rejected);
    final cancellation = Completer<void>();
    repository.cancel = () => cancellation.future;
    await open(tester, preview: '/tmp/rejected-photo.jpg');
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is FileImage),
      findsNothing,
    );
    expect(repository.checkoutCalls, 0);
    await tester.tap(find.text('Retake Moment'));
    await tester.pump();
    expect(result, isNull);
    expect(repository.checkoutCalls, 1);
    cancellation.complete();
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.retake);
    await close(tester);
  });
  testWidgets(
    'cancel goes back to the exact origin after backend acknowledgement',
    (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel check-in'));
      await tester.pumpAndSettle();
      expect(result, CheckinModerationFlowResult.cancelled);
      expect(find.text('Origin'), findsOneWidget);
      expect(repository.checkoutCalls, 1);
      await close(tester);
    },
  );
  testWidgets('failed cancellation stays on screen and can be retried safely', (
    tester,
  ) async {
    repository.cancel = () async => throw StateError('offline');
    await open(tester);
    await tester.tap(find.text('Cancel check-in'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(
      find.textContaining('could not confirm cancellation'),
      findsOneWidget,
    );
    repository.load = () async =>
        status(CheckinActivationState.approved, canJoin: true);
    await tester.pump(const Duration(seconds: 10));
    expect(result, isNull);
    repository.cancel = () async {};
    await tester.tap(find.byTooltip('Cancel check-in'));
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.cancelled);
    expect(repository.checkoutCalls, 2);
    await close(tester);
  });
  testWidgets(
    'late approval while cancellation is in flight cannot open room',
    (tester) async {
      final reading = Completer<CheckinActivationStatus>();
      final cancelling = Completer<void>();
      repository.load = () => reading.future;
      repository.cancel = () => cancelling.future;
      await open(tester);
      await tester.tap(find.text('Cancel check-in'));
      reading.complete(status(CheckinActivationState.approved, canJoin: true));
      await tester.pump();
      expect(result, isNull);
      cancelling.complete();
      await tester.pumpAndSettle();
      expect(result, CheckinModerationFlowResult.cancelled);
      await close(tester);
    },
  );
  testWidgets(
    'expired activation has a fresh-start message, not policy rejection',
    (tester) async {
      repository.load = () async =>
          status(CheckinActivationState.activationExpired);
      await open(tester);
      expect(find.text('Start a fresh check-in'), findsOneWidget);
      expect(find.textContaining('content guidelines'), findsNothing);
      expect(result, isNull);
      await close(tester);
    },
  );
  testWidgets('already deleted pending check-in can close safely', (
    tester,
  ) async {
    repository.cancel = () async =>
        throw ApiException(statusCode: 404, data: {});
    await open(tester);
    await tester.tap(find.text('Cancel check-in'));
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.cancelled);
    await close(tester);
  });
  for (final dark in [true, false]) {
    testWidgets(
      '"Let’s try another Moment" uses the app design (${dark ? 'dark' : 'light'})',
      (tester) async {
        repository.load = () async => status(CheckinActivationState.rejected);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? AppTheme.darkTheme : AppTheme.lightTheme,
            home: CheckinModerationPage(
              checkinId: 'checkin-1',
              repository: repository,
              now: () => now,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Let’s try another Moment'), findsOneWidget);
        // Same gradient icon tile and button as the standard popups.
        expect(find.byIcon(Icons.add_a_photo_rounded), findsOneWidget);
        expect(find.byIcon(Icons.photo_camera_rounded), findsOneWidget);
        expect(find.byType(FilledButton), findsNothing);
        expect(find.text('Check in'), findsOneWidget);
        expect(find.byTooltip('Cancel check-in'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await close(tester);
      },
    );
  }
  testWidgets('old session approval cannot navigate the new session', (
    tester,
  ) async {
    final reading = Completer<CheckinActivationStatus>();
    repository.load = () => reading.future;
    await open(tester);
    PendingPublicMediaService.instance.clear();
    reading.complete(status(CheckinActivationState.approved, canJoin: true));
    await tester.pump();
    expect(result, isNull);
    expect(repository.checkoutCalls, 0);
    await close(tester);
  });

  for (final initial in [
    CheckinActivationState.processing,
    CheckinActivationState.needsReview,
  ]) {
    testWidgets(
      'late $initial approval completes the same Moment with a fresh fix',
      (tester) async {
        repository.load = () async => status(initial);
        await open(tester);
        now = now.add(const Duration(minutes: 5));
        repository.load = () async =>
            status(CheckinActivationState.readyToActivate);
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(repository.activationRequest, {
          'checkinId': 'checkin-1',
          'moderationItemId': 'review-1',
          'latitude': 25.0,
          'longitude': 55.0,
          'accuracyMeters': 5.0,
          'locationCapturedAt': now,
        });
        expect(locationCalls, 1);
        expect(repository.activationCalls, 1);
        expect(repository.checkoutCalls, 0);
        expect(result, CheckinModerationFlowResult.approved);
        await close(tester);
      },
    );
  }

  testWidgets(
    'location failure stays inline and retries without a new upload',
    (tester) async {
      final goodLocation = readLocation;
      readLocation = () async => throw StateError('location denied');
      repository.load = () async =>
          status(CheckinActivationState.readyToActivate);
      await open(tester);
      expect(find.text('Confirm your location'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Retake Moment'), findsNothing);
      expect(repository.activationCalls, 0);
      await tester.pump(const Duration(minutes: 1));
      expect(locationCalls, 1);
      readLocation = goodLocation;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(repository.activationCalls, 1);
      expect(result, CheckinModerationFlowResult.approved);
      await close(tester);
    },
  );

  testWidgets('backend location refusal preserves the approved Moment', (
    tester,
  ) async {
    repository.load = () async =>
        status(CheckinActivationState.readyToActivate);
    repository.activate = () async => throw ApiException(
      statusCode: 400,
      data: {
        'errorCode': 'CHECKIN_LOCATION_REQUIRED',
        'message': 'Please move closer to the venue.',
      },
    );
    await open(tester);
    expect(find.text('Confirm your location'), findsOneWidget);
    expect(find.textContaining('Please move closer'), findsOneWidget);
    expect(find.textContaining('do not need to upload'), findsOneWidget);
    expect(repository.checkoutCalls, 0);
    expect(result, isNull);
    await close(tester);
  });

  for (final action in ['cancel', 'logout', 'background', 'other-route']) {
    testWidgets(
      'GPS arriving after $action cannot activate a delayed check-in',
      (tester) async {
        final fix = await readLocation();
        final pendingFix = Completer<Position>();
        readLocation = () => pendingFix.future;
        repository.load = () async =>
            status(CheckinActivationState.readyToActivate);
        await open(tester);
        expect(find.text('Finishing your check-in'), findsOneWidget);
        if (action == 'cancel') {
          await tester.tap(find.text('Cancel check-in'));
          await tester.pumpAndSettle();
        } else if (action == 'logout') {
          PendingPublicMediaService.instance.clear();
        } else if (action == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
        } else {
          unawaited(
            Navigator.of(
              tester.element(find.byType(CheckinModerationPage)),
            ).push<void>(
              MaterialPageRoute(
                builder: (_) => const Scaffold(body: Text('Other screen')),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }
        pendingFix.complete(fix);
        await tester.pumpAndSettle();
        expect(repository.activationCalls, 0);
        expect(
          result,
          action == 'cancel' ? CheckinModerationFlowResult.cancelled : isNull,
        );
        await close(tester);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
      },
    );
  }

  testWidgets('resuming after a stale background GPS result reads a new fix', (
    tester,
  ) async {
    final getFreshFix = readLocation;
    final oldFix = await getFreshFix();
    final pendingFix = Completer<Position>();
    readLocation = () => pendingFix.future;
    repository.load = () async =>
        status(CheckinActivationState.readyToActivate);
    await open(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    readLocation = getFreshFix;
    pendingFix.complete(oldFix);
    await tester.pump();
    expect(repository.activationCalls, 0);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(locationCalls, 2);
    expect(repository.activationCalls, 1);
    expect(result, CheckinModerationFlowResult.approved);
    await close(tester);
  });

  testWidgets(
    'lost POST response is reconciled with status, not another upload or activation',
    (tester) async {
      repository.load = () async =>
          status(CheckinActivationState.readyToActivate);
      repository.activate = () async => throw TimeoutException('response lost');
      await open(tester);
      expect(find.text('Reconnecting'), findsOneWidget);
      expect(repository.activationCalls, 1);
      repository.load = () async =>
          status(CheckinActivationState.approved, canJoin: true);
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      expect(result, CheckinModerationFlowResult.approved);
      expect(repository.activationCalls, 1);
      expect(repository.checkoutCalls, 0);
      await close(tester);
    },
  );

  testWidgets('late activation response during cancellation cannot open room', (
    tester,
  ) async {
    final activation = Completer<CheckinActivationStatus>();
    final cancellation = Completer<void>();
    repository.load = () async =>
        status(CheckinActivationState.readyToActivate);
    repository.activate = () => activation.future;
    repository.cancel = () => cancellation.future;
    await open(tester);
    await tester.tap(find.text('Cancel check-in'));
    activation.complete(status(CheckinActivationState.approved, canJoin: true));
    await tester.pump();
    expect(result, isNull);
    cancellation.complete();
    await tester.pumpAndSettle();
    expect(result, CheckinModerationFlowResult.cancelled);
    expect(repository.activationCalls, 1);
    await close(tester);
  });

  for (final invalid in [
    status(CheckinActivationState.approved, canJoin: false),
    status(CheckinActivationState.approved, canJoin: true, id: 'other'),
    status(CheckinActivationState.readyToActivate, canJoin: true),
  ]) {
    testWidgets(
      'activation response ${invalid.state}/${invalid.checkinId}/${invalid.canJoin} cannot bypass room gate',
      (tester) async {
        repository.load = () async =>
            status(CheckinActivationState.readyToActivate);
        repository.activate = () async => invalid;
        await open(tester);
        expect(result, isNull);
        expect(repository.activationCalls, 1);
        await close(tester);
      },
    );
  }

  testWidgets('missing exact moderation receipt never activates', (
    tester,
  ) async {
    repository.load = () async =>
        status(CheckinActivationState.readyToActivate, receipt: null);
    await open(tester);
    expect(repository.activationCalls, 0);
    expect(locationCalls, 0);
    expect(result, isNull);
    await close(tester);
  });

  for (final code in [
    'CHECKIN_ACTIVATION_UNAVAILABLE',
    'CHECKIN_APPROVED_MOMENT_REQUIRED',
  ]) {
    testWidgets('$code does not retry or join automatically', (tester) async {
      repository.load = () async =>
          status(CheckinActivationState.readyToActivate);
      repository.activate = () async =>
          throw ApiException(statusCode: 400, data: {'errorCode': code});
      await open(tester);
      expect(find.text('Retake Moment'), findsOneWidget);
      await tester.pump(const Duration(minutes: 1));
      expect(repository.activationCalls, 1);
      expect(result, isNull);
      await close(tester);
    });
  }
}
