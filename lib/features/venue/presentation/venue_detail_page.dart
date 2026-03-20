import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';

class VenueDetailPage extends StatefulWidget {
  final Venue venue;

  const VenueDetailPage({super.key, required this.venue});

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  final _repo = VenueCheckinRepository();
  final _venueContextRepo = VenueContextRepository();
  String? _activeCheckinVenueId;
  String? _activeCheckinVenuePlaceId;
  String? _resolvedVenueIdForCurrentDetail;
  bool _loadingActiveCheckin = true;
  bool _resolvingVenueForCheckin = false;

  @override
  void initState() {
    super.initState();
    _loadActiveCheckin();
  }

  /// For Google-backed detail, [Venue.id] may be a Places id while active check-in uses DB UUID.
  /// We need a stable key to resolve/compare without flashing the wrong CTA.
  String? _effectivePlaceKeyForActiveCheckinCorrelation() {
    final p = widget.venue.placeId;
    if (p != null && p.isNotEmpty) return p;
    if (widget.venue.source != 'google') return null;
    if (widget.venue.id.isEmpty) return null;
    // Real DB uuid as id — matching is done via id == activeVenueId.
    if (widget.venue.isInDb && widget.venue.canCheckin) return null;
    return widget.venue.id;
  }

  Future<void> _loadActiveCheckin() async {
    try {
      final activeCheckin = await _repo.getActiveCheckin();
      final activeVenueId = activeCheckin?.venueId;

      if (!mounted) return;

      if (activeVenueId == null || activeVenueId.isEmpty) {
        setState(() {
          _activeCheckinVenueId = null;
          _activeCheckinVenuePlaceId = null;
          _loadingActiveCheckin = false;
        });
        return;
      }

      setState(() {
        _activeCheckinVenueId = activeVenueId;
        _activeCheckinVenuePlaceId = null;
        // Stay loading until we can decide "here" vs elsewhere (avoid wrong "Check in first").
      });

      final matchedById =
          widget.venue.id.isNotEmpty && widget.venue.id == activeVenueId;
      if (matchedById) {
        if (mounted) {
          setState(() => _loadingActiveCheckin = false);
        }
        return;
      }

      final placeKey = _effectivePlaceKeyForActiveCheckinCorrelation();
      if (placeKey != null && placeKey.isNotEmpty) {
        try {
          final resolvedResponse =
              await _venueContextRepo.resolveVenueFromPlace(placeKey);
          final resolved = _extractVenueIdFromResponse(resolvedResponse);
          if (!mounted) return;
          if (resolved != null &&
              resolved.isNotEmpty &&
              resolved == activeVenueId) {
            setState(() {
              _resolvedVenueIdForCurrentDetail = resolved;
              _loadingActiveCheckin = false;
            });
            return;
          }
        } catch (e) {
          debugPrint('⚠️ resolve for active check-in correlation: $e');
        }
      }

      try {
        final venueData = await _venueContextRepo.getVenueById(activeVenueId);
        final placeId = (venueData['placeId'] ??
                venueData['place_id'] ??
                venueData['googlePlaceId'] ??
                venueData['google_place_id'])
            ?.toString();
        if (!mounted) return;
        setState(() {
          if (placeId != null && placeId.isNotEmpty) {
            _activeCheckinVenuePlaceId = placeId;
          }
          _loadingActiveCheckin = false;
        });
      } catch (e) {
        debugPrint('⚠️ Could not load active check-in venue details: $e');
        if (!mounted) return;
        setState(() => _loadingActiveCheckin = false);
      }
    } catch (e) {
      debugPrint('⚠️ Error loading active check-in: $e');
      if (!mounted) return;
      setState(() {
        _activeCheckinVenueId = null;
        _loadingActiveCheckin = false;
      });
    }
  }

  String? _extractVenueIdFromResponse(Map<String, dynamic> response) {
    final direct = response['venueId'] ?? response['venue_id'] ?? response['id'];
    if (direct is String && direct.isNotEmpty) return direct;

    final venue = response['venue'];
    if (venue is Map) {
      final nestedId = venue['id'] ?? venue['venueId'] ?? venue['venue_id'];
      if (nestedId is String && nestedId.isNotEmpty) return nestedId;
    }
    return null;
  }

