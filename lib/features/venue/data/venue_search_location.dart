import 'package:geolocator/geolocator.dart';

class VenueSearchLocation {
  final double latitude;
  final double longitude;

  const VenueSearchLocation(this.latitude, this.longitude);
}

/// Optional search relevance hint, not check-in/ownership verification.
/// Never requests permission and never prevents a name/address search.
class VenueSearchLocationResolver {
  final GeolocatorPlatform _geolocator;

  VenueSearchLocationResolver({GeolocatorPlatform? geolocator})
    : _geolocator = geolocator ?? GeolocatorPlatform.instance;

  Future<VenueSearchLocation?> resolve() async {
    try {
      return await _resolve().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Denied permission, disabled services, timeout, or unavailable plugin.
      return null;
    }
  }

  Future<VenueSearchLocation?> _resolve() async {
    final permission = await _geolocator.checkPermission();
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    if (!await _geolocator.isLocationServiceEnabled()) return null;

    Position? cached;
    try {
      cached = await _geolocator.getLastKnownPosition();
    } catch (_) {
      // Some platforms have no last-known position. Try one bounded reading.
    }
    if (_usable(cached)) return _coordinates(cached!);

    final current = await _geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 3),
      ),
    );
    return _usable(current) ? _coordinates(current) : null;
  }

  bool _usable(Position? position) {
    if (position == null) return false;
    final age = DateTime.now().difference(position.timestamp);
    return position.latitude.isFinite &&
        position.longitude.isFinite &&
        position.latitude.abs() <= 90 &&
        position.longitude.abs() <= 180 &&
        !(position.latitude == 0 && position.longitude == 0) &&
        age >= const Duration(minutes: -1) &&
        age <= const Duration(minutes: 15);
  }

  VenueSearchLocation _coordinates(Position position) =>
      VenueSearchLocation(position.latitude, position.longitude);
}
