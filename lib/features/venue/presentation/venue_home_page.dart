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

class _VenueHomePageState extends State<VenueHomePage> {
  bool isSheetExpanded = false;
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

      if (!mounted) return;

      setState(() {
        _mapVenues = response.mapItems;
        _listVenues = response.items;
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
    setState(() => _selectedVenueId = venue.id);
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
            venues: _mapVenues,
            selectedVenueId: _selectedVenueId,
            onVenueTap: _selectVenue,
          ),
          if (_locationAvailable)
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