  Future<String> _resolveVenueIdForCheckin() async {
    if (widget.venue.id.isNotEmpty && widget.venue.canCheckin) {
      return widget.venue.id;
    }

    final placeId = widget.venue.placeId;
    if (placeId == null || placeId.isEmpty) {
      if (widget.venue.id.isNotEmpty) return widget.venue.id;
      throw Exception('Venue reference is missing');
    }

    // Check-in flow must resolve a usable venue id without claim/account side effects.
    final resolvedResponse = await _venueContextRepo.resolveVenueFromPlace(placeId);
    final resolved = _extractVenueIdFromResponse(resolvedResponse);
    if (resolved == null || resolved.isEmpty) {
      throw Exception('Could not resolve venue id from place');
    }
    return resolved;
  }

  Future<void> _openCheckinFlow() async {
    setState(() => _resolvingVenueForCheckin = true);
    try {
      final resolvedVenueId = await _resolveVenueIdForCheckin();
      if (!mounted) return;
      setState(() {
        _resolvedVenueIdForCurrentDetail = resolvedVenueId;
      });
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => CheckInPage(venueId: resolvedVenueId),
        ),
      );
      _loadActiveCheckin();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare venue for check-in')),
      );
      debugPrint('❌ Check-in venue resolve error: $e');
    } finally {
      if (mounted) {
        setState(() => _resolvingVenueForCheckin = false);
      }
    }
  }

  bool _isActiveCheckinAtCurrentVenue() {
    final activeVenueId = _activeCheckinVenueId;
    if (activeVenueId == null || activeVenueId.isEmpty) return false;

    final resolvedCurrentVenueId = _resolvedVenueIdForCurrentDetail;
    if (resolvedCurrentVenueId != null &&
        resolvedCurrentVenueId.isNotEmpty &&
        activeVenueId == resolvedCurrentVenueId) {
      return true;
    }

    final currentVenueId = widget.venue.id;
    if (currentVenueId.isNotEmpty && activeVenueId == currentVenueId) {
      return true;
    }

    final currentPlaceId = widget.venue.placeId;
    final activePlaceId = _activeCheckinVenuePlaceId;
    if (currentPlaceId != null &&
        currentPlaceId.isNotEmpty &&
        activePlaceId != null &&
        activePlaceId.isNotEmpty &&
        currentPlaceId == activePlaceId) {
      return true;
    }

    // Some google-only cards use placeId as id.
    if (activePlaceId != null &&
        activePlaceId.isNotEmpty &&
        currentVenueId == activePlaceId) {
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCheckinHere = _isActiveCheckinAtCurrentVenue();

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// BACK
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),

              const SizedBox(height: 8),

              /// HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.venue.photoUrl.isNotEmpty
                          ? widget.venue.photoUrl
                          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.venue.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.venue.status,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              /// COVER IMAGE
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: NetworkImage(
                      widget.venue.photoUrl.isNotEmpty
                          ? widget.venue.photoUrl
                          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              /// TAG
              Text(
                '#${widget.venue.tag}',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              /// ADDRESS
              Text(
                widget.venue.address,
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.map),
                label: const Text('Get Directions'),
              ),

              const SizedBox(height: 24),

              /// WHO'S HERE
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loadingActiveCheckin || _resolvingVenueForCheckin
                      ? null
                      : () async {
                          if (hasActiveCheckinHere) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VenuePeoplePage(
                                  venue: widget.venue,
                                  listVenueId: _activeCheckinVenueId ??
                                      _resolvedVenueIdForCurrentDetail,
                                ),
                              ),
                            );
                            return;
                          }
                          await _openCheckinFlow();
                        },
                  child: Text(
                    _resolvingVenueForCheckin
                        ? 'Preparing venue...'
                        : _loadingActiveCheckin
                        ? "Loading..."
                        : hasActiveCheckinHere
                            ? "Who's here?"
                            : "Check in first",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
