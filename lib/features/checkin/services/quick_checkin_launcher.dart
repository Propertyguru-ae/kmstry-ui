import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:kmstry_frontend/core/location/checkin_location_policy.dart';
import 'package:kmstry_frontend/core/network/network_error.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/ui/branded_notice.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/checkin/presentation/nearby_venue_sheet.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';

/// Quick check-in entry point shared by the Personal home CTA and the navbar
/// centre icon. It decides between two paths (see [_shouldAutoSelect]):
///
///  * **1 tap** — a single unambiguous nearby venue with a good GPS fix:
///    resolve it and open the check-in page directly, no sheet.
///  * **2 taps** — multiple close candidates or a weak GPS fix: open the
///    "You're nearby — select your venue" bottom sheet with the closest one
///    pre-highlighted.
///
/// The backend 100 m distance guard on check-in creation stays the source of
/// truth; these thresholds only govern the UX decision, never authorization.
class QuickCheckinLauncher {
  QuickCheckinLauncher({
    VenueRepository? venueRepository,
    VenueContextRepository? venueContextRepository,
    LocationPermissionService? locationPermissionService,
  }) : _venues = venueRepository ?? VenueRepository(),
       _venueContext = venueContextRepository ?? VenueContextRepository(),
       _permission = locationPermissionService ?? LocationPermissionService();

  final VenueRepository _venues;
  final VenueContextRepository _venueContext;
  final LocationPermissionService _permission;
  final VenueCheckinRepository _checkinRepo = VenueCheckinRepository();

  // ── UX decision thresholds (not security — the backend 100 m guard is) ──
  /// Closest venue must be within this to auto-open without the sheet.
  static const double _autoSelectMaxDistanceMeters = 25;

  /// The runner-up must be at least this far to consider the pick unambiguous.
  static const double _autoSelectRunnerUpMinMeters = 75;

  /// GPS fix must be at least this accurate to trust an auto-pick.
  static const double _maxAccuracyMeters = 30;

  /// Only venues within this are eligible to check into (matches backend guard).
  static const double _checkinMaxDistanceMeters =
      CheckinLocationPolicy.maxDistanceMeters;

  /// Candidate fetch radius — a bit wider than the guard so the sheet can also
  /// surface "just outside range" venues (shown disabled by the sheet).
  static const int _searchRadiusMeters = 300;

  /// Entry point. Acquires location, fetches nearby venues, then either opens
  /// Her tap yeni bir [QuickCheckinLauncher] örneği oluşturuyor; bu yüzden
  /// yeniden girişi örnek düzeyinde değil, statik bir bayrakla engelliyoruz —
  /// navbar iconuna üst üste basılınca üst üste sheet açılmasın.
  static bool _inFlight = false;

  /// the check-in page directly or the selection sheet.
  Future<void> launch(BuildContext context) async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      await _launch(context);
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _launch(BuildContext context) async {
    final hasPermission = await _ensurePermission(context);
    if (!hasPermission || !context.mounted) return;

    // Tap'ın hemen ardından anında geri bildirim: hafif loading sheet aç.
    // Konum + yakın mekan çağrıları sürerken kullanıcı boş ekran görmesin.
    final dismissLoading = showNearbyLoadingSheet(context);
    var loadingClosed = false;
    void closeLoading() {
      if (loadingClosed) return;
      loadingClosed = true;
      dismissLoading();
    }

    try {
      // Sheet için yaklaşık konum yeterli — check-in sayfası zaten yüksek
      // doğrulukla yeniden ölçüp backend guard'ını uyguluyor. Son bilinen konumu
      // hemen kullan; yoksa orta doğrulukla ve 6 sn timeout ile al.
      Position? position = await Geolocator.getLastKnownPosition();
      if (position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 6),
          );
        } catch (_) {
          position = await Geolocator.getLastKnownPosition();
        }
      }
      if (!context.mounted) return;
      if (position == null) {
        closeLoading();
        if (context.mounted) {
          _showSnack(context, 'Could not get your location. Try again.');
        }
        return;
      }

      // Yakın mekanlar + aktif check-in'i PARALEL çek (aktif check-in yalnızca
      // sheet'teki rozet için; markers ile örtüşsün diye ayrı beklenmez).
      final markersFuture = _venues.getMapMarkers(
        latitude: position.latitude,
        longitude: position.longitude,
        radiusMeters: _searchRadiusMeters,
        limit: 60,
      );
      final activeFuture = _checkinRepo
          .getActiveCheckin()
          .then<String?>((a) => a?.venueId)
          .catchError((_) => null);

      List<Venue> markers;
      try {
        markers = await markersFuture;
      } catch (error) {
        closeLoading();
        if (context.mounted) {
          if (isOfflineError(error)) {
            showBrandedNotice(
              context,
              title: 'You\'re offline',
              message:
                  'Reconnect, then tap quick check-in again to find nearby venues.',
              tone: BrandedNoticeTone.warning,
              icon: Icons.wifi_off_rounded,
            );
          } else {
            showBrandedNotice(
              context,
              title: 'Nearby venues unavailable',
              message:
                  'We couldn\'t load places around you. Please try again in a moment.',
              tone: BrandedNoticeTone.error,
              icon: Icons.location_searching_rounded,
            );
          }
        }
        return;
      }
      final activeCheckinVenueId = await activeFuture;
      if (!context.mounted) return;

      // Keep only venues with a known distance, sorted closest-first.
      final candidates = markers.where((v) => v.distanceMeters != null).toList()
        ..sort((a, b) => a.distanceMeters!.compareTo(b.distanceMeters!));

      final eligible = candidates
          .where((v) => v.distanceMeters! <= _checkinMaxDistanceMeters)
          .toList();

      if (eligible.isEmpty) {
        closeLoading();
        if (context.mounted) {
          _showSnack(
            context,
            "No venue found within range. Move closer and try again.",
          );
        }
        return;
      }

      // Veri hazır → loading sheet'i kapat, sonra karar ver.
      closeLoading();
      if (!context.mounted) return;

      if (_shouldAutoSelect(eligible, position.accuracy)) {
        await _proceed(context, eligible.first, activeCheckinVenueId);
        return;
      }

      final chosen = await showNearbyVenueSheet(
        context,
        venues: eligible,
        checkinMaxDistanceMeters: _checkinMaxDistanceMeters.toInt(),
        activeCheckinVenueId: activeCheckinVenueId,
      );
      if (chosen == null || !context.mounted) return;
      await _proceed(context, chosen, activeCheckinVenueId);
    } finally {
      // Herhangi bir erken çıkışta loading sheet açık kalmasın.
      closeLoading();
    }
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

  /// Seçilen venue'da kullanıcı ZATEN check-in'liyse ("You're here") tekrar
  /// check-in akışı açmak yerine venue detay sayfasını açar; değilse normal
  /// check-in akışına girer.
  Future<void> _proceed(
    BuildContext context,
    Venue venue,
    String? activeCheckinVenueId,
  ) async {
    if (activeCheckinVenueId != null && venue.id == activeCheckinVenueId) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
      );
      return;
    }
    await _openCheckin(context, venue);
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

    // Check-in tamamlandıysa → venue detail'deki gibi doğrudan "Who's here?"e geç.
    if (!context.mounted) return;
    if (ActiveCheckinService().isCheckedInAt(venueId)) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VenuePeoplePage(venue: venue, listVenueId: venueId),
        ),
      );
    }
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
    showBrandedNotice(
      context,
      title: 'Quick check-in',
      message: message,
      tone: BrandedNoticeTone.warning,
      icon: Icons.location_on_outlined,
    );
  }
}
