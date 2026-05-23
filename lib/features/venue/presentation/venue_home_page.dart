import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'venue_map_view.dart';
import 'venue_bottom_sheet.dart';
import 'venue_detail_page.dart';

class VenueHomePage extends StatefulWidget {
  const VenueHomePage({super.key});

  @override
  State<VenueHomePage> createState() => _VenueHomePageState();
}

/// Discover may split the same place across [mapItems] vs [items] with different ids, or
/// attach check-ins on only one row. Merge every target against the full pool (both lists)
/// so list cards and map pins get the same stats when any duplicate carries them.
List<Venue> _enrichVenuesWithPoolCheckins(
  List<Venue> targets,
  List<Venue> pool,
) {
  if (pool.isEmpty) return targets;
  return targets.map((t) {
    var merged = t;
    for (final p in pool) {
      if (_isStrictVenueMatch(t, p)) {
        merged = merged.mergeCheckinFieldsFrom(p);
      }
    }
    return merged;
  }).toList();
}

bool _isStrictVenueMatch(Venue a, Venue b) {
  if (a.id.isNotEmpty && b.id.isNotEmpty && a.id == b.id) return true;
  final ap = a.placeId;
  final bp = b.placeId;
  if (ap != null && ap.isNotEmpty && bp != null && bp.isNotEmpty && ap == bp) {
    return true;
  }
  // Some rows can carry place id in `id`.
  if (ap != null && ap.isNotEmpty && b.id == ap) return true;
  if (bp != null && bp.isNotEmpty && a.id == bp) return true;
  return false;
}

class _VenueHomePageState extends State<VenueHomePage> {
  String _selectionKeyForVenue(Venue venue) {
    if (venue.id.isNotEmpty) return venue.id;
    final placeId = venue.placeId;
    if (placeId != null && placeId.isNotEmpty) return placeId;
    return '';
  }

  bool isSheetExpanded = false;
  bool _isMapSearchActive = false;
  bool _locationAvailable = false;
  bool _loadingVenues = false;
  LatLng? _lastResolvedCenter;
  List<Venue> _mapVenues = const [];
  List<Venue> _listVenues = const [];
  String? _selectedVenueId;
  final VenueRepository _venueRepository = VenueRepository();
  final VenueContextRepository _venueContextRepository = VenueContextRepository();

  Future<void> _loadNearbyVenues(LatLng center) async {
    setState(() => _loadingVenues = true);
    try {
      final response = await _venueRepository.getNearbyVenues(
        latitude: center.latitude,
        longitude: center.longitude,
      );
      List<Venue> mapVenues = response.mapItems;
      try {
        mapVenues = await _venueRepository.getMapMarkers(
          latitude: center.latitude,
          longitude: center.longitude,
        );
      } catch (_) {
        // Keep discover mapItems as fallback if map-markers is unavailable.
      }

      if (!mounted) return;

      setState(() {
        final pool = [...mapVenues, ...response.mapItems, ...response.items];
        _mapVenues = _enrichVenuesWithPoolCheckins(mapVenues, pool);
        _listVenues = _enrichVenuesWithPoolCheckins(response.items, pool);
        _loadingVenues = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _mapVenues = const [];
        _listVenues = const [];
        _loadingVenues = false;
      });
    }
  }

  void _selectVenue(Venue venue) {
    setState(() => _selectedVenueId = _selectionKeyForVenue(venue));
  }

  Future<void> _refreshNearbyAfterDetail() async {
    final center = _lastResolvedCenter;
    if (center == null || _loadingVenues) return;
    await _loadNearbyVenues(center);
  }

  String? _extractVenueIdFromResolve(Map<String, dynamic> response) {
    final direct = response['venueId'] ?? response['venue_id'] ?? response['id'];
    if (direct is String && direct.isNotEmpty) return direct;
    final venue = response['venue'];
    if (venue is Map) {
      final nested = venue['id'] ?? venue['venueId'] ?? venue['venue_id'];
      if (nested is String && nested.isNotEmpty) return nested;
    }
    return null;
  }

  Future<String?> _resolveVenueIdForStats(Venue venue) async {
    if (venue.id.isNotEmpty && venue.canCheckin) return venue.id;
    final placeId = venue.placeId;
    if (placeId == null || placeId.isEmpty) return null;
    try {
      final resolved = await _venueContextRepository.resolveVenueFromPlace(placeId);
      return _extractVenueIdFromResolve(resolved);
    } catch (_) {
      return null;
    }
  }

