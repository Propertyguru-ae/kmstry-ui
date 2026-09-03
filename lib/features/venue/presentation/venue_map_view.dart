import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:kmstry_frontend/features/venue/presentation/map_style.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:permission_handler/permission_handler.dart';
import 'cluster_service.dart';
import 'dart:math' as math;
import 'venue_detail_page.dart';
import 'venue_checkin_stats_row.dart';
import 'venue_list_item.dart';

const _kKmstryBlue = Color(0xFF1A9FE8);
const _kKmstryTeal = Color(0xFF1FD9A8);
const _kKmstryPink = Color(0xFFE020D8);
const _kKmstryOrange = Color(0xFFF08838);
const _kKmstryPurple = Color(0xFF8B5CF6);

/// Marker glow paleti — logonun tüm renkleri. Her venue'ye kimliğine göre
/// STABİL (rebuild'de değişmeyen) rastgele bir renk atanır; böylece harita
/// türden bağımsız, çok renkli ve canlı görünür.
const List<Color> _kGlowPalette = [
  _kKmstryBlue,
  _kKmstryTeal,
  _kKmstryPink,
  _kKmstryOrange,
  _kKmstryPurple,
];

class VenueMapView extends StatefulWidget {
  final bool hideSearch;
  final ValueChanged<bool>? onLocationAccessChanged;
  final ValueChanged<LatLng>? onLocationResolved;
  final ValueChanged<bool>? onSearchActivityChanged;
  final ValueChanged<Venue>? onVenueDetailClosed;
  final List<Venue> venues;
  final List<Venue> listVenues;
  final bool loadingVenues;
  final bool loadingMoreVenues;
  final bool hasMoreVenues;
  final VoidCallback? onLoadMoreVenues;
  final ValueChanged<String?>? onBrowseKeywordChanged;
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
    this.listVenues = const [],
    this.loadingVenues = false,
    this.loadingMoreVenues = false,
    this.hasMoreVenues = false,
    this.onLoadMoreVenues,
    this.onBrowseKeywordChanged,
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
  final VenueCheckinRepository _checkinRepository = VenueCheckinRepository();

  /// Kullanıcının şu an aktif check-in yaptığı venue id — sheet kartında
  /// "You're checked in" rozetiyle işaretlenir.
  String? _activeCheckinVenueId;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final DraggableScrollableController _resultsSheetController =
      DraggableScrollableController();

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
  Brightness? _markerThemeBrightness;

  /// While the venue pin popup is open, that marker uses a different hue.
  String? _pressedMarkerVenueKey;
  Timer? _searchDebounce;
  Timer? _photoIconRefreshDebounce;
  bool _searchLoading = false;
  String? _searchError;
  List<Venue> _searchResults = const [];
  List<_PlaceSuggestion> _placeSuggestions = const [];
  List<_CategoryAreaSuggestion> _categoryAreaSuggestions = const [];

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

  // Heatmap açıklaması ve handler'ı korunur; yeniden açılmaya hazır.
  static const bool _showHeatmapInfoButton = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final themeChanged =
        _markerThemeBrightness != null && _markerThemeBrightness != brightness;
    _markerThemeBrightness = brightness;
    if (!themeChanged) return;

