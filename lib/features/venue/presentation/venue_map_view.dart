import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'cluster_service.dart';
import 'dart:math' as math;

class VenueMapView extends StatefulWidget {
  final bool hideSearch;
  final ValueChanged<bool>? onLocationAccessChanged;
  final ValueChanged<LatLng>? onLocationResolved;
  final List<Venue> venues;
  final String? selectedVenueId;
  final ValueChanged<Venue>? onVenueTap;

  const VenueMapView({
    super.key,
    this.hideSearch = false,
    this.onLocationAccessChanged,
    this.onLocationResolved,
    this.venues = const [],
    this.selectedVenueId,
    this.onVenueTap,
  });

  @override
  State<VenueMapView> createState() => _VenueMapViewState();
}

class _VenueMapViewState extends State<VenueMapView> {
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();
  final VenueClusterService _clusterService = const VenueClusterService();
  final VenueRepository _venueRepository = VenueRepository();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  LatLng? _currentLocation;
  GoogleMapController? _mapController;
  CameraPosition? _latestCameraPosition;
  bool _loading = true;
  bool _locationPermissionDenied = false;
  Set<Marker> _markers = const {};
  int _clusterJobToken = 0;
  String _lastViewportKey = '';
  String _lastVenueKey = '';
  String _lastMarkerKey = '';
  String _lastSelectedKey = '';

  final Map<String, BitmapDescriptor> _clusterIconCache = {};
  BitmapDescriptor? _singleDefaultIcon;
  BitmapDescriptor? _singleSelectedIcon;
  BitmapDescriptor? _searchResultIcon;
  Timer? _searchDebounce;
  bool _searchLoading = false;
  String? _searchError;
  List<Venue> _searchResults = const [];
  Venue? _selectedSearchVenue;
  int _searchRequestToken = 0;
  bool _showSearchResults = false;
  final List<bool Function(Venue)> _clusterInputFilters = [
    _isRelevantSocialVenue,
  ];

  static const Set<String> _includedVenueTypes = {
    'restaurant',
    'cafe',
    'bar',
    'nightclub',
    'lounge',
  };

  static const Set<String> _excludedVenueTypes = {
    'lodging',
    'hotel',
    'gas_station',
    'pharmacy',
    'school',
    'hospital',
    'residential',
    'apartment',
    'residential_apartment',
  };

  @override
  void initState() {
    super.initState();
    _searchFocusNode.addListener(() {
      if (!mounted) return;
      if (_searchFocusNode.hasFocus) {
        setState(() => _showSearchResults = true);
      }
    });
    _loadLocation();
  }

  @override
  void didUpdateWidget(covariant VenueMapView oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.selectedVenueId != oldWidget.selectedVenueId &&
        widget.selectedVenueId != null) {
      Venue? selected;
      for (final venue in widget.venues) {
        if (venue.id == widget.selectedVenueId) {
          selected = venue;
          break;
        }
      }
      if (selected != null && _mapController != null) {
        _mapController!.animateCamera(
          CameraUpdate.newLatLng(LatLng(selected.latitude, selected.longitude)),
        );
      }
    }

