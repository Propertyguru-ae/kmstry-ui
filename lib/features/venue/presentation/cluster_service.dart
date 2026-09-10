import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

class VenueClusterNode {
  final String id;
  final LatLng position;
  final List<Venue> venues;
  final bool containsSelected;

  const VenueClusterNode({
    required this.id,
    required this.position,
    required this.venues,
    required this.containsSelected,
  });

  bool get isCluster => venues.length > 6;
  int get count => venues.length;
  Venue get primaryVenue => venues.first;
}

class VenueClusterService {
  const VenueClusterService();

  List<VenueClusterNode> buildClusters({
    required List<Venue> venues,
    required LatLngBounds visibleBounds,
    required double zoom,
    String? selectedVenueId,
  }) {
    if (venues.isEmpty) return const [];

    final cellSizePx = _cellSizeForZoom(zoom);
    final zoomScale = math.pow(2.0, zoom).toDouble();
    final buckets = <String, _Bucket>{};

    for (final venue in venues) {
      if (!_hasValidLocation(venue)) continue;
      if (!_isInBoundsWithPadding(venue, visibleBounds)) continue;

      final point = _project(venue.latitude, venue.longitude, zoomScale);
      final gx = (point.dx / cellSizePx).floor();
      final gy = (point.dy / cellSizePx).floor();
      final key = '$gx:$gy';

      final bucket = buckets.putIfAbsent(key, () => _Bucket(gx: gx, gy: gy));
      bucket.add(venue, selectedVenueId: selectedVenueId);
    }

    final nodes =
        buckets.entries
            .map((entry) => entry.value.toNode(idPrefix: entry.key, zoom: zoom))
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    return nodes;
  }

  bool _hasValidLocation(Venue venue) {
    return venue.latitude.isFinite &&
        venue.longitude.isFinite &&
        venue.latitude >= -90 &&
        venue.latitude <= 90 &&
        venue.longitude >= -180 &&
        venue.longitude <= 180 &&
        !(venue.latitude == 0 && venue.longitude == 0);
  }

  bool _isInBoundsWithPadding(Venue venue, LatLngBounds bounds) {
    final latPad =
        (bounds.northeast.latitude - bounds.southwest.latitude).abs() * 0.15;
    final lngPad = _longitudeSpan(bounds) * 0.15;

    final minLat = bounds.southwest.latitude - latPad;
    final maxLat = bounds.northeast.latitude + latPad;
    final venueLng = venue.longitude;
    final minLng = bounds.southwest.longitude - lngPad;
    final maxLng = bounds.northeast.longitude + lngPad;

    final inLat = venue.latitude >= minLat && venue.latitude <= maxLat;
    final inLng = _isLongitudeInRange(venueLng, minLng, maxLng);
    return inLat && inLng;
  }

  bool _isLongitudeInRange(double lng, double minLng, double maxLng) {
    var normalizedMin = _normalizeLongitude(minLng);
    var normalizedMax = _normalizeLongitude(maxLng);
    final normalizedLng = _normalizeLongitude(lng);

    if (normalizedMin <= normalizedMax) {
      return normalizedLng >= normalizedMin && normalizedLng <= normalizedMax;
    }
    // Antimeridian crossing
    return normalizedLng >= normalizedMin || normalizedLng <= normalizedMax;
  }

  double _normalizeLongitude(double lng) {
    var value = lng;
    while (value > 180) {
      value -= 360;
    }
    while (value < -180) {
      value += 360;
    }
    return value;
  }

  double _longitudeSpan(LatLngBounds bounds) {
    final sw = bounds.southwest.longitude;
    final ne = bounds.northeast.longitude;
    if (ne >= sw) return ne - sw;
    return (180 - sw) + (ne + 180);
  }

  _ProjectedPoint _project(double lat, double lng, double zoomScale) {
    final sinLat = math.sin(lat * math.pi / 180.0).clamp(-0.9999, 0.9999);
    final x = 256.0 * (0.5 + lng / 360.0) * zoomScale;
    final y =
        256.0 *
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) *
        zoomScale;
    return _ProjectedPoint(x, y);
  }

  double _cellSizeForZoom(double zoom) {
    if (zoom >= 17) return 48;
    if (zoom >= 15) return 72;
    if (zoom >= 13) return 96;
    if (zoom >= 11) return 132;
    if (zoom >= 9) return 176;
    return 230;
  }
}

class _ProjectedPoint {
  final double dx;
  final double dy;
  const _ProjectedPoint(this.dx, this.dy);
}

class _Bucket {
  final int gx;
  final int gy;
  final List<Venue> items = [];
  double _latSum = 0;
  double _lngSum = 0;
  bool _containsSelected = false;

  _Bucket({required this.gx, required this.gy});

  void add(Venue venue, {String? selectedVenueId}) {
    items.add(venue);
    _latSum += venue.latitude;
    _lngSum += venue.longitude;
    if (selectedVenueId != null && venue.id == selectedVenueId) {
      _containsSelected = true;
    }
  }

  VenueClusterNode toNode({required String idPrefix, required double zoom}) {
    final sorted = List<Venue>.from(items)
      ..sort((a, b) => _stableVenueId(a).compareTo(_stableVenueId(b)));
    final center = LatLng(_latSum / items.length, _lngSum / items.length);
    final idsPart = sorted.map(_stableVenueId).join('|');
    final id = 'z${zoom.floor()}::$idPrefix::$idsPart';

    return VenueClusterNode(
      id: id,
      position: center,
      venues: sorted,
      containsSelected: _containsSelected,
    );
  }

  String _stableVenueId(Venue venue) {
    if (venue.id.isNotEmpty) return venue.id;
    if ((venue.placeId ?? '').isNotEmpty) return venue.placeId!;
    return '${venue.name}_${venue.latitude}_${venue.longitude}_$gx:$gy';
  }
}