  Venue _withUpdatedStats(Venue v, VenueCheckinStats stats) {
    return Venue(
      id: v.id,
      placeId: v.placeId,
      name: v.name,
      type: v.type,
      status: v.status,
      address: v.address,
      city: v.city,
      photoUrl: v.photoUrl,
      latitude: v.latitude,
      longitude: v.longitude,
      tag: v.tag,
      source: v.source,
      isInDb: v.isInDb,
      canCheckin: v.canCheckin,
      checkinCountActive: stats.checkinCountActive,
      checkinCountMale: stats.male,
      checkinCountFemale: stats.female,
      eventSummary: v.eventSummary,
      verificationLevel: v.verificationLevel,
      distanceMeters: v.distanceMeters,
      openNow: v.openNow,
      rating: v.rating,
      types: v.types,
    );
  }

  bool _isSamePhysicalVenue(Venue candidate, Venue target, String? resolvedVenueId) {
    if (resolvedVenueId != null && resolvedVenueId.isNotEmpty) {
      if (candidate.id == resolvedVenueId) return true;
    }
    final tp = target.placeId;
    if (tp != null && tp.isNotEmpty) {
      if (candidate.placeId == tp) return true;
      if (candidate.id == tp) return true;
    }
    return false;
  }

  Future<void> _refreshVenueStatsForSurface(Venue venue) async {
    final resolvedVenueId = await _resolveVenueIdForStats(venue);
    if (resolvedVenueId == null || resolvedVenueId.isEmpty) return;
    try {
      final stats = await _venueContextRepository.getVenueCheckinStats(resolvedVenueId);
      if (!mounted) return;
      setState(() {
        _mapVenues = _mapVenues
            .map(
              (v) => _isSamePhysicalVenue(v, venue, resolvedVenueId)
                  ? _withUpdatedStats(v, stats)
                  : v,
            )
            .toList();
        _listVenues = _listVenues
            .map(
              (v) => _isSamePhysicalVenue(v, venue, resolvedVenueId)
                  ? _withUpdatedStats(v, stats)
                  : v,
            )
            .toList();
      });
    } catch (_) {
      // Keep current values if stats endpoint fails.
    }
  }

  Future<void> _handleVenueDetailClosed(Venue venue) async {
    await _refreshNearbyAfterDetail();
    await _refreshVenueStatsForSurface(venue);
  }

  Future<void> _openVenue(Venue venue) async {
    _selectVenue(venue);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
    );
    if (!mounted) return;
    await _handleVenueDetailClosed(venue);
  }

  @override
  void initState() {
    super.initState();
    // Trigger "test venue nearby" push once per hour (backend rate-limits).
    // Fire-and-forget — never blocks the UI.
    _venueRepository.triggerTestVenueNotification();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          VenueMapView(
            hideSearch: isSheetExpanded,
            onLocationAccessChanged: (granted) {
              if (!mounted) return;
              setState(() {
                _locationAvailable = granted;
                if (!granted) {
                  _mapVenues = const [];
                  _listVenues = const [];
                  _selectedVenueId = null;
                }
              });
            },
            onLocationResolved: (center) {
              _lastResolvedCenter = center;
              _loadNearbyVenues(center);
              // Fire-and-forget: konumu backend'e ping'le (2km notify için)
              _venueContextRepository
                  .pingLocation(center.latitude, center.longitude)
                  .ignore();
            },
            onSearchActivityChanged: (active) {
              if (!mounted) return;
              setState(() => _isMapSearchActive = active);
            },
            onVenueDetailClosed: (venue) {
              _handleVenueDetailClosed(venue);
            },
            venues: _mapVenues,
            selectedVenueId: _selectedVenueId,
            onVenueTap: _selectVenue,
          ),
          if (_locationAvailable && !_isMapSearchActive)
            VenueBottomSheet(
              onExpandChanged: (expanded) {
                setState(() => isSheetExpanded = expanded);
              },
              venues: _listVenues,
              loading: _loadingVenues,
              selectedVenueId: _selectedVenueId,
              onVenueTap: _openVenue,
            ),
        ],
      ),
    );
  }
}