    final venuesChanged = oldWidget.venues != widget.venues;
    final selectionChanged =
        oldWidget.selectedVenueId != widget.selectedVenueId;
    if (venuesChanged || selectionChanged) {
      _recomputeClusters(force: true);
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _loadLocation() async {
    setState(() {
      _loading = true;
      _locationPermissionDenied = false;
    });

    final permission = await _locationPermissionService.status();

    if (!permission.isGranted) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _locationPermissionDenied = true;
      });
      widget.onLocationAccessChanged?.call(false);
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return;
      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
        _loading = false;
      });
      widget.onLocationAccessChanged?.call(true);
      widget.onLocationResolved?.call(_currentLocation!);
      _recomputeClusters(force: true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _locationPermissionDenied = true;
      });
      widget.onLocationAccessChanged?.call(false);
    }
  }

  Future<void> _recomputeClusters({bool force = false}) async {
    final map = _mapController;
    final camera = _latestCameraPosition;
    if (map == null || camera == null || _locationPermissionDenied) return;

    final clusteredInputVenues = _filterClusterInputVenues(widget.venues);
    final venuesKey = _venueFingerprint(clusteredInputVenues);
    if (!force && venuesKey == _lastVenueKey && widget.venues.isEmpty) return;

    final token = ++_clusterJobToken;
    LatLngBounds bounds;
    try {
      bounds = await map.getVisibleRegion();
    } catch (_) {
      return;
    }
    if (!mounted || token != _clusterJobToken) return;

    final viewportKey = _viewportKey(bounds, camera.zoom);
    final selectedKey =
        '${widget.selectedVenueId ?? ''}|${_selectedSearchVenue != null ? _venueIdentity(_selectedSearchVenue!) : ''}';
    if (!force &&
        viewportKey == _lastViewportKey &&
        venuesKey == _lastVenueKey &&
        selectedKey == _lastSelectedKey) {
      return;
    }

    _lastViewportKey = viewportKey;
    _lastVenueKey = venuesKey;
    _lastSelectedKey = selectedKey;

    if (clusteredInputVenues.isEmpty) {
      if (_markers.isNotEmpty) {
        setState(() => _markers = const {});
      }
      _lastMarkerKey = '';
      return;
    }

    final nodes = _clusterService.buildClusters(
      venues: clusteredInputVenues,
      visibleBounds: bounds,
      zoom: camera.zoom,
      selectedVenueId: widget.selectedVenueId,
    );
    var limitedNodes = nodes;

    if (nodes.length > 80) {
      limitedNodes = List.from(nodes)
        ..sort((a, b) => b.count.compareTo(a.count));
      limitedNodes = limitedNodes.take(80).toList();
    }
    if (!mounted || token != _clusterJobToken) return;

    final builtMarkers = <Marker>{};
    for (final node in limitedNodes) {
      if (node.isCluster) {
        final icon = await _clusterIcon(
          count: node.count,
          highlighted: node.containsSelected,
        );
        if (!mounted || token != _clusterJobToken) return;
        builtMarkers.add(
          Marker(
            markerId: MarkerId('cluster:${node.id}'),
            position: node.position,
            icon: icon,
            zIndexInt: node.containsSelected ? 3 : 2,
            onTap: () {
              final nextZoom = node.count > 20
                  ? (camera.zoom + 3.0)
                  : (camera.zoom + 2.0);

              _mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(
                    target: node.position,
                    zoom: nextZoom.clamp(3.0, 21.0),
                  ),
                ),
              );
              _mapController?.animateCamera(
                CameraUpdate.newCameraPosition(
                  CameraPosition(target: node.position, zoom: nextZoom),
                ),
              );
            },
          ),
        );
      } else {
        final venue = node.primaryVenue;
        final isSelected =
            widget.selectedVenueId != null &&
            widget.selectedVenueId == venue.id;
        builtMarkers.add(
          Marker(
            markerId: MarkerId('venue:${_venueIdentity(venue)}'),
            position: LatLng(venue.latitude, venue.longitude),
            infoWindow: InfoWindow(
              title: venue.name,
              snippet: venue.source == 'db'
                  ? 'DB venue'
                  : 'Google venue (community pending)',
            ),
            icon: isSelected ? _selectedSingleIcon() : _defaultSingleIcon(),
            zIndexInt: isSelected ? 4 : 1,
            onTap: () => widget.onVenueTap?.call(venue),
          ),
        );
      }
    }

    if (_selectedSearchVenue != null &&
        _selectedSearchVenue!.latitude != 0 &&
        _selectedSearchVenue!.longitude != 0) {
      builtMarkers.add(
        Marker(
          markerId: const MarkerId('search:selected'),
          position: LatLng(
            _selectedSearchVenue!.latitude,
            _selectedSearchVenue!.longitude,
          ),
          icon: await _searchSelectionIcon(),
          zIndexInt: 6,
          infoWindow: InfoWindow(
            title: _selectedSearchVenue!.name,
            snippet: _selectedSearchVenue!.address,
          ),
        ),
      );
    }

    final markerKey = _markerFingerprint(builtMarkers);
    if (markerKey == _lastMarkerKey) return;
    _lastMarkerKey = markerKey;
    if (mounted) {
      setState(() => _markers = builtMarkers);
    }
  }

  BitmapDescriptor _defaultSingleIcon() {
    return _singleDefaultIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueRed,
    );
  }

  BitmapDescriptor _selectedSingleIcon() {
    return _singleSelectedIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueAzure,
    );
  }

  Future<BitmapDescriptor> _searchSelectionIcon() async {
    if (_searchResultIcon != null) return _searchResultIcon!;
    _searchResultIcon = await _drawClusterBitmap(
      size: 56,
      text: 'S',
      fill: const Color(0xFF0EA5E9),
      stroke: const Color(0xFFBAE6FD),
    );
    return _searchResultIcon!;
  }

  Future<BitmapDescriptor> _clusterIcon({
    required int count,
    required bool highlighted,
  }) async {
    final text = count > 999 ? '999+' : '$count';
    final bucket = count >= 100 ? '100+' : (count >= 20 ? '20+' : '2+');
    final cacheKey = '$bucket:$text:$highlighted';

    final cached = _clusterIconCache[cacheKey];
    if (cached != null) return cached;

    final size = (42 + (math.log(count + 1) * 8)).clamp(42, 70).toInt();
    Color fill;

    if (highlighted) {
      fill = const Color(0xFFEA580C); // strong orange
    } else if (count > 50) {
      fill = const Color(0xFF9A3412); // dark burnt orange
    } else if (count > 20) {
      fill = const Color(0xFFC2410C); // mid orange
    } else {
      fill = const Color(0xFFFB923C); // soft orange
    }

    final stroke = highlighted
        ? const Color(0xFF90CDF4)
        : const Color(0xFFD6BCFA);

    final icon = await _drawClusterBitmap(
      size: size,
      text: text,
      fill: fill,
      stroke: stroke,
    );

    _clusterIconCache[cacheKey] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _drawClusterBitmap({
    required int size,
    required String text,
    required Color fill,
    required Color stroke,
  }) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(size / 2, size / 2);
    final radius = size / 2.0;

    final fillPaint = Paint()..color = fill;
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;

    canvas.drawCircle(center, radius - 2, fillPaint);
    canvas.drawCircle(center, radius - 3, strokePaint);

    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.30,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset((size - tp.width) / 2, (size - tp.height) / 2));

    final image = await recorder.endRecording().toImage(size, size);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null || bytes.isEmpty) {
      return _defaultSingleIcon();
    }
    return BitmapDescriptor.bytes(bytes);
  }

  String _viewportKey(LatLngBounds bounds, double zoom) {
    String f(double v) => v.toStringAsFixed(4);
    return '${f(bounds.southwest.latitude)}:${f(bounds.southwest.longitude)}:'
        '${f(bounds.northeast.latitude)}:${f(bounds.northeast.longitude)}:'
        '${zoom.toStringAsFixed(2)}';
  }

  String _venueFingerprint(List<Venue> venues) {
    if (venues.isEmpty) return 'empty';
    final parts =
        venues
            .map(
              (v) =>
                  '${_venueIdentity(v)}:${v.latitude.toStringAsFixed(5)}:${v.longitude.toStringAsFixed(5)}',
            )
            .toList()
          ..sort();
    return parts.join(';');
  }

  String _markerFingerprint(Set<Marker> markers) {
    if (markers.isEmpty) return 'empty';
    final parts =
        markers
            .map(
              (m) =>
                  '${m.markerId.value}:${m.position.latitude.toStringAsFixed(5)}:${m.position.longitude.toStringAsFixed(5)}:${m.zIndexInt}',
            )
            .toList()
          ..sort();
    return parts.join(';');
  }

  String _venueIdentity(Venue venue) {
    if (venue.id.isNotEmpty) return venue.id;
    if ((venue.placeId ?? '').isNotEmpty) return venue.placeId!;
    return '${venue.name}_${venue.latitude}_${venue.longitude}';
  }

  List<Venue> _filterClusterInputVenues(List<Venue> venues) {
    if (venues.isEmpty) return const [];
    return venues
        .where((v) => _clusterInputFilters.every((f) => f(v)))
        .toList();
  }

  static bool _isRelevantSocialVenue(Venue venue) {
    final normalized = _normalizeVenueType(venue.type);
    if (normalized.isEmpty) return false;
    if (_excludedVenueTypes.contains(normalized)) return false;
    return _includedVenueTypes.contains(normalized);
  }

  static String _normalizeVenueType(String rawType) {
    return rawType
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final query = value.trim();
    if (query.isEmpty) {
      setState(() {
        _searchLoading = false;
        _searchError = null;
        _searchResults = const [];
        _showSearchResults = _searchFocusNode.hasFocus;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    final location = _currentLocation;
    if (location == null) return;
    final token = ++_searchRequestToken;
    setState(() {
      _searchLoading = true;
      _searchError = null;
      _showSearchResults = true;
    });

    try {
      final results = await _venueRepository.searchVenues(
        query: query,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted || token != _searchRequestToken) return;
      setState(() {
        _searchResults = results;
        _searchLoading = false;
      });
    } catch (_) {
      if (!mounted || token != _searchRequestToken) return;
      setState(() {
        _searchResults = const [];
        _searchLoading = false;
        _searchError = 'Search failed. Please try again.';
      });
    }
  }

  Future<void> _onSearchResultTap(Venue venue) async {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _selectedSearchVenue = venue;
      _showSearchResults = false;
      _searchResults = const [];
      _searchError = null;
      _searchController.text = venue.name;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    });

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(venue.latitude, venue.longitude),
          zoom: 17,
        ),
      ),
    );
    _recomputeClusters(force: true);
  }

  void _closeSearchPanel() {
    if (!_showSearchResults &&
        !_searchFocusNode.hasFocus &&
        _searchResults.isEmpty &&
        _searchError == null) {
      return;
    }
    _searchFocusNode.unfocus();
    setState(() {
      _showSearchResults = false;
      _searchResults = const [];
      _searchError = null;
      _searchLoading = false;
    });
  }

  Widget _buildSearchBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Colors.black12,
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 20, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: 'Search places on map',
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchLoading)
            const SizedBox(
              height: 16,
              width: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (_searchController.text.trim().isNotEmpty)
            IconButton(
              onPressed: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              icon: const Icon(Icons.close, size: 18, color: Colors.grey),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsPanel() {
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final shouldShow = _showSearchResults && (hasQuery || _searchLoading);
    if (!shouldShow) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            blurRadius: 14,
            offset: Offset(0, 4),
            color: Colors.black12,
          ),
        ],
      ),
      child: _buildSearchResultsContent(),
    );
  }

  Widget _buildSearchResultsContent() {
    if (_searchLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Text('Searching venues...'),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _searchError!,
          style: const TextStyle(color: Colors.redAccent),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No venues found for this query.'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final hasRating = item.rating != null && item.rating! > 0;
        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              'https://www.gstatic.com/images/branding/product/1x/maps_32dp.png',
              width: 24,
              height: 24,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.map_rounded,
                size: 18,
                color: Colors.grey,
              ),
            ),
          ),
          title: Text(
            item.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                item.address.isNotEmpty ? item.address : '-',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Icon(
                    Icons.star_rounded,
                    size: 14,
                    color: Colors.amber,
                  ),
                  const SizedBox(width: 3),
                  Text(
                    hasRating
                        ? 'Google rating ${item.rating!.toStringAsFixed(1)}'
                        : 'Google rating unavailable',
                    style: const TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          onTap: () => _onSearchResultTap(item),
        );
      },
    );
  }

  Future<void> _enableLocationPermission() async {
    final status = await Permission.location.status;

    if (status.isGranted) {
      await _loadLocation();
    } else if (status.isDenied) {
      final result = await Permission.location.request();
      if (result.isGranted) {
        await _loadLocation();
      }
    } else if (status.isPermanentlyDenied) {
      await openAppSettings();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_locationPermissionDenied) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.location_off_outlined, size: 48),
              const SizedBox(height: 12),
              const Text(
                'Location permission needed',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Enable location to load nearby venues on the map.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              ElevatedButton(
                onPressed: _enableLocationPermission,
                child: const Text('Enable'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentLocation == null) {
      return const Center(child: Text('Location unavailable'));
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(
            target: _currentLocation!,
            zoom: 15,
          ),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          compassEnabled: true,
          zoomControlsEnabled: false,
          onMapCreated: (controller) {
            _mapController = controller;
            _latestCameraPosition = CameraPosition(
              target: _currentLocation!,
              zoom: 15,
            );
            _recomputeClusters(force: true);
          },
          onCameraMove: (position) {
            _latestCameraPosition = position;
          },
          onTap: (_) => _closeSearchPanel(),
          onCameraIdle: _recomputeClusters,
          markers: _markers,
        ),

        /// 🔍 SEARCH BAR
        if (!widget.hideSearch)
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Column(
              children: [
                _buildSearchBar(),
                const SizedBox(height: 8),
                _buildSearchResultsPanel(),
              ],
            ),
          ),

        /// 🎛️ RIGHT CONTROLS
        if (!widget.hideSearch)
          Positioned(
            right: 16,
            top: 90,
            child: Column(
              children: [
                const _CircleIcon(Icons.layers_outlined),
                SizedBox(height: 12),
                _CircleIcon(
                  Icons.navigation_outlined,
                  onTap: () {
                    if (_currentLocation == null || _mapController == null) {
                      return;
                    }
                    _mapController!.animateCamera(
                      CameraUpdate.newLatLng(_currentLocation!),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// ⚪ FLOATING ICON
class _CircleIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _CircleIcon(this.icon, {this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: IconButton(onPressed: onTap, icon: Icon(icon)),
    );
  }
}
