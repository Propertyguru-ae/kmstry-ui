import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/features/venue/data/venue_search_location.dart';

class _Geo extends GeolocatorPlatform {
  LocationPermission permission = LocationPermission.whileInUse;
  bool enabled = true;
  Position? cached;
  Position? current;
  int reads = 0;
  int requests = 0;
  LocationSettings? settings;

  @override
  Future<LocationPermission> checkPermission() async => permission;
  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    throw StateError('Must not request permission');
  }

  @override
  Future<bool> isLocationServiceEnabled() async => enabled;
  @override
  Future<Position?> getLastKnownPosition({
    bool forceLocationManager = false,
  }) async => cached;
  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    reads++;
    settings = locationSettings;
    if (current == null) throw StateError('Location unavailable');
    return current!;
  }
}

Position _position({Duration age = Duration.zero, double latitude = 25.2048}) =>
    Position.fromMap({
      'latitude': latitude,
      'longitude': 55.2708,
      'timestamp': DateTime.now().subtract(age).millisecondsSinceEpoch,
      'accuracy': 100.0,
    });

void main() {
  for (final permission in [
    LocationPermission.denied,
    LocationPermission.deniedForever,
    LocationPermission.unableToDetermine,
  ]) {
    test('permission $permission does not prompt or read GPS', () async {
      final geo = _Geo()..permission = permission;
      expect(
        await VenueSearchLocationResolver(geolocator: geo).resolve(),
        isNull,
      );
      expect(geo.requests, 0);
      expect(geo.reads, 0);
    });
  }
  test('disabled services do not prompt or block search', () async {
    final geo = _Geo()..enabled = false;
    expect(
      await VenueSearchLocationResolver(geolocator: geo).resolve(),
      isNull,
    );
    expect(geo.requests, 0);
    expect(geo.reads, 0);
  });
  test('uses a recent cached position without another GPS reading', () async {
    final geo = _Geo()..cached = _position();
    final result = await VenueSearchLocationResolver(geolocator: geo).resolve();
    expect(result?.latitude, 25.2048);
    expect(result?.longitude, 55.2708);
    expect(geo.reads, 0);
    expect(geo.requests, 0);
  });
  test('replaces old cached location with a bounded current reading', () async {
    final geo = _Geo()
      ..cached = _position(age: const Duration(days: 1), latitude: 51.5)
      ..current = _position();
    final result = await VenueSearchLocationResolver(geolocator: geo).resolve();
    expect(result?.latitude, 25.2048);
    expect(geo.reads, 1);
    expect(geo.settings?.timeLimit, const Duration(seconds: 3));
    expect(geo.requests, 0);
  });
  test('unavailable GPS gracefully yields no bias', () async {
    expect(
      await VenueSearchLocationResolver(geolocator: _Geo()).resolve(),
      isNull,
    );
  });
  test('invalid coordinates are not sent', () async {
    final geo = _Geo()..current = _position(latitude: double.nan);
    expect(
      await VenueSearchLocationResolver(geolocator: geo).resolve(),
      isNull,
    );
  });
}
