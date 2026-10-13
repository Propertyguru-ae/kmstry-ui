import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/venue/data/ping_response.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';

class _Repository extends VenueCheckinRepository {
  final result = Completer<PingResponse>();
  final started = Completer<void>();
  int calls = 0;
  @override
  Future<PingResponse> pingCheckin({
    required String checkinId,
    required double latitude,
    required double longitude,
  }) {
    calls++;
    if (!started.isCompleted) started.complete();
    return result.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repository repository;
  late CheckinPingManager manager;
  late int session;
  late String? user;
  late List<CheckinRenewalInfo> prompts;
  late int expired;
  setUp(() {
    session = 1;
    user = 'handan';
    prompts = [];
    expired = 0;
    ActiveCheckinService().clear();
    ActiveCheckinService().setActiveCheckin(
      'old',
      userId: user,
      venueId: 'venue',
    );
    repository = _Repository();
    manager = CheckinPingManager.forTest(
      repository: repository,
      getSessionGeneration: () => session,
    );
    manager.configure(
      getCurrentUserId: () async => user,
      getLocation: () async => (lat: 25.2, lng: 55.2),
      onCheckinTimedOut: prompts.add,
      onCheckinExpired: () => expired++,
    );
  });
  tearDown(() {
    manager.stop();
    ActiveCheckinService().clear();
  });
  PingResponse expiredResponse() => PingResponse(
    status: 'expired',
    nearVenue: true,
    venueId: 'venue',
    venueName: 'Cafe Alpha',
    expiresAt: DateTime(2026, 10, 6, 14),
    renewalLatitude: 25.2,
    renewalLongitude: 55.2,
  );

  test(
    'expired ping carries server expiry, owner and location anchor',
    () async {
      final flight = manager.pingNow();
      await repository.started.future;
      repository.result.complete(expiredResponse());
      await flight;
      expect(ActiveCheckinService().hasActiveCheckin, isFalse);
      expect(prompts.single.expiresAt, DateTime(2026, 10, 6, 14));
      expect(prompts.single.userId, 'handan');
      expect(prompts.single.position, (lat: 25.2, lng: 55.2));
    },
  );
  test('late expired response cannot clear a newer check-in', () async {
    final flight = manager.pingNow();
    await repository.started.future;
    ActiveCheckinService().setActiveCheckin('new', userId: user);
    repository.result.complete(expiredResponse());
    await flight;
    expect(ActiveCheckinService().activeCheckinId, 'new');
    expect(prompts, isEmpty);
    expect(expired, 0);
  });
  test('owner hydration does not discard a valid expiry response', () async {
    final active = ActiveCheckinService();
    active.clear();
    active.setActiveCheckin('old', venueId: 'venue');
    final flight = manager.pingNow();
    await repository.started.future;
    active.syncForUser(userId: user, checkinId: 'old', venueId: 'venue');
    repository.result.complete(expiredResponse());
    await flight;
    expect(active.hasActiveCheckin, isFalse);
    expect(prompts.single.userId, user);
  });
  test('logout/session switch invalidates an in-flight ping', () async {
    final flight = manager.pingNow();
    await repository.started.future;
    session++;
    user = 'another-user';
    ActiveCheckinService().setActiveCheckin('another', userId: user);
    repository.result.complete(expiredResponse());
    await flight;
    expect(ActiveCheckinService().activeCheckinId, 'another');
    expect(prompts, isEmpty);
  });
  test(
    'late invalid-state error does not clear a new account check-in',
    () async {
      final flight = manager.pingNow();
      await repository.started.future;
      ActiveCheckinService().setActiveCheckin('new', userId: 'new-owner');
      repository.result.completeError(Exception('not found'));
      await flight;
      expect(ActiveCheckinService().activeCheckinId, 'new');
    },
  );
  test(
    'stop invalidates even an otherwise unchanged active check-in',
    () async {
      final flight = manager.pingNow();
      await repository.started.future;
      manager.stop();
      repository.result.complete(expiredResponse());
      await flight;
      expect(ActiveCheckinService().activeCheckinId, 'old');
      expect(prompts, isEmpty);
    },
  );
  test(
    'concurrent ticks share one ping and missing user skips safely',
    () async {
      final flight = manager.pingNow();
      await repository.started.future;
      await manager.pingNow();
      expect(repository.calls, 1);
      repository.result.complete(PingResponse(status: 'active'));
      await flight;
      user = null;
      await manager.pingNow();
      expect(repository.calls, 1);
      expect(ActiveCheckinService().activeCheckinId, 'old');
    },
  );
  test('old backend response without true expiry cannot renew', () async {
    final flight = manager.pingNow();
    await repository.started.future;
    repository.result.complete(
      PingResponse(status: 'expired', nearVenue: true, venueId: 'venue'),
    );
    await flight;
    expect(prompts, isEmpty);
    expect(expired, 1);
  });
  test(
    'GPS wait from an old check-in cannot start a ping for a new one',
    () async {
      final gps = Completer<({double lat, double lng})>();
      manager.configure(
        getCurrentUserId: () async => user,
        getLocation: () => gps.future,
        onCheckinTimedOut: prompts.add,
      );
      final flight = manager.pingNow();
      await Future<void>.delayed(Duration.zero);
      ActiveCheckinService().setActiveCheckin('new', userId: user);
      gps.complete((lat: 25.2, lng: 55.2));
      await flight;
      expect(repository.calls, 0);
      expect(prompts, isEmpty);
    },
  );
}
