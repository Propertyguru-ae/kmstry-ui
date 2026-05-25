import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'cluster_service.dart';
import 'dart:math' as math;
import 'venue_detail_page.dart';
import 'venue_checkin_stats_row.dart';

class VenueMapView extends StatefulWidget {
  final bool hideSearch;
  final ValueChanged<bool>? onLocationAccessChanged;
  final ValueChanged<LatLng>? onLocationResolved;
  final ValueChanged<bool>? onSearchActivityChanged;
  final ValueChanged<Venue>? onVenueDetailClosed;
  final List<Venue> venues;
  final String? selectedVenueId;
  final ValueChanged<Venue>? onVenueTap;

  const VenueMapView({
    super.key,
    this.hideSearch = false,
    this.onLocationAccessChanged,
    this.onLocationResolved,
    this.onSearchActivityChanged,
    this.onVenueDetailClosed,
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
  final VenueContextRepository _venueContextRepository =
      VenueContextRepository();
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
  final Map<String, BitmapDescriptor> _photoMarkerIconCache = {};
  final Set<String> _photoMarkerIconLoadingKeys = <String>{};
  BitmapDescriptor? _singleDefaultIcon;
  BitmapDescriptor? _singleSelectedIcon;
  BitmapDescriptor? _singlePressedIcon;

  /// While the venue pin popup is open, that marker uses a different hue.
  String? _pressedMarkerVenueKey;
  Timer? _searchDebounce;
  Timer? _photoIconRefreshDebounce;
  bool _searchLoading = false;
  String? _searchError;
  List<Venue> _searchResults = const [];

  /// Last venue chosen from type search — shown as a normal map pin if not already on the map.
  Venue? _selectedSearchVenue;
  int _searchRequestToken = 0;
  bool _showSearchResults = false;
  final Map<String, VenueCheckinStats> _liveStatsByVenueKey = {};
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
        // Kullanıcı aynı sorguya tekrar dokunduğunda liste boşsa yeniden getir.
        final query = _searchController.text.trim();
        if (query.isNotEmpty &&
            _searchResults.isEmpty &&
            !_searchLoading &&
            _searchError == null) {
          _performSearch(query);
        }
      }
      _notifySearchActivity();
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
        if (_matchesSelectedVenue(venue)) {
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
    widget.onSearchActivityChanged?.call(false);
    _searchDebounce?.cancel();
    _photoIconRefreshDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  bool get _isSearchActive {
    return _searchFocusNode.hasFocus ||
        _searchLoading ||
        _showSearchResults ||
        _searchController.text.trim().isNotEmpty;
  }

  void _notifySearchActivity() {
    widget.onSearchActivityChanged?.call(_isSearchActive);
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

    // 1. Cache'den son bilinen konumu anında göster — GPS warm-up beklemeden
    //    ilk açılışta harita ve listenin hemen dolmasını sağlar.
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null && mounted) {
        setState(() {
          _currentLocation = LatLng(lastKnown.latitude, lastKnown.longitude);
          _loading = false;
        });
        widget.onLocationAccessChanged?.call(true);
        widget.onLocationResolved?.call(_currentLocation!);
        _recomputeClusters(force: true);
      }
    } catch (_) {
      // Yoksa devam — getCurrentPosition dener
    }

    // 2. Arka planda daha hassas konum al; anlamlı fark varsa yenile.
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: const Duration(seconds: 8),
      );

      if (!mounted) return;

      final updated = LatLng(position.latitude, position.longitude);
      final prev = _currentLocation;
      final moved = prev == null ||
          (updated.latitude - prev.latitude).abs() > 0.0005 ||
          (updated.longitude - prev.longitude).abs() > 0.0005;

      setState(() {
        _currentLocation = updated;
        _loading = false;
      });

