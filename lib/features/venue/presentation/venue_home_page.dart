import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
      if (t.isSameVenueAs(p)) {
        merged = merged.mergeCheckinFieldsFrom(p);
      }
    }
    return merged;
  }).toList();
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
  List<Venue> _mapVenues = const [];
  List<Venue> _listVenues = const [];
  String? _selectedVenueId;
  final VenueRepository _venueRepository = VenueRepository();

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

  void _openVenue(Venue venue) {
    _selectVenue(venue);
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
    );
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
            onLocationResolved: _loadNearbyVenues,
            onSearchActivityChanged: (active) {
              if (!mounted) return;
              setState(() => _isMapSearchActive = active);
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
