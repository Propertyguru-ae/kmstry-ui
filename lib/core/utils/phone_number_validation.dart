import 'package:phone_numbers_parser/phone_numbers_parser.dart';

/// Numbering-plan checks run locally. They do not verify ownership or delivery.
String? normalizedValidPhone(String value) {
  final raw = value.trim();
  if (raw.length > 40 || !RegExp(r'^\+[0-9 ()-]+$').hasMatch(raw)) {
    return null;
  }
  try {
    final parsed = PhoneNumber.parse(raw);
    return parsed.isValid() ? parsed.international : null;
  } catch (_) {
    return null;
  }
}

/// Use country metadata for domestic prefixes (including countries that keep
/// their leading zero), rather than a hand-maintained zero-removal list.
String? internationalPhoneInput(String value, String countryCode) {
  final raw = value.trim();
  if (raw.isEmpty ||
      raw.length > 40 ||
      !RegExp(r'^\+?[0-9 ()-]+$').hasMatch(raw)) {
    return null;
  }
  try {
    final iso = IsoCode.values.where((c) => c.name == countryCode).firstOrNull;
    final international = raw.startsWith('+') || raw.startsWith('00');
    return PhoneNumber.parse(
      raw.startsWith('00') ? '+${raw.substring(2)}' : raw,
      destinationCountry: international ? null : iso,
    ).international;
  } catch (_) {
    return null;
  }
}

String? contactPhoneError(String value) {
  if (value.trim().isEmpty) return 'Please enter your contact phone number.';
  return normalizedValidPhone(value) == null
      ? 'Enter a valid contact phone number for the selected country.'
      : null;
}
