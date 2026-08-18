import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'venue_map_view.dart';

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

  bool _loadingVenues = false;
  bool _loadingMoreVenues = false;
  bool _hasMoreVenues = false;
  LatLng? _lastResolvedCenter;
  LatLng? _lastLoadedCenter;
  String? _browseKeyword;
  String? _lastLoadedKeyword;
  int _venueLoadToken = 0;
  int _nearbyPage = 1;
  static const int _nearbyPageSize = 50;
  List<Venue> _mapVenues = const [];
  List<Venue> _listVenues = const [];
  String? _selectedVenueId;
  final VenueRepository _venueRepository = VenueRepository();
  final VenueContextRepository _venueContextRepository =
      VenueContextRepository();

  Future<void> _loadNearbyVenues(LatLng center, {int attempt = 1}) async {
    final keyword = _browseKeyword;
    final last = _lastLoadedCenter;
    if (last != null &&
        _listVenues.isNotEmpty &&
        _normalizedKeyword(_lastLoadedKeyword) == _normalizedKeyword(keyword) &&
        _distanceMetersBetween(last, center) < 140) {
      return;
    }

    final token = ++_venueLoadToken;
    setState(() => _loadingVenues = _listVenues.isEmpty);
    try {
      final response = await _venueRepository.getNearbyVenues(
        latitude: center.latitude,
        longitude: center.longitude,
        page: 1,
        pageSize: _nearbyPageSize,
        keyword: keyword,
      );
      if (!mounted || token != _venueLoadToken) return;

      final initialPool = [...response.mapItems, ...response.items];
      setState(() {
        _lastLoadedCenter = center;
        _lastLoadedKeyword = keyword;
        _mapVenues = _enrichVenuesWithPoolCheckins(
          response.mapItems,
          initialPool,
        );
        _listVenues = _enrichVenuesWithPoolCheckins(
          response.items,
          initialPool,
        );
        _nearbyPage = response.page;
        _hasMoreVenues = response.hasMore;
        _loadingMoreVenues = false;
        _loadingVenues = false;
      });

      try {
        final mapVenues = await _venueRepository.getMapMarkers(
          latitude: center.latitude,
          longitude: center.longitude,
          keyword: keyword,
        );
        if (!mounted || token != _venueLoadToken) return;
        setState(() {
          final pool = [...mapVenues, ...response.mapItems, ...response.items];
          _mapVenues = _enrichVenuesWithPoolCheckins(mapVenues, pool);
          _listVenues = _dedupeVenues(
            _enrichVenuesWithPoolCheckins(_listVenues, pool),
          );
        });
      } catch (_) {
        // Keep discover mapItems as fallback if map-markers is unavailable.
      }
    } catch (e) {
      debugPrint('[VenueHome] _loadNearbyVenues failed (attempt $attempt): $e');
      if (!mounted || token != _venueLoadToken) return;
      if (attempt < 3) {
        await Future.delayed(Duration(seconds: attempt * 2));
        if (!mounted || token != _venueLoadToken) return;
        await _loadNearbyVenues(center, attempt: attempt + 1);
        return;
      }
      setState(() {
        _mapVenues = const [];
        _listVenues = const [];
        _nearbyPage = 1;
        _hasMoreVenues = false;
        _loadingMoreVenues = false;
        _loadingVenues = false;
      });
    }
  }

  Future<void> _loadMoreNearbyVenues() async {
    final center = _lastLoadedCenter ?? _lastResolvedCenter;
    final keyword = _browseKeyword;
    if (center == null ||
        _loadingVenues ||
        _loadingMoreVenues ||
        !_hasMoreVenues) {
      return;
    }

    final token = _venueLoadToken;
    final nextPage = _nearbyPage + 1;
    setState(() => _loadingMoreVenues = true);

    try {
      final response = await _venueRepository.getNearbyVenues(
        latitude: center.latitude,
        longitude: center.longitude,
        page: nextPage,
        pageSize: _nearbyPageSize,
        keyword: keyword,
      );
      if (!mounted || token != _venueLoadToken) return;

      setState(() {
        final pool = [
          ..._mapVenues,
          ..._listVenues,
          ...response.mapItems,
          ...response.items,
        ];
        _mapVenues = _dedupeVenues(
          _enrichVenuesWithPoolCheckins([
            ..._mapVenues,
            ...response.mapItems,
          ], pool),
        );
        _listVenues = _dedupeVenues(
          _enrichVenuesWithPoolCheckins([
            ..._listVenues,
            ...response.items,
          ], pool),
        );
        _nearbyPage = response.page > _nearbyPage ? response.page : nextPage;
        _hasMoreVenues = response.hasMore && response.items.isNotEmpty;
        _loadingMoreVenues = false;
      });
    } catch (e) {
      debugPrint('[VenueHome] _loadMoreNearbyVenues failed: $e');
      if (!mounted || token != _venueLoadToken) return;
      setState(() => _loadingMoreVenues = false);
    }
  }

  String _normalizedKeyword(String? keyword) =>
      keyword?.trim().toLowerCase() ?? '';

  void _handleBrowseKeywordChanged(String? keyword) {
    final normalized = _normalizedKeyword(keyword);
    if (_normalizedKeyword(_browseKeyword) == normalized) return;
    _browseKeyword = normalized.isEmpty ? null : keyword!.trim();
    _lastLoadedCenter = null;
    final center = _lastResolvedCenter;
    if (center != null) {
      _loadNearbyVenues(center);
    }
  }

  List<Venue> _dedupeVenues(List<Venue> venues) {
    final seen = <String>{};
    final result = <Venue>[];
    for (final venue in venues) {
      final key = _selectionKeyForVenue(venue).isNotEmpty
          ? _selectionKeyForVenue(venue)
          : '${venue.name.toLowerCase().trim()}|${venue.latitude.toStringAsFixed(5)}|${venue.longitude.toStringAsFixed(5)}';
      if (seen.add(key)) result.add(venue);
    }
    return result;
  }

  double _distanceMetersBetween(LatLng a, LatLng b) {
    const earthRadius = 6371000.0;
    final dLat = (b.latitude - a.latitude) * 0.017453292519943295;
    final dLng = (b.longitude - a.longitude) * 0.017453292519943295;
    final lat1 = a.latitude * 0.017453292519943295;
    final lat2 = b.latitude * 0.017453292519943295;
    final h =
        (math.sin(dLat / 2) * math.sin(dLat / 2)) +
        math.cos(lat1) *
            math.cos(lat2) *
            (math.sin(dLng / 2) * math.sin(dLng / 2));
    return 2 * earthRadius * math.asin(math.sqrt(h));
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
    final direct =
        response['venueId'] ?? response['venue_id'] ?? response['id'];
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
      final resolved = await _venueContextRepository.resolveVenueFromPlace(
        placeId,
      );
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
      ratingCount: v.ratingCount,
      types: v.types,
      description: v.description,
      photos: v.photos,
      openingHours: v.openingHours,
      upcomingEvents: v.upcomingEvents,
      partnershipPlatforms: v.partnershipPlatforms,
    );
  }

  bool _isSamePhysicalVenue(
    Venue candidate,
    Venue target,
    String? resolvedVenueId,
  ) {
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
      final stats = await _venueContextRepository.getVenueCheckinStats(
        resolvedVenueId,
      );
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
            onLocationAccessChanged: (granted) {
              if (!mounted) return;
              if (!granted) {
                setState(() {
                  _mapVenues = const [];
                  _listVenues = const [];
                  _selectedVenueId = null;
                });
              }
            },
            onLocationResolved: (center) {
              _lastResolvedCenter = center;
              _loadNearbyVenues(center);
              // Fire-and-forget: konumu backend'e ping'le (2km notify için)
              _venueContextRepository
                  .pingLocation(center.latitude, center.longitude)
                  .ignore();
            },
            onSearchActivityChanged: (_) {
              // Parent no longer hides a separate list sheet during search.
            },
            onVenueDetailClosed: (venue) {
              _handleVenueDetailClosed(venue);
            },
            venues: _mapVenues,
            listVenues: _listVenues,
            loadingVenues: _loadingVenues,
            loadingMoreVenues: _loadingMoreVenues,
            hasMoreVenues: _hasMoreVenues,
            onLoadMoreVenues: _loadMoreNearbyVenues,
            onBrowseKeywordChanged: _handleBrowseKeywordChanged,
            selectedVenueId: _selectedVenueId,
            onVenueTap: _selectVenue,
          ),
        ],
      ),
    );
  }
}
