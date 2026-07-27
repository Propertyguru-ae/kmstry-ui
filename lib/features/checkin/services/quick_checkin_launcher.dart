import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/checkin/presentation/nearby_venue_sheet.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';

/// Quick check-in entry point shared by the Personal home CTA and the navbar
/// centre icon. It decides between two paths (see [_shouldAutoSelect]):
///
///  * **1 tap** — a single unambiguous nearby venue with a good GPS fix:
///    resolve it and open the check-in page directly, no sheet.
///  * **2 taps** — multiple close candidates or a weak GPS fix: open the
///    "You're nearby — select your venue" bottom sheet with the closest one
///    pre-highlighted.
///
/// The backend 200 m distance guard on check-in creation stays the source of
/// truth; these thresholds only govern the UX decision, never authorization.
class QuickCheckinLauncher {
  QuickCheckinLauncher({
    VenueRepository? venueRepository,
    VenueContextRepository? venueContextRepository,
    LocationPermissionService? locationPermissionService,
  })  : _venues = venueRepository ?? VenueRepository(),
        _venueContext = venueContextRepository ?? VenueContextRepository(),
        _permission =
            locationPermissionService ?? LocationPermissionService();

  final VenueRepository _venues;
  final VenueContextRepository _venueContext;
  final LocationPermissionService _permission;

  // ── UX decision thresholds (not security — the backend 200 m guard is) ──
  /// Closest venue must be within this to auto-open without the sheet.
  static const double _autoSelectMaxDistanceMeters = 25;

  /// The runner-up must be at least this far to consider the pick unambiguous.
  static const double _autoSelectRunnerUpMinMeters = 75;

  /// GPS fix must be at least this accurate to trust an auto-pick.
  static const double _maxAccuracyMeters = 30;

  /// Only venues within this are eligible to check into (matches backend guard).
  static const double _checkinMaxDistanceMeters = 200;

  /// Candidate fetch radius — a bit wider than the guard so the sheet can also
  /// surface "just outside range" venues (shown disabled by the sheet).
  static const int _searchRadiusMeters = 300;

  /// Entry point. Acquires location, fetches nearby venues, then either opens
  /// the check-in page directly or the selection sheet.
  Future<void> launch(BuildContext context) async {
    final hasPermission = await _ensurePermission(context);
    if (!hasPermission || !context.mounted) return;

    Position? position = await Geolocator.getLastKnownPosition();
    position ??= await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
    if (!context.mounted) return;

    List<Venue> markers;
    try {
      markers = await _venues.getMapMarkers(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _searchRadiusMeters,
        limit: 60,
      );
    } catch (_) {
      if (!context.mounted) return;
      _showSnack(context, 'Could not load nearby venues. Try again.');
      return;
    }
    if (!context.mounted) return;

    // Keep only venues with a known distance, sorted closest-first.
    final candidates =
        markers.where((v) => v.distanceMeters != null).toList()
          ..sort(
            (a, b) => a.distanceMeters!.compareTo(b.distanceMeters!),
          );

    final eligible = candidates
        .where((v) => v.distanceMeters! <= _checkinMaxDistanceMeters)
        .toList();

    if (eligible.isEmpty) {
      if (!context.mounted) return;
      _showSnack(
        context,
        "No venue found within range. Move closer and try again.",
      );
      return;
    }

    if (_shouldAutoSelect(eligible, position.accuracy)) {
      await _openCheckin(context, eligible.first);
      return;
    }

    if (!context.mounted) return;
    final chosen = await showNearbyVenueSheet(
      context,
      venues: eligible,
      checkinMaxDistanceMeters: _checkinMaxDistanceMeters.toInt(),
    );
    if (chosen == null || !context.mounted) return;
    await _openCheckin(context, chosen);
  }

  /// 1-tap fast path: closest venue is clearly the one, and the GPS fix is
  /// trustworthy. All three must hold, otherwise fall back to the sheet.
  bool _shouldAutoSelect(List<Venue> eligible, double accuracy) {
    final nearest = eligible.first;
    final nearestDistance = nearest.distanceMeters!.toDouble();
    if (accuracy > _maxAccuracyMeters) return false;
    if (nearestDistance > _autoSelectMaxDistanceMeters) return false;
    if (eligible.length > 1) {
      final runnerUp = eligible[1].distanceMeters!.toDouble();
      if (runnerUp <= _autoSelectRunnerUpMinMeters) return false;
    }
    return true;
  }

  /// Resolves a checkinable venue id (DB venues use their id directly;
  /// Google-only venues are materialized via resolveVenueFromPlace) and opens
  /// the check-in capture page.
  Future<void> _openCheckin(BuildContext context, Venue venue) async {
    String? venueId;
    try {
      venueId = await _resolveVenueId(venue);
    } catch (_) {
      venueId = null;
    }
    if (venueId == null || venueId.isEmpty) {
      if (context.mounted) {
        _showSnack(context, 'Could not prepare this venue for check-in.');
      }
      return;
    }
    if (!context.mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CheckInPage(
          venueId: venueId!,
          venueLatitude: venue.latitude,
          venueLongitude: venue.longitude,
        ),
      ),
    );
  }

  Future<String> _resolveVenueId(Venue venue) async {
    if (venue.id.isNotEmpty && venue.canCheckin) {
      return venue.id;
    }
    final placeId = venue.placeId;
    if (placeId == null || placeId.isEmpty) {
      if (venue.id.isNotEmpty) return venue.id;
      throw Exception('Venue reference is missing');
    }
    final response = await _venueContext.resolveVenueFromPlace(placeId);
    final resolved = _extractVenueId(response);
    if (resolved == null || resolved.isEmpty) {
      throw Exception('Could not resolve venue id from place');
    }
    return resolved;
  }

  String? _extractVenueId(Map<String, dynamic> response) {
    final direct =
        response['venueId'] ?? response['venue_id'] ?? response['id'];
    if (direct is String && direct.isNotEmpty) return direct;
    final venue = response['venue'];
    if (venue is Map) {
      final nestedId = venue['id'] ?? venue['venueId'] ?? venue['venue_id'];
      if (nestedId is String && nestedId.isNotEmpty) return nestedId;
    }
    return null;
  }

  Future<bool> _ensurePermission(BuildContext context) async {
    var status = await _permission.status();
    if (!status.isGranted) {
      status = await _permission.request();
    }
    if (status.isGranted) return true;
    if (!context.mounted) return false;
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Location required'),
        content: const Text(
          'Location permission is required to find venues near you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              openAppSettings();
              Navigator.pop(context);
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
    return false;
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
