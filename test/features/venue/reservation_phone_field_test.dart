import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/phone_country_picker.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';
import 'package:kmstry_frontend/features/venue/presentation/reservation_phone_field.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_phone_editor.dart';

void main() {
  test(
    'restoring or pasting an international number never doubles its prefix',
    () {
      final phone = ReservationPhoneController(
        initialPhone: '+44 20 7946 0001',
      );
      addTearDown(phone.dispose);
      expect(phone.country.code, 'GB');
      expect(phone.number.text, '2079460001');
      expect(phone.fullNumber, '+442079460001');
      phone.number.text = '+971 50 123 4567';
      expect(phone.country.code, 'AE');
      expect(phone.number.text, '501234567');
      expect(phone.fullNumber, '+971501234567');
      phone.number.text = '0044 20 7946 0002';
      expect(phone.country.code, 'GB');
      expect(phone.fullNumber, '+442079460002');
    },
  );

  test(
    'selected code combines with national input, empty input remains required',
    () {
      final phone = ReservationPhoneController();
      addTearDown(phone.dispose);
      expect(
        reservationPhoneError(phone.fullNumber),
        'Please enter your reservations phone number.',
      );
      phone.number.text = '050 123 4567';
      expect(phone.fullNumber, '+971501234567');
      phone.selectCountry(phoneCountries.firstWhere((c) => c.code == 'GB'));
      phone.number.text = '020 7946 0001';
      expect(phone.fullNumber, '+442079460001');
      phone.number.text = '*123#';
      expect(normalizeReservationPhone(phone.fullNumber), isNull);
      phone.clear();
      expect(phone.fullNumber, '');
    },
  );

  test(
    'shared codes preserve the selected country and unknown codes remain intact',
    () {
      final phone = ReservationPhoneController();
      addTearDown(phone.dispose);
      phone.selectCountry(phoneCountries.firstWhere((c) => c.code == 'CA'));
      phone.number.text = '+1 202 555 0123';
      expect(phone.country.code, 'CA');
      expect(phone.fullNumber, '+12025550123');
      phone.setInternationalNumber('+212512345678');
      expect(phone.country, internationalPhoneCountry);
      expect(phone.fullNumber, '+212512345678');
      phone.selectCountry(phoneCountries.firstWhere((c) => c.code == 'AE'));
      expect(phone.fullNumber, '');
      phone.number.text = '050 123 4567';
      expect(phone.fullNumber, '+971501234567');
    },
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final dark in [false, true]) {
      testWidgets(
        'profile country picker saves joined number on $platform dark=$dark',
        (tester) async {
          tester.view.physicalSize = const Size(390, 844);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          String? saved;
          await tester.pumpWidget(
            MaterialApp(
              theme: (dark ? AppTheme.darkTheme : AppTheme.lightTheme).copyWith(
                platform: platform,
              ),
              home: Scaffold(
                body: VenuePhoneEditor(
                  initialPhone: '+442079460001',
                  onSave: (value) async {
                    saved = value;
                  },
                ),
              ),
            ),
          );
          final picker = find.byKey(
            const ValueKey('edit-reservation-phone-country'),
          );
          expect(
            find.descendant(of: picker, matching: find.text('+44')),
            findsOneWidget,
          );
          expect(find.text('2079460001'), findsOneWidget);
          await tester.tap(picker);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byWidgetPredicate(
              (w) =>
                  w is TextField &&
                  w.decoration?.hintText == 'Search country or code...',
            ),
            'Turkey',
          );
          await tester.pumpAndSettle();
          await tester.tap(find.widgetWithText(ListTile, 'Turkey'));
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byKey(const ValueKey('edit-reservation-phone')),
            '0212 555 123',
          );
          await tester.tap(find.text('Save changes'));
          await tester.pumpAndSettle();
          expect(saved, isNull);
          expect(
            find.text(
              'Enter a valid reservations phone number for the selected country.',
            ),
            findsOneWidget,
          );
          expect(find.text('0212 555 123'), findsOneWidget);
          await tester.enterText(
            find.byKey(const ValueKey('edit-reservation-phone')),
            '0212 555 1234',
          );
          await tester.tap(find.text('Save changes'));
          await tester.pumpAndSettle();
          expect(saved, '+902125551234');
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