    _clusterIconCache.clear();
    _photoMarkerIconCache.clear();
    _lastMarkerKey = '';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _recomputeClusters(force: true);
    });
  }

  // ── Harita filtreleri ──────────────────────────────────────────────────────
  /// Seçili kategoriler (venue.type): restaurant/cafe/bar/club/lounge. Boş = tümü.
  final Set<String> _selectedCategories = <String>{};

  /// Seçili external partnership platformları. Boş = filtre yok.
  final Set<String> _selectedPartnerships = <String>{};

  String? _selectedCuisineKeyword;
  String? _selectedCuisineLabel;
  bool _busyNowOnly = false;
  bool _openNowOnly = false;

  /// Seçili minimum puan eşikleri (ör. 4.0, 4.5). Boş = filtre yok.
  /// Çoklu seçimde en düşük eşik geçerlidir (OR mantığı).
  final Set<double> _selectedRatings = <double>{};

  /// Seçili maksimum mesafe bantları (metre). Boş = filtre yok.
  /// Çoklu seçimde en geniş bant geçerlidir (OR mantığı).
  final Set<int> _selectedDistances = <int>{};
  bool _showResultsSheet = true;
  bool _resultsSheetExpanded = false;

  static const double _resultsSheetMinSize = 0.18;
  static const double _resultsSheetInitialSize = 0.48;
  static const double _resultsSheetMaxSize = 0.94;

  static const List<({String key, String label, IconData icon})>
  _categoryOptions = [
    (key: 'restaurant', label: 'Restaurants', icon: Icons.restaurant_rounded),
    (key: 'cafe', label: 'Cafes', icon: Icons.local_cafe_rounded),
    (key: 'bar', label: 'Bars', icon: Icons.local_bar_rounded),
    (key: 'club', label: 'Nightclubs', icon: Icons.nightlife_rounded),
    (key: 'lounge', label: 'Lounges', icon: Icons.weekend_rounded),
  ];

  static const List<({String keyword, String label, IconData icon})>
  _cuisineOptions = [
    (keyword: 'pizza', label: 'Pizza', icon: Icons.local_pizza_rounded),
    (keyword: 'sushi', label: 'Sushi', icon: Icons.set_meal_rounded),
    (keyword: 'burger', label: 'Burger', icon: Icons.lunch_dining_rounded),
    (
      keyword: 'breakfast',
      label: 'Breakfast',
      icon: Icons.free_breakfast_rounded,
    ),
    (keyword: 'dessert', label: 'Dessert', icon: Icons.icecream_rounded),
    (keyword: 'steak', label: 'Steak', icon: Icons.dinner_dining_rounded),
    (keyword: 'seafood', label: 'Seafood', icon: Icons.set_meal_rounded),
  ];

  static const List<({String key, String label})> _partnershipOptions = [
    (key: 'THE_ENTERTAINER', label: 'The Entertainer'),
    (key: 'FAZAA', label: 'Fazaa'),
    (key: 'ESAAD', label: 'ESAAD'),
    (key: 'COBONE', label: 'Cobone'),
    (key: 'GROUPON', label: 'Groupon'),
    (key: 'OTHER', label: 'Other'),
  ];

  bool get _hasActiveFilters =>
      _selectedCategories.isNotEmpty ||
      _selectedPartnerships.isNotEmpty ||
      _selectedCuisineKeyword != null ||
      _busyNowOnly ||
      _openNowOnly ||
      _selectedRatings.isNotEmpty ||
      _selectedDistances.isNotEmpty;

  bool get _hasBrowseContext =>
      _hasActiveFilters || _searchController.text.trim().isNotEmpty;

  /// Kullanıcı filtrelerini tek bir venue'ye uygular.
  bool _passesUserFilters(Venue v) {
    if (_selectedCategories.isNotEmpty) {
      final normalizedTypes = _normalizedVenueTypes(v);
      if (!normalizedTypes.any(_selectedCategories.contains)) return false;
    }
    if (_busyNowOnly) {
      if ((v.checkinCountActive ?? 0) <= 0) return false;
    }
    if (_openNowOnly) {
      if (v.openNow != true) return false;
    }
    if (_selectedRatings.isNotEmpty) {
      final r = v.rating;
      final minRequired = _selectedRatings.reduce(math.min);
      if (r == null || r < minRequired) return false;
    }
    if (_selectedDistances.isNotEmpty) {
      final d = v.distanceMeters;
      final maxAllowed = _selectedDistances.reduce(math.max);
      if (d == null || d > maxAllowed) return false;
    }
    if (_selectedPartnerships.isNotEmpty) {
      if (!v.partnershipPlatforms.any(_selectedPartnerships.contains)) {
        return false;
      }
    }
    return true;
  }

  void _onFiltersChanged() {
    setState(() {});
    _recomputeClusters(force: true);
  }

  void _clearAllFilters() {
    setState(() {
      _selectedCategories.clear();
      _selectedPartnerships.clear();
      _selectedCuisineKeyword = null;
      _selectedCuisineLabel = null;
      _busyNowOnly = false;
      _openNowOnly = false;
      _selectedRatings.clear();
      _selectedDistances.clear();
      _searchController.clear();
    });
    widget.onBrowseKeywordChanged?.call(null);
    _recomputeClusters(force: true);
  }

  // ── Kategori chip satırı ───────────────────────────────────────────────────
  Widget _buildFilterChipsRow() {
    return SizedBox(
      height: 34,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          if (_hasActiveFilters)
            _FilterChip(
              icon: Icons.close_rounded,
              label: 'Clear',
              selected: false,
              accent: _kKmstryPink,
              onTap: _clearAllFilters,
            ),
          _FilterChip(
            icon: Icons.local_fire_department_rounded,
            label: 'Busy now',
            selected: _busyNowOnly,
            accent: _kKmstryTeal,
            onTap: _openBusyResults,
          ),
          for (final option in _categoryOptions)
            _FilterChip(
              icon: option.icon,
              label: option.label,
              selected:
                  _selectedCategories.length == 1 &&
                  _selectedCategories.contains(option.key),
              onTap: () => _openCategoryResults(option.key),
            ),
          for (final option in _cuisineOptions)
            _FilterChip(
              icon: option.icon,
              label: option.label,
              selected: _selectedCuisineKeyword == option.keyword,
              onTap: () => _openCuisineResults(option.keyword, option.label),
            ),
        ],
      ),
    );
  }

  void _openBusyResults() {
    setState(() {
      _selectedCategories.clear();
      _selectedCuisineKeyword = null;
      _selectedCuisineLabel = null;
      _busyNowOnly = true;
      _showResultsSheet = true;
      _showSearchResults = false;
      _searchController.text = 'Busy now';
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    });
    widget.onBrowseKeywordChanged?.call(null);
    _onFiltersChanged();
  }

  void _openCategoryResults(String categoryKey) {
    final label = _categoryLabelForKey(categoryKey);
    setState(() {
      _busyNowOnly = false;
      _selectedCuisineKeyword = null;
      _selectedCuisineLabel = null;
      _selectedCategories
        ..clear()
        ..add(categoryKey);
      _showResultsSheet = true;
      _showSearchResults = false;
      _searchController.text = label;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    });
    widget.onBrowseKeywordChanged?.call(null);
    _onFiltersChanged();
  }

  void _openCuisineResults(String keyword, String label) {
    _searchDebounce?.cancel();
    setState(() {
      _busyNowOnly = false;
      _selectedCategories.clear();
      _selectedCuisineKeyword = keyword;
      _selectedCuisineLabel = label;
      _showResultsSheet = true;
      _showSearchResults = false;
      _searchError = null;
      _searchLoading = false;
      _searchResults = const [];
      _placeSuggestions = const [];
      _categoryAreaSuggestions = const [];
      _selectedSearchVenue = null;
      _searchController.text = label;
      _searchController.selection = TextSelection.collapsed(
        offset: _searchController.text.length,
      );
    });
    widget.onBrowseKeywordChanged?.call(keyword);
    _notifySearchActivity();
    _recomputeClusters(force: true);
  }

  void _closeResultsSheet() {
    if (_hasBrowseContext) {
      _clearSearchAndFilters();
      return;
    }
    _collapseResultsSheet();
  }

  void _collapseResultsSheet() {
    _closeSearchPanel();
    if (!_showResultsSheet) {
      setState(() => _showResultsSheet = true);
    }
    if (_resultsSheetController.isAttached) {
      _resultsSheetController.animateTo(
        _resultsSheetMinSize,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _clearSearchAndFilters() {
    _searchDebounce?.cancel();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _selectedCategories.clear();
      _selectedPartnerships.clear();
      _selectedCuisineKeyword = null;
      _selectedCuisineLabel = null;
      _busyNowOnly = false;
      _openNowOnly = false;
      _selectedRatings.clear();
      _selectedDistances.clear();
      _searchLoading = false;
      _searchError = null;
      _searchResults = const [];
      _placeSuggestions = const [];
      _categoryAreaSuggestions = const [];
      _selectedSearchVenue = null;
      _showSearchResults = false;
      _showResultsSheet = true;
    });
    widget.onBrowseKeywordChanged?.call(null);
    _notifySearchActivity();
    _recomputeClusters(force: true);
    if (_resultsSheetController.isAttached) {
      _resultsSheetController.animateTo(
        _resultsSheetInitialSize,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
  }

  String get _resultsTitle {
    if (_selectedCuisineLabel != null) return _selectedCuisineLabel!;
    if (_busyNowOnly && _selectedCategories.isEmpty) return 'Busy now';
    if (_selectedCategories.length == 1) {
      final key = _selectedCategories.first;
      for (final option in _categoryOptions) {
        if (option.key == key) return option.label;
      }
    }
    return 'Nearby venues';
  }

  String _categoryLabelForKey(String key) {
    for (final option in _categoryOptions) {
      if (option.key == key) return option.label;
    }
    return 'Nearby venues';
  }

  IconData _categoryIconForKey(String key) {
    for (final option in _categoryOptions) {
      if (option.key == key) return option.icon;
    }
    return Icons.place_rounded;
  }

  String? _categoryKeyForQuery(String rawQuery) {
    final normalized = rawQuery
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ');
    switch (normalized) {
      case 'restaurant':
      case 'restaurants':
        return 'restaurant';
      case 'cafe':
      case 'cafes':
      case 'coffee':
      case 'coffee shop':
      case 'coffee shops':
        return 'cafe';
      case 'bar':
      case 'bars':
      case 'pub':
      case 'pubs':
        return 'bar';
      case 'nightclub':
      case 'nightclubs':
      case 'night club':
      case 'night clubs':
      case 'club':
      case 'clubs':
        return 'club';
      case 'lounge':
      case 'lounges':
        return 'lounge';
    }
    return null;
  }

  ({String keyword, String label})? _cuisineForQuery(String rawQuery) {
    final normalized = rawQuery
        .trim()
        .toLowerCase()
        .replaceAll('-', ' ')
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    for (final option in _cuisineOptions) {
      if (normalized == option.keyword.toLowerCase() ||
          normalized == option.label.toLowerCase()) {
        return (keyword: option.keyword, label: option.label);
      }
    }
    switch (normalized) {
      case 'pizzeria':
      case 'pizzaci':
      case 'pizzacı':
        return (keyword: 'pizza', label: 'Pizza');
      case 'hamburger':
      case 'burgers':
        return (keyword: 'burger', label: 'Burger');
      case 'kahvalti':
      case 'kahvaltı':
      case 'brunch':
        return (keyword: 'breakfast', label: 'Breakfast');
      case 'tatli':
      case 'tatlı':
      case 'desserts':
        return (keyword: 'dessert', label: 'Dessert');
      case 'fish':
      case 'sea food':
      case 'balik':
      case 'balık':
        return (keyword: 'seafood', label: 'Seafood');
    }
    return null;
  }

  _CategoryAreaQuery? _categoryAreaQueryForSearch(String rawQuery) {
    final trimmed = rawQuery.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();
    for (final option in _categoryOptions) {
      final variants = _categoryQueryVariants(option.key);
      for (final variant in variants) {
        if (lower == variant) return null;
        if (lower.startsWith('$variant ')) {
          final areaQuery = trimmed.substring(variant.length).trim();
          if (areaQuery.length < 2) return null;
          return _CategoryAreaQuery(
            categoryKey: option.key,
            categoryLabel: option.label,
            areaQuery: areaQuery,
          );
        }
      }
    }
    return null;
  }

  List<String> _categoryQueryVariants(String key) {
    switch (key) {
      case 'restaurant':
        return const ['restaurant', 'restaurants'];
      case 'cafe':
        return const ['cafe', 'cafes', 'coffee', 'coffee shop', 'coffee shops'];
      case 'bar':
        return const ['bar', 'bars', 'pub', 'pubs'];
      case 'club':
        return const [
          'nightclub',
          'nightclubs',
          'night club',
          'night clubs',
          'club',
          'clubs',
        ];
      case 'lounge':
        return const ['lounge', 'lounges'];
    }
    return const [];
  }

  String get _advancedFilterSummary {
    final parts = <String>[];
    if (_openNowOnly) parts.add('Open now');
    if (_selectedRatings.isNotEmpty) {
      parts.add('${_selectedRatings.reduce(math.min).toStringAsFixed(1)}+');
    }
    if (_selectedPartnerships.isNotEmpty) {
      parts.add('${_selectedPartnerships.length} partnership');
    }
    return parts.isEmpty ? 'All nearby' : parts.join(' · ');
  }

  List<Venue> _filteredResultVenues() {
    final source = widget.listVenues.isNotEmpty
        ? widget.listVenues
        : widget.venues;
    final items = source.where(_passesUserFilters).toList()
      ..sort(
        (a, b) =>
            (a.distanceMeters ?? 999999).compareTo(b.distanceMeters ?? 999999),
      );
    return items;
  }

  Future<void> _openFilterSheet({
    required String title,
    required Widget Function(StateSetter setSheetState) contentBuilder,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Container(
              margin: EdgeInsets.fromLTRB(
                12,
                0,
                12,
                MediaQuery.of(ctx).padding.bottom + 12,
              ),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0D1623) : colors.surface,
                borderRadius: BorderRadius.circular(26),
                border: Border.all(
                  color: isDark
                      ? _kKmstryBlue.withValues(alpha: 0.14)
                      : colors.outline.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                    color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            _kKmstryBlue,
                            _kKmstryTeal.withValues(alpha: 0.95),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: colors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  contentBuilder(setSheetState),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openPartnershipSheet() {
    return _openFilterSheet(
      title: 'Deals and discounts',
      contentBuilder: (setSheetState) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final textColor = theme.colorScheme.onSurface;
        final maxHeight = MediaQuery.of(context).size.height * 0.56;
        final sheetHeight = maxHeight > 430 ? 430.0 : maxHeight;
        return SizedBox(
          height: sheetHeight,
          child: Column(
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select one or more partner benefits.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    fontWeight: FontWeight.w600,
                    color: textColor.withValues(alpha: isDark ? 0.66 : 0.58),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: _partnershipOptions.length,
                  separatorBuilder: (_, index) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final o = _partnershipOptions[index];
                    return _PartnershipOptionTile(
                      label: o.label,
                      selected: _selectedPartnerships.contains(o.key),
                      isDark: isDark,
                      onTap: () {
                        setSheetState(() {
                          if (_selectedPartnerships.contains(o.key)) {
                            _selectedPartnerships.remove(o.key);
                          } else {
                            _selectedPartnerships.add(o.key);
                          }
                        });
                        _onFiltersChanged();
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              _sheetDoneButton(),
            ],
          ),
        );
      },
    );
  }

  /// Partnership sheet ile aynı düzeni kullanan, çoklu seçimli filtre gövdesi.
  Widget _buildMultiSelectSheetBody<T>({
    required String subtitle,
    required List<({String label, T value})> options,
    required bool Function(T value) isSelected,
    required void Function(T value) onToggle,
    required void Function(VoidCallback) setSheetState,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.colorScheme.onSurface;
    final maxHeight = MediaQuery.of(context).size.height * 0.56;
    final desired = 120.0 + options.length * 62.0;
    final sheetHeight = math.min(maxHeight, math.min(desired, 430.0));
    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              subtitle,
              style: TextStyle(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: textColor.withValues(alpha: isDark ? 0.66 : 0.58),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: options.length,
              separatorBuilder: (_, index) => const SizedBox(height: 8),
              itemBuilder: (_, index) {
                final o = options[index];
                return _PartnershipOptionTile(
                  label: o.label,
                  selected: isSelected(o.value),
                  isDark: isDark,
                  onTap: () {
                    setSheetState(() => onToggle(o.value));
                    _onFiltersChanged();
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          _sheetDoneButton(),
        ],
      ),
    );
  }

  Widget _sheetDoneButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(context).pop(),
          child: Ink(
            width: 56,
            height: 46,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_kKmstryBlue, _kKmstryTeal],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                  color: _kKmstryBlue.withValues(alpha: 0.22),
                ),
              ],
            ),
            child: const Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openRatingSheet() {
    const options = <({String label, double value})>[
      (label: '3.0+', value: 3.0),
      (label: '3.5+', value: 3.5),
      (label: '4.0+', value: 4.0),
      (label: '4.5+', value: 4.5),
    ];
    return _openFilterSheet(
      title: 'Minimum rating',
      contentBuilder: (setSheetState) => _buildMultiSelectSheetBody<double>(
        subtitle: 'Select one or more rating tiers.',
        options: options,
        isSelected: _selectedRatings.contains,
        onToggle: (value) {
          if (_selectedRatings.contains(value)) {
            _selectedRatings.remove(value);
          } else {
            _selectedRatings.add(value);
          }
        },
        setSheetState: setSheetState,
      ),
    );
  }

  Future<void> _openDistanceSheet() {
    const options = <({String label, int value})>[
      (label: 'Within 1 km', value: 1000),
      (label: 'Within 5 km', value: 5000),
      (label: 'Within 10 km', value: 10000),
    ];
    return _openFilterSheet(
      title: 'Distance',
      contentBuilder: (setSheetState) => _buildMultiSelectSheetBody<int>(
        subtitle: 'Select one or more distance bands.',
        options: options,
        isSelected: _selectedDistances.contains,
        onToggle: (value) {
          if (_selectedDistances.contains(value)) {
            _selectedDistances.remove(value);
          } else {
            _selectedDistances.add(value);
          }
        },
        setSheetState: setSheetState,
      ),
    );
  }

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
    _loadActiveCheckin();
  }

  /// "You're checked in" turkuaz rozeti — marker popup ve hızlı check-in
  /// sheet'inde aynı görünüm için ortak.
  Widget _buildCheckedInBadge(bool isDark) {
    const color = Color(0xFF1FD9A8); // logo turkuazı (AppColors.teal)
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.check_circle_rounded, size: 13, color: color),
          const SizedBox(width: 4),
          Text(
            "You're checked in",
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white.withValues(alpha: 0.9) : color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadActiveCheckin() async {
    try {
      final ActiveCheckin? active = await _checkinRepository.getActiveCheckin();
      if (!mounted) return;
      setState(() => _activeCheckinVenueId = active?.venueId);
    } catch (_) {
      // Sessiz geç — rozet gösterilmez.
    }
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
    if (venuesChanged) {
      // Venue listesi güncellenince (ör. checkin sonrası) icon cache'i temizle
      // ki checkinCountActive değişen venue'lar yeni heat rengiyle yeniden çizilsin.
      _photoMarkerIconCache.clear();
      _photoMarkerIconLoadingKeys.clear();
      // Venue listesi yenilendiyse (ör. check-in sonrası) aktif check-in'i de
      // tazele ki rozet doğru mekanda görünsün.
      _loadActiveCheckin();
    }
    if (venuesChanged || selectionChanged) {
      _recomputeClusters(force: true);
    }
  }

  void _showHeatmapLegend(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Read the room. Before you walk in.',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'The ring around a venue tells you how many people are checked in right now.',
                style: TextStyle(fontSize: 13, color: Colors.grey[600]),
              ),
              const SizedBox(height: 16),
              _legendRow(
                const Color(0xFF2196F3),
                'Just getting started',
                'A few people checked in',
              ),
              const SizedBox(height: 12),
              _legendRow(
                const Color(0xFFFF9800),
                'It\'s picking up',
                'Getting busier',
              ),
              const SizedBox(height: 12),
              _legendRow(
                const Color(0xFF4C1D95),
                'It\'s a vibe',
                'Packed! People are here',
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _legendRow(Color color, String label, String sublabel) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 3.5),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Text(
              sublabel,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
      ],
    );
  }

  @override
  void dispose() {
    widget.onSearchActivityChanged?.call(false);
    _searchDebounce?.cancel();
    _photoIconRefreshDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _resultsSheetController.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  bool get _isSearchActive {
    if (_isFilterDisplayQuery) return false;
    return _searchFocusNode.hasFocus ||
        _searchLoading ||
        _showSearchResults ||
        _searchController.text.trim().isNotEmpty;
  }

  bool get _isFilterDisplayQuery {
    final query = _searchController.text.trim();
    if (query.isEmpty) return false;
    if (_busyNowOnly && query.toLowerCase() == 'busy now') return true;
    return _selectedCategories.isNotEmpty &&
        _categoryKeyForQuery(query) != null;
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
      final moved =
          prev == null ||
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
            // Pin üstünde Google'ın beyaz info window'u gösterilmez; detay için
            // alttan gelen premium popup (_showVenueMarkerPopup) kullanılır.
            infoWindow: InfoWindow.noText,
            icon: venueIcon,
            zIndexInt: isPressed ? 5 : (isSelected ? 4 : 1),
            // Popup anında açılsın: canlı istatistik tazelemesi popup içinde
            // arka planda yapılır (önceden burada bir tur, popup içinde bir tur
            // daha ağ çağrısı vardı → sheet geç açılıyordu).
            onTap: () => _showVenueMarkerPopup(venue),
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
      BitmapDescriptor.hueAzure,
    );
  }

  BitmapDescriptor _selectedSingleIcon() {
    return _singleSelectedIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueCyan,
    );
  }

  BitmapDescriptor _pressedSingleIcon() {
    return _singlePressedIcon ??= BitmapDescriptor.defaultMarkerWithHue(
      BitmapDescriptor.hueCyan,
    );
  }

  Color _heatRingColor(int? count) {
    if (count == null || count == 0) return Colors.transparent;
    if (count < 6) return _kKmstryBlue;
    if (count < 15) return _kKmstryTeal;
    return _kKmstryPink;
  }

  double _heatStrokeWidth(int? count) {
    if (count == null || count == 0) return 0;
    if (count < 6) return 2.5;
    if (count < 15) return 4.0;
    return 5.5;
  }

  BitmapDescriptor _singleVenueIcon({
    required Venue venue,
    required bool isSelected,
    required bool isPressed,
  }) {
    final photoUrl = venue.photoUrl.trim();
    // Fotosu olan her venue (DB veya Google farketmez) resimli pin gösterilir;
    // düz mavi pin yalnızca gerçekten hiç fotoğrafı olmayan venue'larda kalır.
    if (photoUrl.isEmpty) {
      return _fallbackSingleIcon(isSelected: isSelected, isPressed: isPressed);
    }

    final activeCount = (isPressed || isSelected)
        ? null
        : venue.checkinCountActive;

    final ringColor = (isPressed || isSelected)
        ? _kKmstryBlue
        : _heatRingColor(activeCount);
    final glowColor = _venueGlowColor(venue);
    final glowHex = glowColor.toARGB32().toRadixString(16);
    final cacheKey =
        '${_venueIdentity(venue)}|$photoUrl|$isSelected|$isPressed|$activeCount|$glowHex';
    final cached = _photoMarkerIconCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    _schedulePhotoMarkerIconBuild(
      cacheKey: cacheKey,
      photoUrl: photoUrl,
      ringColor: ringColor,
      glowColor: glowColor,
      activeCount: activeCount,
    );
    return _fallbackSingleIcon(isSelected: isSelected, isPressed: isPressed);
  }

  /// Venue'ye kimliğine göre STABİL rastgele bir logo rengi atar (türden
  /// bağımsız). Aynı venue her zaman aynı rengi alır → rebuild'de titremez;
  /// komşu mekanlar farklı renklerde olur → harita çok renkli ve canlı.
  Color _venueGlowColor(Venue venue) {
    final idx = _venueIdentity(venue).hashCode.abs() % _kGlowPalette.length;
    return _kGlowPalette[idx];
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
    required Color glowColor,
    int? activeCount,
  }) {
    if (_photoMarkerIconLoadingKeys.contains(cacheKey)) return;
    _photoMarkerIconLoadingKeys.add(cacheKey);
    _buildPhotoMarkerIcon(
          photoUrl: photoUrl,
          ringColor: ringColor,
          glowColor: glowColor,
          activeCount: activeCount,
        )
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

  /// Marker fotoğraflarının ham byte'larını diskte cache'leyerek getirir.
  /// `cached_network_image` ile aynı `flutter_cache_manager` altyapısını
  /// kullanır; aynı foto URL'i bir daha indirilmez.
  static final BaseCacheManager _markerPhotoCacheManager =
      DefaultCacheManager();

  Future<Uint8List?> _loadMarkerPhotoBytes(String photoUrl) async {
    try {
      final file = await _markerPhotoCacheManager.getSingleFile(photoUrl);
      if (!await file.exists()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor?> _buildPhotoMarkerIcon({
    required String photoUrl,
    required Color ringColor,
    required Color glowColor,
    int? activeCount,
  }) async {
    try {
      final uri = Uri.tryParse(photoUrl);
      if (uri == null) return null;
      // Ham fotoğrafı diskten oku; ilk görülüşte bir kez indirilir, sonraki
      // rebuild/uygulama açılışlarında ağdan tekrar çekilmez → Place Photo SKU
      // maliyeti ve veri/pil tüketimi düşer.
      final bytes = await _loadMarkerPhotoBytes(photoUrl);
      if (bytes == null || bytes.isEmpty) return null;
      // Yüksek çözünürlük (4x) → kenarlar ve glow keskin, "pixel pixel" görünüm
      // biter. Görüntü boyutu aynı (64pt) kalır, sadece daha çok piksel basılır.
      const scale = 4.0;
      // 72pt: glow'un yumuşak dış kenarına pay bırakır (64pt'te dış halo canvas
      // kenarında kırpılıp sert bir daire oluşturuyordu).
      const logicalSize = 72.0;
      const physicalSize = logicalSize * scale;

      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: (52 * scale).toInt(),
        targetHeight: (52 * scale).toInt(),
      );
      final frame = await codec.getNextFrame();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.scale(scale, scale);

      const center = Offset(logicalSize / 2, logicalSize / 2);
      const outerR = 25.0;
      const imageR = 22.5;

      // Zemin gölgesi (derinlik) — hafif.
      canvas.drawCircle(
        center.translate(0, 2),
        outerR,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.22)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5),
      );

      // Logo-renkli glow (halo): iki katman → mekanlar haritada belirgin parlar.
      // 1) Geniş, yumuşak dış halo (uzaktan fark edilsin).
      canvas.drawCircle(
        center,
        outerR + 3,
        Paint()
          ..color = glowColor.withValues(alpha: 0.42)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 10),
      );
      // 2) Sıkı iç glow (halkayı canlı renge boğar) — biraz yumuşatıldı.
      canvas.drawCircle(
        center,
        outerR + 1,
        Paint()
          ..color = glowColor.withValues(alpha: 0.72)
          ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
      );

      // Çerçeve zemini (koyu).
      canvas.drawCircle(
        center,
        outerR,
        Paint()..color = const Color(0xFF0F172A),
      );

      // Renkli parlak halka kenarı — glow'u nete bağlar, sınırı belirginleştirir.
      canvas.drawCircle(
        center,
        outerR - 0.75,
        Paint()
          ..color = glowColor.withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8,
      );

      // Fotoğraf.
      final clipPath = Path()
        ..addOval(Rect.fromCircle(center: center, radius: imageR));
      canvas.save();
      canvas.clipPath(clipPath);
      paintImage(
        canvas: canvas,
        rect: Rect.fromCircle(center: center, radius: imageR),
        image: frame.image,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.high,
      );
      canvas.restore();

      // İnce beyaz iç kenar — fotoğrafı çerçeveden ayırır, daha temiz durur.
      canvas.drawCircle(
        center,
        imageR,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      // Aktivite ring'i (heat) — check-in yoğunluğuna göre.
      if ((ringColor.a * 255.0).round() > 0) {
        canvas.drawCircle(
          center,
          outerR,
          Paint()
            ..color = ringColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = _heatStrokeWidth(activeCount),
        );
      }

      // Canlı check-in rozeti (sağ üst) — mekanda şu an kaç kişi var.
      if (activeCount != null && activeCount > 0) {
        final badgeCenter = center.translate(17, -17);
        const badgeR = 9.0;
        canvas.drawCircle(
          badgeCenter,
          badgeR + 1.6,
          Paint()..color = const Color(0xFF06091A),
        );
        canvas.drawCircle(badgeCenter, badgeR, Paint()..color = _kKmstryTeal);
        final label = activeCount > 99 ? '99+' : '$activeCount';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              color: Color(0xFF06121A),
              fontSize: 10,
              fontWeight: FontWeight.w800,
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, badgeCenter - Offset(tp.width / 2, tp.height / 2));
      }

      final image = await recorder.endRecording().toImage(
        physicalSize.toInt(),
        physicalSize.toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData?.buffer.asUint8List();
      if (pngBytes == null || pngBytes.isEmpty) return null;
      return BitmapDescriptor.bytes(pngBytes, imagePixelRatio: scale);
    } catch (_) {
      return null;
    }
  }

  Future<BitmapDescriptor> _clusterIcon({
    required int count,
    required bool highlighted,
  }) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = count > 999 ? '999+' : '$count';
    const sublabel = 'spots';
    final bucket = count >= 100 ? '100+' : (count >= 20 ? '20+' : '2+');
    final cacheKey = '${isDark ? 'dark' : 'light'}:$bucket:$text:$highlighted';

    final cached = _clusterIconCache[cacheKey];
    if (cached != null) return cached;

    final size = (44 + (math.log(count + 1) * 5)).clamp(44, 62).toInt();
    Color fill;
    Color stroke;

    if (!isDark) {
      fill = const Color(0xFFFCFBFF);
      if (highlighted || count <= 20) {
        stroke = _kKmstryBlue;
      } else if (count > 50) {
        stroke = _kKmstryPink;
      } else {
        stroke = const Color(0xFF8257E5);
      }
    } else if (highlighted) {
      fill = const Color(0xFF081120);
      stroke = _kKmstryBlue;
    } else if (count > 50) {
      fill = const Color(0xFF081120);
      stroke = _kKmstryPink;
    } else if (count > 20) {
      fill = const Color(0xFF081120);
      stroke = _kKmstryBlue;
    } else {
      fill = const Color(0xFF081120);
      stroke = _kKmstryTeal;
    }

    final icon = await _drawClusterBitmap(
      size: size,
      text: text,
      sublabel: sublabel,
      fill: fill,
      stroke: stroke,
      isDark: isDark,
    );

    _clusterIconCache[cacheKey] = icon;
    return icon;
  }

  Future<BitmapDescriptor> _drawClusterBitmap({
    required int size,
    required String text,
    required Color fill,
    required Color stroke,
    required bool isDark,
    String? sublabel,
  }) async {
    const scale = 3.0;
    final physicalSize = (size * scale).toInt();
    final logicalSize = size.toDouble();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.scale(scale, scale);

    final center = Offset(logicalSize / 2, logicalSize / 2);
    final pillRect = Rect.fromLTWH(
      2,
      logicalSize * 0.16,
      logicalSize - 4,
      logicalSize * 0.68,
    );
    final pill = RRect.fromRectAndRadius(
      pillRect,
      Radius.circular(logicalSize * 0.24),
    );

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: isDark ? 0.34 : 0.14)
      ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 4);
    canvas.drawRRect(pill.shift(const Offset(0, 2)), shadowPaint);

    final fillPaint = Paint()
      ..shader = ui.Gradient.linear(pillRect.topLeft, pillRect.bottomRight, [
        fill,
        isDark ? const Color(0xFF101A2B) : const Color(0xFFF0ECFA),
      ]);
    final strokePaint = Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawRRect(pill, fillPaint);
    if ((stroke.a * 255.0).round() > 0) {
      canvas.drawRRect(pill.deflate(1.1), strokePaint);
    }

    final mainTp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: isDark ? Colors.white : const Color(0xFF241C35),
          fontSize: logicalSize * 0.28,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (sublabel != null && sublabel.isNotEmpty) {
      final subTp = TextPainter(
        text: TextSpan(
          text: sublabel,
          style: TextStyle(
            color: isDark
                ? Colors.white.withValues(alpha: 0.75)
                : const Color(0xFF675E76),
            fontSize: logicalSize * 0.145,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final totalHeight = mainTp.height + subTp.height;
      final topY = center.dy - (totalHeight / 2) - 1;
      mainTp.paint(canvas, Offset((logicalSize - mainTp.width) / 2, topY));
      subTp.paint(
        canvas,
        Offset((logicalSize - subTp.width) / 2, topY + mainTp.height - 1),
      );
    } else {
      mainTp.paint(
        canvas,
        Offset(
          (logicalSize - mainTp.width) / 2,
          (logicalSize - mainTp.height) / 2,
        ),
      );
    }

    final image = await recorder.endRecording().toImage(
      physicalSize,
      physicalSize,
    );
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    final bytes = byteData?.buffer.asUint8List();
    if (bytes == null || bytes.isEmpty) {
      return _defaultSingleIcon();
    }
    return BitmapDescriptor.bytes(bytes, imagePixelRatio: scale);
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
        // Pin üstünde beyaz info window yok; detay alttan popup'ta gösterilir.
        infoWindow: InfoWindow.noText,
        onTap: () => _showVenueMarkerPopup(sv),
      ),
    );
  }

  List<Venue> _filterClusterInputVenues(List<Venue> venues) {
    if (venues.isEmpty) return const [];
    return venues
        .where((v) => _clusterInputFilters.every((f) => f(v)))
        .where(_passesUserFilters)
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
        _selectedCategories.clear();
        _selectedCuisineKeyword = null;
        _selectedCuisineLabel = null;
        _busyNowOnly = false;
        _searchLoading = false;
        _searchError = null;
        _searchResults = const [];
        _placeSuggestions = const [];
        _categoryAreaSuggestions = const [];
        _showSearchResults = _searchFocusNode.hasFocus;
        _selectedSearchVenue = null;
        _showResultsSheet = true;
      });
      widget.onBrowseKeywordChanged?.call(null);
      _notifySearchActivity();
      _recomputeClusters(force: true);
      return;
    }

    final categoryKey = _categoryKeyForQuery(query);
    if (categoryKey != null) {
      setState(() {
        _busyNowOnly = false;
        _selectedCuisineKeyword = null;
        _selectedCuisineLabel = null;
        _selectedCategories
          ..clear()
          ..add(categoryKey);
        _searchLoading = false;
        _searchError = null;
        _searchResults = const [];
        _placeSuggestions = const [];
        _categoryAreaSuggestions = const [];
        _showSearchResults = false;
        _selectedSearchVenue = null;
        _showResultsSheet = true;
      });
      widget.onBrowseKeywordChanged?.call(null);
      _notifySearchActivity();
      _recomputeClusters(force: true);
      return;
    }

    final cuisine = _cuisineForQuery(query);
    if (cuisine != null) {
      setState(() {
        _busyNowOnly = false;
        _selectedCategories.clear();
        _selectedCuisineKeyword = cuisine.keyword;
        _selectedCuisineLabel = cuisine.label;
        _searchLoading = false;
        _searchError = null;
        _searchResults = const [];
        _placeSuggestions = const [];
        _categoryAreaSuggestions = const [];
        _showSearchResults = false;
        _selectedSearchVenue = null;
        _showResultsSheet = true;
      });
      widget.onBrowseKeywordChanged?.call(cuisine.keyword);
      _notifySearchActivity();
      _recomputeClusters(force: true);
      return;
    }

    setState(() {
      _selectedCategories.clear();
      _selectedCuisineKeyword = null;
      _selectedCuisineLabel = null;
      _busyNowOnly = false;
      _showResultsSheet = false;
    });
    widget.onBrowseKeywordChanged?.call(null);

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
      final categoryAreaQuery = _categoryAreaQueryForSearch(query);
      final placeQuery = categoryAreaQuery?.areaQuery ?? query;
      final futures = await Future.wait([
        _venueRepository.searchVenues(
          query: query,
          latitude: location.latitude,
          longitude: location.longitude,
        ),
        _fetchPlaceSuggestions(query: placeQuery, location: location),
      ]);

      if (!mounted || token != _searchRequestToken) return;
      final venueResults = futures[0] as List<Venue>;
      final placeResults = futures[1] as List<_PlaceSuggestion>;

      setState(() {
        _searchResults = _enrichSearchResultsWithNearbyVenues(venueResults);
        _placeSuggestions = placeResults;
        _categoryAreaSuggestions = categoryAreaQuery == null
            ? const []
            : placeResults
                  .take(4)
                  .map(
                    (place) => _CategoryAreaSuggestion(
                      categoryKey: categoryAreaQuery.categoryKey,
                      categoryLabel: categoryAreaQuery.categoryLabel,
                      place: place,
                    ),
                  )
                  .toList();
        _searchLoading = false;
      });
      _notifySearchActivity();
    } catch (_) {
      if (!mounted || token != _searchRequestToken) return;
      setState(() {
        _searchResults = const [];
        _placeSuggestions = const [];
        _categoryAreaSuggestions = const [];
        _searchLoading = false;
        _searchError = 'Search failed. Please try again.';
      });
      _notifySearchActivity();
    }
  }

  static const _googleApiKey = 'AIzaSyAW_tmPFyMqvhpZn9Fieq2iUXxX3we-F70';

  Future<List<_PlaceSuggestion>> _fetchPlaceSuggestions({
    required String query,
    required LatLng location,
  }) async {
    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/autocomplete/json',
        {'input': query, 'language': 'tr', 'key': _googleApiKey},
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return const [];
      final data = json.decode(response.body) as Map<String, dynamic>;
      final predictions = data['predictions'] as List? ?? [];
      return predictions
          .take(4)
          .map((p) {
            final map = p as Map<String, dynamic>;
            return _PlaceSuggestion(
              placeId: map['place_id']?.toString() ?? '',
              mainText:
                  (map['structured_formatting']?['main_text'] ??
                          map['description'] ??
                          '')
                      .toString(),
              secondaryText:
                  (map['structured_formatting']?['secondary_text'] ?? '')
                      .toString(),
            );
          })
          .where((s) => s.placeId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _onPlaceSuggestionTap(_PlaceSuggestion suggestion) async {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    setState(() {
      _showSearchResults = false;
      _searchController.text = suggestion.mainText;
    });
    _notifySearchActivity();

    try {
      final uri = Uri.https(
        'maps.googleapis.com',
        '/maps/api/place/details/json',
        {
          'place_id': suggestion.placeId,
          'fields': 'geometry',
          'key': _googleApiKey,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final location = data['result']?['geometry']?['location'];
      if (location == null) return;
      final lat = (location['lat'] as num).toDouble();
      final lng = (location['lng'] as num).toDouble();
      final target = LatLng(lat, lng);

      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
      if (!mounted) return;
      widget.onLocationResolved?.call(target);
    } catch (_) {}
  }

  Future<void> _onCategoryAreaSuggestionTap(
    _CategoryAreaSuggestion suggestion,
  ) async {
    _searchDebounce?.cancel();
    _searchFocusNode.unfocus();
    final searchText =
        '${suggestion.categoryLabel} near ${suggestion.place.mainText}';
    setState(() {
      _busyNowOnly = false;
      _selectedCategories
        ..clear()
        ..add(suggestion.categoryKey);
      _showSearchResults = false;
      _searchError = null;
      _searchLoading = false;
      _searchResults = const [];
      _placeSuggestions = const [];
      _categoryAreaSuggestions = const [];
      _showResultsSheet = true;
      _searchController.text = searchText;
      _searchController.selection = TextSelection.collapsed(
        offset: searchText.length,
      );
    });
    _notifySearchActivity();
    _recomputeClusters(force: true);

    try {
      final uri =
          Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
            'place_id': suggestion.place.placeId,
            'fields': 'geometry',
            'key': _googleApiKey,
          });
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body) as Map<String, dynamic>;
      final location = data['result']?['geometry']?['location'];
      if (location == null) return;
      final target = LatLng(
        (location['lat'] as num).toDouble(),
        (location['lng'] as num).toDouble(),
      );
      await _mapController?.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(target: target, zoom: 15),
        ),
      );
      if (!mounted) return;
      widget.onLocationResolved?.call(target);
    } catch (_) {}
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
      ratingCount: venue.ratingCount,
      types: venue.types,
      description: venue.description,
      photos: venue.photos,
      openingHours: venue.openingHours,
      upcomingEvents: venue.upcomingEvents,
      partnershipPlatforms: venue.partnershipPlatforms,
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

  Future<void> _openVenueDetailFromMap(
    Venue venue, {
    bool reopenMarkerPopup = false,
  }) async {
    // Aramadan (search sonuç listesinden) açıldıysa Trending Now sinyalini besle.
    if (_showSearchResults && venue.id.isNotEmpty) {
      unawaited(_venueRepository.recordSearchHit(venue.id));
    }
    widget.onVenueTap?.call(venue);
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
    );
    if (!mounted) return;
    widget.onVenueDetailClosed?.call(venue);
    if (reopenMarkerPopup) {
      // Pin popup'ından detay açıldıysa geri dönünce aynı pin bağlamını koru.
      await _showVenueMarkerPopup(_latestVenueSnapshotFor(venue));
    }
  }

  Future<void> _showVenueMarkerPopup(Venue venue) async {
    if (!mounted) return;

    final key = _venueIdentity(venue);
    setState(() => _pressedMarkerVenueKey = key);
    unawaited(_recomputeClusters(force: true));

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final surface = isDark
        ? colors.surface.withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.97);
    final border = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);
    final subtitleColor = colors.onSurface.withValues(alpha: 0.72);

    // Canlı istatistikleri arka planda tazele — popup ANINDA açılır, veri
    // gelince (rating / check-in sayısı) sheet içi güncellenir.
    final refreshFuture = _refreshLiveStatsForVenue(venue);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) {
        var liveVenue = venue;
        var refreshHooked = false;
        return StatefulBuilder(
          builder: (statefulContext, setSheetState) {
            if (!refreshHooked) {
              refreshHooked = true;
              refreshFuture.then((fresh) {
                if (!statefulContext.mounted) return;
                setSheetState(() => liveVenue = fresh);
              });
            }
            final hasRating = liveVenue.rating != null && liveVenue.rating! > 0;
            final isActiveCheckin =
                _activeCheckinVenueId != null &&
                liveVenue.id == _activeCheckinVenueId;
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  0,
                  0,
                  0,
                  MediaQuery.of(sheetContext).padding.bottom,
                ),
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(sheetContext).size.height * 0.48,
                  ),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(26),
                    ),
                    border: Border(top: BorderSide(color: border)),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 28,
                        offset: const Offset(0, -10),
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.52)
                            : Colors.black.withValues(alpha: 0.12),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: border),
                                color: colors.surface.withValues(alpha: 0.8),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(17),
                                child: liveVenue.photoUrl.isNotEmpty
                                    ? CachedImage(
                                        liveVenue.photoUrl,
                                        fit: BoxFit.cover,
                                        errorWidget: (_) => Icon(
                                          Icons.storefront_rounded,
                                          color: colors.onSurface.withValues(
                                            alpha: 0.74,
                                          ),
                                        ),
                                      )
                                    : Icon(
                                        Icons.storefront_rounded,
                                        color: colors.onSurface.withValues(
                                          alpha: 0.74,
                                        ),
                                      ),
                              ),
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
                                  if (isActiveCheckin) ...[
                                    const SizedBox(height: 6),
                                    _buildCheckedInBadge(isDark),
                                  ],
                                  if (liveVenue.address.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      liveVenue.address,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: subtitleColor),
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
                        PrimaryButton(
                          label: 'View venue',
                          trailingArrow: true,
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _openVenueDetailFromMap(
                              liveVenue,
                              reopenMarkerPopup: true,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
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
        ? const Color(0xFF0D1726).withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.96);
    final textColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark
        ? Colors.white.withValues(alpha: 0.76)
        : Colors.grey.shade600;
    final iconColor = isDark ? _kKmstryBlue : _kKmstryBlue;
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? _kKmstryBlue.withValues(alpha: 0.34)
              : _kKmstryBlue.withValues(alpha: 0.20),
        ),
        boxShadow: [
          BoxShadow(
            blurRadius: 18,
            offset: const Offset(0, 8),
            color: isDark
                ? _kKmstryBlue.withValues(alpha: 0.18)
                : _kKmstryBlue.withValues(alpha: 0.10),
          ),
          BoxShadow(
            blurRadius: 12,
            offset: const Offset(0, 4),
            color: Colors.black.withValues(alpha: isDark ? 0.36 : 0.08),
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
              onTap: _clearSearchAndFilters,
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
          style: TextStyle(color: colors.error, fontWeight: FontWeight.w600),
        ),
      );
    }
    if (_searchResults.isEmpty &&
        _placeSuggestions.isEmpty &&
        _categoryAreaSuggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No results found.',
          style: TextStyle(color: colors.onSurface.withValues(alpha: 0.72)),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      shrinkWrap: true,
      children: [
        if (_categoryAreaSuggestions.isNotEmpty) ...[
          ..._categoryAreaSuggestions.map(
            (suggestion) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _onCategoryAreaSuggestionTap(suggestion),
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
                          color: const Color(
                            0xFF1A9FE8,
                          ).withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          _categoryIconForKey(suggestion.categoryKey),
                          size: 18,
                          color: const Color(0xFF1A9FE8),
                        ),
                      ),
                      title: Text(
                        suggestion.categoryLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        'near ${suggestion.place.mainText}${suggestion.place.secondaryText.isNotEmpty ? ' · ${suggestion.place.secondaryText}' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                        ),
                      ),
                      trailing: Icon(
                        Icons.north_west_rounded,
                        size: 18,
                        color: colors.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_placeSuggestions.isNotEmpty || _searchResults.isNotEmpty)
            const SizedBox(height: 4),
        ],
        // ── Areas / Places ──────────────────────────────────────
        if (_placeSuggestions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            child: Text(
              'AREAS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ),
          ..._placeSuggestions.map(
            (place) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => _onPlaceSuggestionTap(place),
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
                          color: colors.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.location_on_outlined,
                          size: 18,
                          color: colors.primary,
                        ),
                      ),
                      title: Text(
                        place.mainText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colors.onSurface,
                        ),
                      ),
                      subtitle: place.secondaryText.isNotEmpty
                          ? Text(
                              place.secondaryText,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.55),
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: Icon(
                        Icons.arrow_outward,
                        size: 16,
                        color: colors.onSurface.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (_searchResults.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: Text(
                'VENUES',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: colors.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
        ],
        // ── Venues ──────────────────────────────────────────────
        ...List.generate(_searchResults.length, (index) {
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
                        child: CachedImage(
                          'https://www.gstatic.com/images/branding/product/1x/maps_32dp.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.contain,
                          errorWidget: (context) => Icon(
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
        }),
      ],
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

  Widget _buildResultsSheet() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final venues = _filteredResultVenues();

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final expanded = notification.extent > 0.62;
        if (expanded != _resultsSheetExpanded) {
          setState(() => _resultsSheetExpanded = expanded);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        controller: _resultsSheetController,
        initialChildSize: _resultsSheetInitialSize,
        minChildSize: _resultsSheetMinSize,
        maxChildSize: _resultsSheetMaxSize,
        builder: (context, controller) {
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF0D1623) : Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(_resultsSheetExpanded ? 0 : 26),
              ),
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? _kKmstryBlue.withValues(alpha: 0.24)
                      : _kKmstryBlue.withValues(alpha: 0.12),
                ),
              ),
              boxShadow: [
                BoxShadow(
                  blurRadius: 28,
                  offset: const Offset(0, -10),
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.55)
                      : Colors.black.withValues(alpha: 0.12),
                ),
              ],
            ),
            child: Column(
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (details) {
                    if (!_resultsSheetController.isAttached) return;
                    final height = MediaQuery.of(context).size.height;
                    final nextSize =
                        (_resultsSheetController.size -
                                (details.primaryDelta ?? 0) / height)
                            .clamp(_resultsSheetMinSize, _resultsSheetMaxSize);
                    _resultsSheetController.jumpTo(nextSize);
                  },
                  child: Column(
                    children: [
                      const SizedBox(height: 8),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _kKmstryBlue.withValues(alpha: 0.88),
                              _kKmstryTeal.withValues(alpha: 0.88),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              blurRadius: 12,
                              color: _kKmstryTeal.withValues(alpha: 0.28),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 12, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _resultsTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w800,
                                      color: colors.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    widget.loadingVenues && venues.isEmpty
                                        ? 'Loading venues...'
                                        : _advancedFilterSummary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: colors.onSurface.withValues(
                                        alpha: isDark ? 0.68 : 0.62,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (_hasBrowseContext)
                              IconButton(
                                tooltip: 'Clear',
                                onPressed: _closeResultsSheet,
                                icon: const Icon(Icons.close_rounded),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _buildResultsAdvancedFilters(),
                const SizedBox(height: 8),
                Expanded(
                  child: widget.loadingVenues && venues.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : venues.isEmpty
                      ? _buildNoVenueResults()
                      : NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            final metrics = notification.metrics;
                            if (metrics.maxScrollExtent > 0 &&
                                metrics.pixels >=
                                    metrics.maxScrollExtent - 420) {
                              widget.onLoadMoreVenues?.call();
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: controller,
                            padding: EdgeInsets.only(
                              bottom:
                                  MediaQuery.of(context).padding.bottom + 20,
                            ),
                            itemCount: venues.length + 1,
                            itemBuilder: (context, index) {
                              if (index == venues.length) {
                                return _buildResultsFooter();
                              }
                              final venue = venues[index];
                              return VenueListItem(
                                venue: venue,
                                isSelected: _matchesSelectedVenue(venue),
                                isActiveCheckin:
                                    _activeCheckinVenueId != null &&
                                    venue.id == _activeCheckinVenueId,
                                onTap: (v) => _openVenueDetailFromMap(v),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildResultsAdvancedFilters() {
    return SizedBox(
      height: 38,
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          if (_hasActiveFilters)
            _ResultFilterChip(
              icon: Icons.close_rounded,
              label: 'Clear',
              selected: false,
              onTap: _clearSearchAndFilters,
            ),
          _ResultFilterChip(
            icon: Icons.schedule_rounded,
            label: 'Open now',
            selected: _openNowOnly,
            onTap: () {
              setState(() => _openNowOnly = !_openNowOnly);
              _onFiltersChanged();
            },
          ),
          _ResultFilterChip(
            icon: Icons.star_rounded,
            label: _selectedRatings.isEmpty
                ? 'Top rated'
                : (_selectedRatings.length == 1
                      ? '${_selectedRatings.first.toStringAsFixed(1)}+ rated'
                      : '${_selectedRatings.length} selected'),
            selected: _selectedRatings.isNotEmpty,
            onTap: _openRatingSheet,
          ),
          _ResultFilterChip(
            icon: Icons.handshake_outlined,
            label: _selectedPartnerships.isEmpty
                ? 'Deals and discounts'
                : '${_selectedPartnerships.length} selected',
            selected: _selectedPartnerships.isNotEmpty,
            onTap: _openPartnershipSheet,
          ),
          _ResultFilterChip(
            icon: Icons.near_me_rounded,
            label: _selectedDistances.isEmpty
                ? 'Distance'
                : (_selectedDistances.length == 1
                      ? '${(_selectedDistances.first / 1000).toStringAsFixed(0)} km'
                      : '${_selectedDistances.length} selected'),
            selected: _selectedDistances.isNotEmpty,
            onTap: _openDistanceSheet,
          ),
        ],
      ),
    );
  }

  Widget _buildResultsFooter() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (widget.loadingMoreVenues) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: colors.primary,
            ),
          ),
        ),
      );
    }
    if (!widget.hasMoreVenues) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            'No more venues',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.42),
            ),
          ),
        ),
      );
    }
    return const SizedBox(height: 18);
  }

  Widget _buildNoVenueResults() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.travel_explore_rounded,
              size: 42,
              color: colors.onSurface.withValues(alpha: 0.32),
            ),
            const SizedBox(height: 12),
            Text(
              'No venues found',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Try widening your filters.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: colors.onSurface.withValues(alpha: 0.58),
              ),
            ),
          ],
        ),
      ),
    );
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
          style: Theme.of(context).brightness == Brightness.dark
              ? kKmstryMapStyleDark
              : kKmstryMapStyleLight,
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
          onTap: (_) => _collapseResultsSheet(),
          onCameraIdle: _recomputeClusters,
          markers: _markers,
        ),

        /// 🔍 SEARCH BAR — arama aktifken de görünür kalmalı (aksi halde
        /// odaklanınca kendini gizler ve sadece harita/pinler kalırdı).
        if (!widget.hideSearch)
          Positioned(
            top: 14,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [Expanded(child: _buildSearchBar())]),
                const SizedBox(height: 8),
                _buildSearchResultsPanel(),
              ],
            ),
          ),

        if (!widget.hideSearch && !_showSearchResults)
          Positioned(top: 68, left: 0, right: 0, child: _buildFilterChipsRow()),

        // Search suggestions own this area while the field is active. Keeping
        // the floating map controls visible here would place them above the
        // suggestion panel because they are painted later in the Stack.
        if (!widget.hideSearch &&
            !_showSearchResults &&
            !_searchFocusNode.hasFocus)
          Positioned(
            right: 16,
            top: 110,
            child: Row(
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
                    widget.onLocationResolved?.call(_currentLocation!);
                  },
                ),
                if (_showHeatmapInfoButton) ...[
                  const SizedBox(width: 8),
                  _CircleIcon(
                    Icons.info_outline,
                    onTap: () => _showHeatmapLegend(context),
                  ),
                ],
              ],
            ),
          ),

        if (_showResultsSheet && !_showSearchResults && !_searchLoading)
          _buildResultsSheet(),
      ],
    );
  }
}

