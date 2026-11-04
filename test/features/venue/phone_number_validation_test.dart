import 'package:flutter_test/flutter_test.dart';
import 'package:kmstry_frontend/core/utils/phone_number_validation.dart';
import 'package:kmstry_frontend/features/venue/data/reservation_phone.dart';

void main() {
  for (final phone in [
    '+971501234567',
    '+97142345678',
    '+902125551234',
    '+905321234567',
    '+9611234567',
    '+96171123456',
    '+442079460001',
    '+12025550123',
  ]) {
    test('both fields accept valid mobile/fixed phone $phone', () {
      expect(normalizedValidPhone(phone), phone);
      expect(contactPhoneError(phone), isNull);
      expect(reservationPhoneError(phone), isNull);
    });
  }
  for (final phone in [
    '+97112345',
    '+97150123456',
    '+9715012345678',
    '+971111111111',
    '+90212555123',
    '+9053212345678',
    '+961123456',
    '+96199123456',
    '+44207946000',
    '+999123456789',
    '+120255501',
    '+97150abc4567',
    '+971501234567;1',
    '+971501234567#',
    '',
    ' ',
    '*123#',
  ]) {
    test('both fields reject invalid phone $phone', () {
      expect(normalizedValidPhone(phone), isNull);
      expect(contactPhoneError(phone), isNotNull);
      expect(reservationPhoneError(phone), isNotNull);
    });
  }
  test(
    'country metadata handles domestic prefixes and keeps significant zeros',
    () {
      expect(internationalPhoneInput('050 123 4567', 'AE'), '+971501234567');
      expect(internationalPhoneInput('04 234 5678', 'AE'), '+97142345678');
      expect(internationalPhoneInput('0212 555 1234', 'TR'), '+902125551234');
      expect(internationalPhoneInput('01 234 567', 'LB'), '+9611234567');
      expect(internationalPhoneInput('020 7946 0001', 'GB'), '+442079460001');
      expect(internationalPhoneInput('06 6982', 'IT'), '+39066982');
      expect(
        internationalPhoneInput('0044 20 7946 0001', 'AE'),
        '+442079460001',
      );
    },
  );
  test(
    'old test numbers remain readable but must be corrected on a new write',
    () {
      expect(normalizeReservationPhone('+441632960001'), '+441632960001');
      expect(reservationPhoneError('+441632960001'), isNotNull);
    },
  );
}
