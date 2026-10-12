import 'package:geolocator/geolocator.dart';

import '../location/checkin_location_policy.dart';

typedef RenewalPosition = ({double lat, double lng});

bool isFreshRenewalPosition(Position position, DateTime now) {
  final age = now.difference(position.timestamp);
  return age <= const Duration(minutes: 1) &&
      age >= const Duration(seconds: -10) &&
      position.accuracy.isFinite &&
      position.accuracy >= 0 &&
      position.accuracy <= 75 &&
      position.latitude.isFinite &&
      position.latitude.abs() <= 90 &&
      position.longitude.isFinite &&
      position.longitude.abs() <= 180;
}

class CheckinRenewalInfo {
  final String checkinId;
  final String venueId;
  final String? venueName;
  final DateTime? expiresAt;
  final RenewalPosition? position;
  final String? userId;

  const CheckinRenewalInfo({
    required this.checkinId,
    required this.venueId,
    this.venueName,
    this.expiresAt,
    this.position,
    this.userId,
  });

  static const renewalWindow = Duration(hours: 6);

  bool isWithinWindow(DateTime now) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    final elapsed = now.difference(expiry);
    return !elapsed.isNegative && elapsed <= renewalWindow;
  }

  bool isNear(RenewalPosition? here) {
    final anchor = position;
    if (anchor == null || here == null) return false;
    if (![
          anchor.lat,
          anchor.lng,
          here.lat,
          here.lng,
        ].every((n) => n.isFinite) ||
        anchor.lat.abs() > 90 ||
        here.lat.abs() > 90 ||
        anchor.lng.abs() > 180 ||
        here.lng.abs() > 180) {
      return false;
    }
    return Geolocator.distanceBetween(
          anchor.lat,
          anchor.lng,
          here.lat,
          here.lng,
        ) <=
        CheckinLocationPolicy.maxDistanceMeters;
  }
}