/// 🏷️ Harita filtre chip'i (Google Maps'teki "Open now / Price" satırı gibi).
class _FilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color? accent;
  final VoidCallback onTap;

  const _FilterChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = accent ?? _kKmstryBlue;
    // Light mode'da harita açık renk → beyaz chip / koyu metin; seçili = logo
    // mavisi. Dark mode: eski koyu pill görünümü korunur.
    final bg = selected
        ? (isDark
              ? const Color(0xFF0A1422).withValues(alpha: 0.94)
              : accentColor)
        : (isDark
              ? const Color(0xFF0E1825).withValues(alpha: 0.90)
              : Colors.white);
    final fg = selected
        ? Colors.white
        : (isDark
              ? Colors.white.withValues(alpha: 0.92)
              : const Color(0xFF1F2937));
    // Seçili pill ikonunun rengi: dark'ta accent, light'ta (mavi zemin) beyaz.
    final selectedAccent = isDark ? accentColor : Colors.white;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(17),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            height: 34,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(17),
              border: Border.all(
                color: selected
                    ? accentColor.withValues(alpha: 0.84)
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.14)
                          : Colors.black.withValues(alpha: 0.16)),
              ),
              boxShadow: [
                // Light mode'da seçili olmayan chip'e ağır siyah gölge yerine
                // haritadan ayrışsın diye hafif, yumuşak bir gölge veriyoruz.
                if (selected)
                  BoxShadow(
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                    color: accentColor.withValues(alpha: 0.28),
                  )
                else
                  BoxShadow(
                    blurRadius: isDark ? 10 : 6,
                    offset: const Offset(0, 2),
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.06),
                  ),
                if (selected)
                  BoxShadow(
                    blurRadius: 2,
                    color: _kKmstryTeal.withValues(alpha: 0.20),
                  ),
              ],
            ),
            foregroundDecoration: selected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.08),
                        Colors.transparent,
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  )
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: selected ? 18 : 0,
                  height: selected ? 18 : 0,
                  margin: EdgeInsets.only(right: selected ? 5 : 0),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selectedAccent.withValues(alpha: 0.18),
                  ),
                  child: selected
                      ? Icon(icon, size: 13, color: selectedAccent)
                      : null,
                ),
                if (!selected) ...[
                  Icon(icon, size: 15, color: fg),
                  const SizedBox(width: 5),
                ],
                Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultFilterChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ResultFilterChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = _kKmstryBlue;
    final bg = selected
        ? (isDark ? const Color(0xFF0A1422).withValues(alpha: 0.92) : accent)
        : (isDark
              ? Colors.white.withValues(alpha: 0.07)
              : const Color(0xFFF4F7FB));
    final border = selected
        ? accent.withValues(alpha: 0.72)
        : (isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06));
    final fg = selected
        ? Colors.white
        : theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.84 : 0.78);

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(19),
          onTap: onTap,
          child: Ink(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(19),
              border: Border.all(color: border),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        blurRadius: 14,
                        offset: const Offset(0, 5),
                        color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 16, color: fg),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
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
      width: 38,
      height: 38,
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
        padding: EdgeInsets.zero,
        iconSize: 20,
        onPressed: onTap,
        icon: Icon(icon, color: isDark ? Colors.white : Colors.black87),
      ),
    );
  }
}