      if (prev == null) {
        // İlk kez çözüldü — getLastKnownPosition da yoktu
        widget.onLocationAccessChanged?.call(true);
      }
      if (moved) {
        widget.onLocationResolved?.call(_currentLocation!);
        _recomputeClusters(force: true);
      }
    } catch (_) {
      if (!mounted) return;
      // Cache'den konum zaten varsa hata gösterme, çalışmaya devam et.
      if (_currentLocation == null) {
        setState(() {
          _loading = false;
          _locationPermissionDenied = true;
        });
        widget.onLocationAccessChanged?.call(false);
      } else {
        setState(() => _loading = false);
      }
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
      // Map SDK henüz hazır değil — kısa delay sonra tekrar dene.
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || token != _clusterJobToken) return;
      try {
        bounds = await map.getVisibleRegion();
      } catch (_) {
        return;
      }
    }
    if (!mounted || token != _clusterJobToken) return;

    final viewportKey = _viewportKey(bounds, camera.zoom);
    final selectedKey =
        '${widget.selectedVenueId ?? ''}|${_selectedSearchVenue != null ? _venueIdentity(_selectedSearchVenue!) : ''}|${_pressedMarkerVenueKey ?? ''}';
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
      final onlySearch = <Marker>{};
      _appendSearchSelectionMarker(onlySearch);
      final markerKey =
          '${_markerFingerprint(onlySearch)}|${_pressedMarkerVenueKey ?? ''}|empty';
      if (onlySearch.isEmpty) {
        if (_markers.isNotEmpty) {
          setState(() => _markers = const {});
        }
        _lastMarkerKey = '';
        return;
      }
      if (markerKey == _lastMarkerKey) return;
      _lastMarkerKey = markerKey;
      if (mounted) {
        setState(() => _markers = onlySearch);
      }
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
        final venue = _venueWithLiveStats(node.primaryVenue);
        final vid = _venueIdentity(venue);
        final isSelected = _matchesSelectedVenue(venue);
        final isPressed = _pressedMarkerVenueKey == vid;
        final venueIcon = _singleVenueIcon(
          venue: venue,
          isSelected: isSelected,
          isPressed: isPressed,
        );
        builtMarkers.add(
          Marker(
            markerId: MarkerId('venue:$vid'),
            position: LatLng(venue.latitude, venue.longitude),
            infoWindow: InfoWindow(
              title: venue.name,
              snippet: _venueMarkerInfoSnippet(venue),
            ),
            icon: venueIcon,
            zIndexInt: isPressed ? 5 : (isSelected ? 4 : 1),
            onTap: () async {
              final refreshed = await _refreshLiveStatsForVenue(venue);
              if (!mounted) return;
              await _mapController?.showMarkerInfoWindow(
                MarkerId('venue:$vid'),
              );
              await _showVenueMarkerPopup(refreshed);
            },
          ),
        );
      }
    }

    _appendSearchSelectionMarker(builtMarkers);

    final markerKey =
        '${_markerFingerprint(builtMarkers)}|${_pressedMarkerVenueKey ?? ''}';
    if (markerKey == _lastMarkerKey) return;
    _lastMarkerKey = markerKey;
    if (mounted) {
      setState(() => _markers = builtMarkers);
    }
  }

  BitmapDescriptor _defaultSingleIcon() {
    return _singleDefaultIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );
  }

  BitmapDescriptor _selectedSingleIcon() {
    return _singleSelectedIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );
  }

  BitmapDescriptor _pressedSingleIcon() {
    return _singlePressedIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueBlue,
    );
  }

  BitmapDescriptor _singleVenueIcon({
    required Venue venue,
    required bool isSelected,
    required bool isPressed,
  }) {
    final photoUrl = venue.photoUrl.trim();
    if (photoUrl.isEmpty) {
      return _fallbackSingleIcon(isSelected: isSelected, isPressed: isPressed);
    }

    final ringColor = isPressed
        ? AppTheme.brandPrimary
        : isSelected
        ? AppTheme.brandPrimary
        : Colors.transparent;
    final cacheKey =
        '${_venueIdentity(venue)}|$photoUrl|$isSelected|$isPressed';
    final cached = _photoMarkerIconCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    _schedulePhotoMarkerIconBuild(
      cacheKey: cacheKey,
      photoUrl: photoUrl,
      ringColor: ringColor,
    );
    return _fallbackSingleIcon(isSelected: isSelected, isPressed: isPressed);
  }

  BitmapDescriptor _fallbackSingleIcon({
    required bool isSelected,
    required bool isPressed,
  }) {
    if (isPressed) return _pressedSingleIcon();
    if (isSelected) return _selectedSingleIcon();
    return _defaultSingleIcon();
  }

  void _schedulePhotoMarkerIconBuild({
    required String cacheKey,
    required String photoUrl,
    required Color ringColor,
  }) {
    if (_photoMarkerIconLoadingKeys.contains(cacheKey)) return;
    _photoMarkerIconLoadingKeys.add(cacheKey);
    _buildPhotoMarkerIcon(photoUrl: photoUrl, ringColor: ringColor)
        .then((icon) {
          if (icon == null || !mounted) return;
          _photoMarkerIconCache[cacheKey] = icon;
          _schedulePhotoIconRefresh();
        })
        .whenComplete(() {
          _photoMarkerIconLoadingKeys.remove(cacheKey);
        });
  }

  void _schedulePhotoIconRefresh() {
    _photoIconRefreshDebounce?.cancel();
    _photoIconRefreshDebounce = Timer(const Duration(milliseconds: 120), () {
      if (!mounted) return;
      // Icons changed but marker IDs/positions are the same → fingerprint would
      // match and setState would be skipped. Reset the key so the icon swap
      // always reaches setState.
      _lastMarkerKey = '';
      _recomputeClusters(force: true);
    });
  }

  Future<BitmapDescriptor?> _buildPhotoMarkerIcon({
    required String photoUrl,
    required Color ringColor,
  }) async {
    try {
      final uri = Uri.tryParse(photoUrl);
      if (uri == null) return null;
      final data = await NetworkAssetBundle(uri).load(uri.toString());
      final bytes = data.buffer.asUint8List();
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: 56,
        targetHeight: 56,
      );
      final frame = await codec.getNextFrame();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const size = 56.0;
      const center = Offset(size / 2, size / 2);
      const outerR = 26.0;
      const imageR = 20.5;

      final shadowPaint = Paint()
        ..color = Colors.black.withValues(alpha: 0.30)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
      canvas.drawCircle(center.translate(0, 2), outerR, shadowPaint);

      canvas.drawCircle(
        center,
        outerR,
        Paint()..color = const Color(0xFF0F172A),
      );
      if (ringColor.alpha > 0) {
        canvas.drawCircle(
          center,
          outerR,
          Paint()
            ..color = ringColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3,
        );
      }

      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: imageR));
      canvas.save();
      canvas.clipPath(clipPath);
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: center, radius: imageR),
        image: frame.image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();

      final image = await recorder.endRecording().toImage(56, 56);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) return null;
      return BitmapDescriptor.bytes(pngBytes);
    } catch (_) {
      return null;
    }
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
      fill = AppTheme.brandPrimary;
    } else if (count > 50) {
      fill = const Color(0xFF0F172A); // deep slate
    } else if (count > 20) {
      fill = const Color(0xFF1D4ED8); // strong cobalt
    } else {
      fill = const Color(0xFF334155); // muted blue-slate
    }

    const stroke = Colors.transparent;

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
    if (stroke.alpha > 0) {
      canvas.drawCircle(center, radius - 3, strokePaint);
    }

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

  /// Search API may omit check-in aggregates; copy from loaded nearby [widget.venues] when same place.
  List<Venue> _enrichSearchResultsWithNearbyVenues(List<Venue> results) {
    final nearby = widget.venues;
    if (nearby.isEmpty) return results;
    return results.map((r) {
      var merged = r;
      for (final v in nearby) {
        if (r.isSameVenueAs(v)) {
          merged = merged.mergeCheckinFieldsFrom(v);
        }
      }
      return merged;
    }).toList();
  }

  /// Standard red/yellow pin (not the old large "S" badge). Skipped if the same venue is already a cluster pin.
  void _appendSearchSelectionMarker(Set<Marker> builtMarkers) {
    final sv = _selectedSearchVenue;
    if (sv == null) return;
    if (!sv.latitude.isFinite ||
        !sv.longitude.isFinite ||
        (sv.latitude == 0 && sv.longitude == 0)) {
      return;
    }
    final searchId = _venueIdentity(sv);
    final alreadyPinned = builtMarkers.any(
      (m) => m.markerId.value == 'venue:$searchId',
    );
    if (alreadyPinned) return;

    final searchPressed = _pressedMarkerVenueKey == searchId;
    final icon = _singleVenueIcon(
      venue: sv,
      isSelected: true,
      isPressed: searchPressed,
    );
    builtMarkers.add(
      Marker(
        markerId: MarkerId('search:$searchId'),
        position: LatLng(sv.latitude, sv.longitude),
        icon: icon,
        zIndexInt: searchPressed ? 5 : 6,
        infoWindow: InfoWindow(
          title: sv.name,
          snippet: _venueMarkerInfoSnippet(sv),
        ),
        onTap: () => _showVenueMarkerPopup(sv),
      ),
    );
  }

  List<Venue> _filterClusterInputVenues(List<Venue> venues) {
    if (venues.isEmpty) return const [];
    return venues
        .where((v) => _clusterInputFilters.every((f) => f(v)))
        .toList();
  }

  static bool _isRelevantSocialVenue(Venue venue) {
    final normalizedTypes = _normalizedVenueTypes(venue);
    if (normalizedTypes.isEmpty) {
      return venue.isInDb;
    }
    if (normalizedTypes.any(_excludedVenueTypes.contains)) return false;
    if (normalizedTypes.any(_includedVenueTypes.contains)) return true;
    return venue.isInDb;
  }

  static Set<String> _normalizedVenueTypes(Venue venue) {
    final out = <String>{};
    final primary = _normalizeVenueType(venue.type);
    if (primary.isNotEmpty) out.add(primary);
    for (final raw in venue.types) {
      final normalized = _normalizeVenueType(raw);
      if (normalized.isNotEmpty) out.add(normalized);
    }
    return out;
  }

  static String _normalizeVenueType(String rawType) {
    final normalized = rawType
        .trim()
        .toLowerCase()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');
    switch (normalized) {
      case 'night_club':
        return 'nightclub';
      case 'pub':
      case 'brewpub':
        return 'bar';
      default:
        return normalized;
    }
  }

  bool _matchesSelectedVenue(Venue venue) {
    final selectedId = widget.selectedVenueId;
    if (selectedId == null || selectedId.isEmpty) return false;
    if (venue.id == selectedId) return true;
    if ((venue.placeId ?? '') == selectedId) return true;
    return _venueIdentity(venue) == selectedId;
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
        _selectedSearchVenue = null;
      });
      _notifySearchActivity();
      _recomputeClusters(force: true);
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
    _notifySearchActivity();

    try {
      final results = await _venueRepository.searchVenues(
        query: query,
        latitude: location.latitude,
        longitude: location.longitude,
      );
      if (!mounted || token != _searchRequestToken) return;
      setState(() {
        _searchResults = _enrichSearchResultsWithNearbyVenues(results);
        _searchLoading = false;
      });
      _notifySearchActivity();
    } catch (_) {
      if (!mounted || token != _searchRequestToken) return;
      setState(() {
        _searchResults = const [];
        _searchLoading = false;
        _searchError = 'Search failed. Please try again.';
      });
      _notifySearchActivity();
    }
  }

  Future<void> _onSearchResultTap(Venue venue) async {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _selectedSearchVenue = venue;
      _showSearchResults = false;
      _searchError = null;
      _searchController.text = venue.name;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    });
    _notifySearchActivity();

    await _mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(venue.latitude, venue.longitude),
          zoom: 17,
        ),
      ),
    );
    if (!mounted) return;
    // Same UX as tapping the pin: yellow “pressed” marker + bottom sheet.
    await _showVenueMarkerPopup(venue);
  }

  Venue _latestVenueSnapshotFor(Venue venue) {
    for (final v in widget.venues) {
      if (v.isSameVenueAs(venue)) return v;
    }
    return venue;
  }

  String? _extractVenueIdFromResolve(Map<String, dynamic> response) {
    final direct =
        response['venueId'] ?? response['venue_id'] ?? response['id'];
    if (direct is String && direct.isNotEmpty) return direct;
    final nested = response['venue'];
    if (nested is Map) {
      final mapped = nested['id'] ?? nested['venueId'] ?? nested['venue_id'];
      if (mapped is String && mapped.isNotEmpty) return mapped;
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

  Venue _withStats(Venue venue, VenueCheckinStats stats) {
    return Venue(
      id: venue.id,
      placeId: venue.placeId,
      name: venue.name,
      type: venue.type,
      status: venue.status,
      address: venue.address,
      city: venue.city,
      photoUrl: venue.photoUrl,
      latitude: venue.latitude,
      longitude: venue.longitude,
      tag: venue.tag,
      source: venue.source,
      isInDb: venue.isInDb,
      canCheckin: venue.canCheckin,
      checkinCountActive: stats.checkinCountActive,
      checkinCountMale: stats.male,
      checkinCountFemale: stats.female,
      eventSummary: venue.eventSummary,
      verificationLevel: venue.verificationLevel,
      distanceMeters: venue.distanceMeters,
      openNow: venue.openNow,
      rating: venue.rating,
      types: venue.types,
    );
  }

  Venue _venueWithLiveStats(Venue venue) {
    final key = _venueIdentity(venue);
    final stats = _liveStatsByVenueKey[key];
    if (stats == null) return venue;
    return _withStats(venue, stats);
  }

  Future<Venue> _refreshLiveStatsForVenue(Venue venue) async {
    final resolvedVenueId = await _resolveVenueIdForStats(venue);
    if (resolvedVenueId == null || resolvedVenueId.isEmpty) {
      return _venueWithLiveStats(venue);
    }
    try {
      final stats = await _venueContextRepository.getVenueCheckinStats(
        resolvedVenueId,
      );
      if (!mounted) return _venueWithLiveStats(venue);
      _liveStatsByVenueKey[_venueIdentity(venue)] = stats;
      await _recomputeClusters(force: true);
      return _venueWithLiveStats(venue);
    } catch (_) {
      return _venueWithLiveStats(venue);
    }
  }

  Future<void> _openVenueDetailFromMap(Venue venue) async {
    widget.onVenueTap?.call(venue);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
    );
    if (!mounted) return;
    widget.onVenueDetailClosed?.call(venue);
    // Keep the map UX continuous: return to same selected venue popup.
    await _showVenueMarkerPopup(_latestVenueSnapshotFor(venue));
  }

  /// Short line for native [InfoWindow] (character-limited on some platforms).
  String _venueMarkerInfoSnippet(Venue venue) {
    final parts = <String>[];
    if (venue.rating != null && venue.rating! > 0) {
      parts.add('★${venue.rating!.toStringAsFixed(1)}');
    }
    final total = venue.checkinCountActive;
    if (total != null) {
      if (total == 0) {
        parts.add('Be the first to check in');
      } else {
        parts.add('$total checked in');
      }
    } else {
      final m = venue.checkinCountMale;
      final f = venue.checkinCountFemale;
      if (m != null && f != null) {
        final sum = m + f;
        if (sum == 0) {
          parts.add('Be the first to check in');
        } else {
          parts.add('$sum checked in');
        }
      }
    }
    if (venue.checkinCountMale != null && venue.checkinCountMale! > 0) {
      parts.add('♂${venue.checkinCountMale}');
    }
    if (venue.checkinCountFemale != null && venue.checkinCountFemale! > 0) {
      parts.add('♀${venue.checkinCountFemale}');
    }
    if (parts.isEmpty) {
      if (!venue.isInDb) {
        return 'Be the first to check in';
      }
      return venue.source == 'db'
          ? 'Tap Open for details'
          : 'Google place · Open for details';
    }
    return parts.join(' · ');
  }

  Future<void> _showVenueMarkerPopup(Venue venue) async {
    if (!mounted) return;
    final liveVenue = await _refreshLiveStatsForVenue(venue);

    final key = _venueIdentity(liveVenue);
    setState(() => _pressedMarkerVenueKey = key);
    await _recomputeClusters(force: true);
    if (!mounted) return;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final hasRating = liveVenue.rating != null && liveVenue.rating! > 0;
    final surface = isDark
        ? colors.surface.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.97);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);
    final subtitleColor = colors.onSurface.withValues(alpha: 0.72);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      showDragHandle: false,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 28,
                    offset: const Offset(0, 12),
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.52)
                        : Colors.black.withValues(alpha: 0.12),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.onSurface.withValues(alpha: 0.24),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: border),
                            color: colors.surface.withValues(alpha: 0.8),
                            image: liveVenue.photoUrl.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(liveVenue.photoUrl),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: liveVenue.photoUrl.isEmpty
                              ? Icon(
                                  Icons.storefront_rounded,
                                  color: colors.onSurface.withValues(
                                    alpha: 0.74,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                liveVenue.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 21,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              if (liveVenue.address.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  liveVenue.address,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: subtitleColor,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: colors.surface.withValues(
                          alpha: isDark ? 0.86 : 0.7,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                      ),
                      child: Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (hasRating) ...[
                            Icon(
                              Icons.star_rounded,
                              size: 18,
                              color: isDark
                                  ? Colors.amber.shade300
                                  : Colors.amber.shade700,
                            ),
                            Text(
                              'Google rating',
                              style: TextStyle(
                                fontSize: 13,
                                color: subtitleColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              liveVenue.rating!.toStringAsFixed(1),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurface,
                              ),
                            ),
                          ] else
                            Text(
                              'No rating',
                              style: TextStyle(
                                fontSize: 13,
                                color: subtitleColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          VenueCheckinStatsRow(
                            venue: liveVenue,
                            isDark: isDark,
                            iconSize: 16,
                            fontSize: 14,
                            treatMissingStatsAsCheckInPrompt: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _openVenueDetailFromMap(liveVenue);
                      },
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    if (!mounted) return;
    setState(() => _pressedMarkerVenueKey = null);
    await _recomputeClusters(force: true);
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
    _notifySearchActivity();
  }

  Widget _buildSearchBar() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final backgroundColor = isDark
        ? theme.colorScheme.surface.withValues(alpha: 0.92)
        : Colors.white.withValues(alpha: 0.96);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white70 : Colors.grey.shade600;
    final iconColor = isDark ? Colors.white70 : Colors.grey.shade700;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.28)
              : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: isDark
                ? Colors.black.withValues(alpha: 0.5)
                : Colors.black12,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(Icons.search, size: 20, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              style: TextStyle(color: textColor),
              decoration: InputDecoration(
                hintText: 'Search places on map',
                hintStyle: TextStyle(color: hintColor),
                filled: false,
                fillColor: Colors.transparent,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                errorBorder: InputBorder.none,
                focusedErrorBorder: InputBorder.none,
                isDense: true,
                isCollapsed: true,
                contentPadding: EdgeInsets.zero,
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
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                _searchController.clear();
                _onSearchChanged('');
              },
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(Icons.close, size: 18, color: iconColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsPanel() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final hasQuery = _searchController.text.trim().isNotEmpty;
    final shouldShow = _showSearchResults && (hasQuery || _searchLoading);
    if (!shouldShow) return const SizedBox.shrink();

    return Container(
      constraints: const BoxConstraints(maxHeight: 320),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withValues(alpha: 0.96)
            : const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : const Color(0xFFE6EEF4),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: isDark
                ? Colors.black.withValues(alpha: 0.42)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ],
      ),
      child: _buildSearchResultsContent(),
    );
  }

  Widget _buildSearchResultsContent() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    if (_searchLoading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Searching venues...',
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    if (_searchError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _searchError!,
          style: TextStyle(
            color: colors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
    if (_searchResults.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No venues found for this query.',
          style: TextStyle(color: colors.onSurface.withValues(alpha: 0.72)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      shrinkWrap: true,
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final hasRating = item.rating != null && item.rating! > 0;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _onSearchResultTap(item),
              child: Ink(
                decoration: BoxDecoration(
                  color: isDark
                      ? colors.surface.withValues(alpha: 0.92)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : const Color(0xFFE6EEF4),
                  ),
                ),
                child: ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  leading: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        'https://www.gstatic.com/images/branding/product/1x/maps_32dp.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.map_rounded,
                          size: 18,
                          color: colors.primary,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    item.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface,
                    ),
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
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
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
                          VenueCheckinStatsRow(
                            venue: item,
                            isDark: isDark,
                            iconSize: 13,
                            fontSize: 11,
                            treatMissingStatsAsCheckInPrompt: true,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surface.withValues(alpha: 0.95)
            : Colors.white,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.3)
              : Colors.black.withValues(alpha: 0.08),
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: isDark
                ? Colors.black.withValues(alpha: 0.5)
                : Colors.black12,
          ),
        ],
      ),
      child: IconButton(
        onPressed: onTap,
        icon: Icon(icon, color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }
}
