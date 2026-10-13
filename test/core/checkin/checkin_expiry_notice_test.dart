import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/checkin/checkin_expiry_notice.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ended_card.dart';
import 'package:kmstry_frontend/core/checkin/checkin_renewal_info.dart';

void main() {
  late CheckinExpiryNotice notices;
  const info = CheckinRenewalInfo(
    checkinId: 'old',
    venueId: 'cafe',
    userId: 'hilal',
  );
  void context({
    String? user = 'hilal',
    int session = 1,
    bool personal = true,
    bool foreground = true,
  }) => notices.setContext(
    userId: user,
    session: session,
    personal: personal,
    foreground: foreground,
  );
  setUp(() => notices = CheckinExpiryNotice());
  tearDown(() => notices.dispose());

  test('one dismissible notice for a live personal expiry', () {
    context();
    notices.offer(info, hasActiveCheckin: false);
    expect(notices.current, info);
    notices.dismiss();
    notices.offer(info, hasActiveCheckin: false);
    expect(notices.current, isNull);
  });
  test('venue expiry is not queued for returning to personal', () {
    context(personal: false);
    notices.offer(info, hasActiveCheckin: false);
    context();
    notices.offer(info, hasActiveCheckin: false);
    expect(notices.current, isNull);
  });
  test('unresolved account does not show or queue the notice', () {
    context(user: null, personal: false);
    notices.offer(info, hasActiveCheckin: false);
    context();
    expect(notices.current, isNull);
  });
  test('background expiry is not replayed on resume', () {
    context(foreground: false);
    notices.offer(info, hasActiveCheckin: false);
    context();
    notices.offer(info, hasActiveCheckin: false);
    expect(notices.current, isNull);
  });
  test('new check-in and another owner cannot trigger the card', () {
    context();
    notices.offer(info, hasActiveCheckin: true);
    expect(notices.current, isNull);
    context(user: 'zeynep');
    notices.offer(info, hasActiveCheckin: false);
    expect(notices.current, isNull);
  });
  for (final change in [
    'venue',
    'logout',
    'background',
    'new-checkin',
    'dismiss',
  ]) {
    test(
      '$change immediately invalidates a pending location/button action',
      () {
        context();
        notices.offer(info, hasActiveCheckin: false);
        final attempt = notices.revision;
        expect(notices.isCurrent(info, attempt), isTrue);
        switch (change) {
          case 'venue':
            context(personal: false);
          case 'logout':
            context(user: null, session: 2);
          case 'background':
            context(foreground: false);
          default:
            notices.dismiss();
        }
        expect(notices.current, isNull);
        expect(notices.isCurrent(info, attempt), isFalse);
        context();
        expect(notices.current, isNull);
        expect(notices.isCurrent(info, attempt), isFalse);
      },
    );
  }
  testWidgets(
    'card wraps on a narrow screen with large text and has no renew action',
    (tester) async {
      var starts = 0;
      var closes = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 280,
                child: MediaQuery(
                  data: const MediaQueryData(
                    textScaler: TextScaler.linear(1.7),
                  ),
                  child: CheckinEndedCard(
                    onCheckin: () => starts++,
                    onDismiss: () => closes++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Renew'), findsNothing);
      await tester.tap(find.text('Check in again'));
      await tester.tap(find.byTooltip('Dismiss'));
      expect(starts, 1);
      expect(closes, 1);
    },
  );
}