class _PlaceSuggestion {
  final String placeId;
  final String mainText;
  final String secondaryText;

  const _PlaceSuggestion({
    required this.placeId,
    required this.mainText,
    required this.secondaryText,
  });
}

class _CategoryAreaQuery {
  final String categoryKey;
  final String categoryLabel;
  final String areaQuery;

  const _CategoryAreaQuery({
    required this.categoryKey,
    required this.categoryLabel,
    required this.areaQuery,
  });
}

class _PartnershipOptionTile extends StatelessWidget {
  const _PartnershipOptionTile({
    required this.label,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? _kKmstryBlue.withValues(alpha: isDark ? 0.16 : 0.10)
                : isDark
                ? const Color(0xFF111C2B)
                : const Color(0xFFF7FAFD),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected
                  ? _kKmstryBlue.withValues(alpha: 0.62)
                  : textColor.withValues(alpha: isDark ? 0.08 : 0.10),
              width: selected ? 1.2 : 1,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                      color: _kKmstryBlue.withValues(alpha: 0.16),
                    ),
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: selected
                      ? const LinearGradient(
                          colors: [_kKmstryBlue, _kKmstryTeal],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: selected ? null : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? Colors.transparent
                        : textColor.withValues(alpha: isDark ? 0.42 : 0.28),
                    width: 1.6,
                  ),
                ),
                child: selected
                    ? const Icon(
                        Icons.check_rounded,
                        color: Colors.white,
                        size: 17,
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected
                        ? textColor
                        : textColor.withValues(alpha: isDark ? 0.78 : 0.72),
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.done_rounded, color: _kKmstryTeal, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryAreaSuggestion {
  final String categoryKey;
  final String categoryLabel;
  final _PlaceSuggestion place;

  const _CategoryAreaSuggestion({
    required this.categoryKey,
    required this.categoryLabel,
    required this.place,
  });
}
