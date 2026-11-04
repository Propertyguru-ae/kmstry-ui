import 'package:kmstry_frontend/core/utils/phone_number_validation.dart';

/// Safe display/call format for stored and Google numbers, including old data.
String? normalizeReservationPhone(String value) {
  final raw = value.trim();
  if (raw.length > 40) return null;
  final phone = raw.replaceAll(RegExp(r'[ ()-]'), '');
  return RegExp(r'^\+[1-9][0-9]{6,14}$').hasMatch(phone) ? phone : null;
}

String? reservationPhoneError(String? value) {
  if (value == null || value.trim().isEmpty) {
    return 'Please enter your reservations phone number.';
  }
  return normalizedValidPhone(value) == null
      ? 'Enter a valid reservations phone number for the selected country.'
      : null;
}

class VenuePhone {
  final String? phone;
  final bool fromGoogle;
  final List<({String name, Uri? uri})> attributions;
  const VenuePhone({
    this.phone,
    this.fromGoogle = false,
    this.attributions = const [],
  });

  factory VenuePhone.fromJson(Map<String, dynamic> json) => VenuePhone(
    phone: normalizeReservationPhone(json['phone']?.toString() ?? ''),
    fromGoogle: json['source'] == 'google',
    attributions: (json['attributions'] as List? ?? [])
        .whereType<Map>()
        .map((a) {
          final uri = Uri.tryParse(a['uri']?.toString() ?? '');
          return (
            name: a['displayName']?.toString() ?? '',
            uri: uri?.scheme == 'https' ? uri : null,
          );
        })
        .where((a) => a.name.isNotEmpty)
        .toList(),
  );
}
