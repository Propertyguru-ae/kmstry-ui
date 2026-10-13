import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/venue/visible_venue_read.dart';

void main() {
  test(
    'fresh return needs no read; stale return refreshes without a timer',
    () async {
      var time = DateTime(2026, 10, 6);
      var calls = 0;
      final gate = VisibleVenueRead(
        now: () => time,
        isVisible: () => true,
        read: () async {
          calls++;
          return true;
        },
      );
      await gate.activate();
      await gate.activate();
      time = time.add(const Duration(seconds: 9));
      await gate.activate();
      expect(calls, 1);
      time = time.add(const Duration(seconds: 1));
      await gate.activate();
      expect(calls, 2);
      gate.dispose();
    },
  );

  test('hidden changes coalesce and flush only when visible', () async {
    var visible = false;
    var calls = 0;
    final gate = VisibleVenueRead(
      isVisible: () => visible,
      read: () async {
        calls++;
        return true;
      },
    );
    await gate.invalidate();
    await gate.invalidate();
    await gate.activate();
    expect(calls, 0);
    visible = true;
    await gate.activate();
    expect(calls, 1);
    gate.dispose();
  });

  test(
    'parallel activations share a read; writes during it cause exactly one trailing fresh read',
    () async {
      var calls = 0;
      final first = Completer<bool>();
      final gate = VisibleVenueRead(
        isVisible: () => true,
        read: () {
          calls++;
          return calls == 1 ? first.future : Future.value(true);
        },
      );
      final a = gate.activate();
      final b = gate.activate();
      gate.invalidate();
      gate.invalidate();
      expect(calls, 1);
      first.complete(true);
      await Future.wait([a, b]);
      expect(calls, 2);
      gate.dispose();
    },
  );

  test(
    'going hidden during a read retains dirty work without starting another request',
    () async {
      var visible = true;
      var calls = 0;
      final first = Completer<bool>();
      final gate = VisibleVenueRead(
        isVisible: () => visible,
        read: () {
          calls++;
          return calls == 1 ? first.future : Future.value(true);
        },
      );
      final work = gate.activate();
      gate.invalidate();
      visible = false;
      first.complete(true);
      await work;
      expect(calls, 1);
      visible = true;
      await gate.activate();
      expect(calls, 2);
      gate.dispose();
    },
  );

  for (final throws in [false, true]) {
    test(
      'failure has no automatic retry loop and retries on next activation (throws=$throws)',
      () async {
        var calls = 0;
        final gate = VisibleVenueRead(
          isVisible: () => true,
          read: () async {
            calls++;
            if (calls == 1) {
              if (throws) throw StateError('network');
              return false;
            }
            return true;
          },
        );
        await gate.activate();
        expect(calls, 1);
        expect(gate.needsRefresh, true);
        await gate.activate();
        expect(calls, 2);
        expect(gate.needsRefresh, false);
        gate.dispose();
      },
    );
  }

  test(
    'reset starts a new scope; late former work cannot complete or clear the new gate',
    () async {
      final old = Completer<bool>();
      final current = Completer<bool>();
      var calls = 0;
      final gate = VisibleVenueRead(
        isVisible: () => true,
        read: () => ++calls == 1 ? old.future : current.future,
      );
      final a = gate.activate();
      gate.reset();
      final b = gate.activate();
      old.complete(true);
      await a;
      final c = gate.activate();
      expect(calls, 2);
      current.complete(true);
      await Future.wait([b, c]);
      expect(gate.needsRefresh, false);
      gate.dispose();
    },
  );

  test('disposal consumes late failure without a trailing read', () async {
    final late = Completer<bool>();
    var calls = 0;
    final gate = VisibleVenueRead(
      isVisible: () => true,
      read: () {
        calls++;
        return late.future;
      },
    );
    final work = gate.activate();
    gate.invalidate();
    gate.dispose();
    late.completeError(StateError('late'));
    await work;
    await gate.invalidate();
    expect(calls, 1);
  });
}
