import 'dart:io';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_tray.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_model.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_repository.dart';
import 'package:kmstry_frontend/features/venue_stories/data/venue_story_viewed_cache.dart';

// VenueUpcomingEvent, venue_model.dart'tan geliyor — ayrı import gerekmez

class VenueDetailPage extends StatefulWidget {
  final Venue venue;

  const VenueDetailPage({super.key, required this.venue});

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  final _repo = VenueCheckinRepository();
  final _checkinRepo = CheckinRepository();
  final _venueContextRepo = VenueContextRepository();
  final _storyRepo = StoryRepository();
  final _venueStoryRepo = VenueStoryRepository();
  int _storyTrayRefreshCount = 0;
  bool _storyUploading = false;
  List<VenueStoryItem> _headerStories = [];
  String? _activeCheckinId;
  String? _activeCheckinVenueId;
  String? _activeCheckinVenuePlaceId;
  bool _checkingOut = false;
  String? _resolvedVenueIdForCurrentDetail;
  bool _loadingActiveCheckin = true;
  bool _resolvingVenueForCheckin = false;
  Map<String, dynamic>? _venueDetails;
  Map<String, dynamic>? _enrichedVenueData;
  bool _loadingDetails = true;
  bool _loadingCheckinStats = false;
  int? _checkinCountActive;
  int? _checkinCountMale;
  int? _checkinCountFemale;

  @override
  void initState() {
    super.initState();
    _checkinCountActive = widget.venue.checkinCountActive;
    _checkinCountMale = widget.venue.checkinCountMale;
    _checkinCountFemale = widget.venue.checkinCountFemale;
    _loadActiveCheckin();
    _loadVenueDetails();
    _loadEnrichedVenueData();
    _refreshCheckinStats();
    _loadHeaderStories();
  }

  Future<void> _loadHeaderStories() async {
    try {
      final stories = await _venueStoryRepo.getVenueStories(widget.venue.id);
      if (!mounted) return;
      setState(() {
        _headerStories = stories;
      });
    } catch (_) {}
  }

  void _openStoryViewer() {
    if (_headerStories.isEmpty) return;
    final venueId = widget.venue.id;
    final startIndex = _headerStories.indexWhere((s) => !s.viewedByMe);
    final initialIndex = startIndex == -1 ? 0 : startIndex;
    final group = StoryGroup(
      user: StoryUser(
        id: 'venue_$venueId',
        fullName: widget.venue.name,
        photo: widget.venue.photoUrl.isNotEmpty ? widget.venue.photoUrl : null,
      ),
      stories: _headerStories.map((s) => StoryItem(
        id: s.id,
        mediaUrl: s.mediaUrl,
        mediaType: s.mediaType,
        thumbnailUrl: s.thumbnailUrl,
        durationSecs: s.durationSecs,
        expiresAt: s.expiresAt,
        createdAt: s.createdAt,
        viewCount: s.viewCount,
      )).toList(),
    );
    Navigator.push<StoryViewerResult>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [group],
          venueId: venueId,
          initialStoryIndex: initialIndex,
          onClose: (lastIndex, allFinished) {
            final justViewed = allFinished
                ? _headerStories.map((s) => s.id).toSet()
                : { for (int i = 0; i <= lastIndex && i < _headerStories.length; i++) _headerStories[i].id };
            final cache = VenueStoryViewedCache.instance;
            justViewed.forEach(cache.mark);
            if (!mounted) return;
            setState(() {
              _headerStories = [
                for (final s in _headerStories)
                  (s.viewedByMe || justViewed.contains(s.id)) ? s.copyWith(viewedByMe: true) : s,
              ];
            });
          },
        ),
      ),
    );
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

  Future<void> _loadEnrichedVenueData() async {
    if (!widget.venue.isInDb || widget.venue.id.isEmpty) return;
    try {
      final data = await _venueContextRepo.getVenueById(widget.venue.id);
      if (!mounted) return;
      setState(() => _enrichedVenueData = data);
    } catch (e) {
      debugPrint('⚠️ Could not load enriched venue data: $e');
    }
  }

  Future<void> _loadVenueDetails() async {
    try {
      final placeId = widget.venue.placeId;

      if (placeId == null || placeId.isEmpty) {
        setState(() => _loadingDetails = false);
        return;
      }

      final data = await _venueContextRepo.getVenueDetails(placeId);

      if (!mounted) return;

      setState(() {
        _venueDetails = data;
        _loadingDetails = false;
      });
    } catch (e) {
      debugPrint('❌ Error loading venue details: $e');
      if (!mounted) return;
      setState(() => _loadingDetails = false);
    }
  }

  Future<void> _loadActiveCheckin() async {
    try {
      final activeCheckin = await _repo.getActiveCheckin();
      final activeVenueId = activeCheckin?.venueId;

      if (!mounted) return;

      if (activeVenueId == null || activeVenueId.isEmpty) {
        setState(() {
          _activeCheckinId = null;
          _activeCheckinVenueId = null;
          _activeCheckinVenuePlaceId = null;
          _loadingActiveCheckin = false;
        });
        return;
      }

      setState(() {
        _activeCheckinId = activeCheckin?.id;
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
          final resolvedResponse = await _venueContextRepo
              .resolveVenueFromPlace(placeKey);
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
        final placeId =
            (venueData['placeId'] ??
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
        _activeCheckinId = null;
        _activeCheckinVenueId = null;
        _loadingActiveCheckin = false;
      });
    }
  }

  String? _extractVenueIdFromResponse(Map<String, dynamic> response) {
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
    final resolvedResponse = await _venueContextRepo.resolveVenueFromPlace(
      placeId,
    );
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
          builder: (_) => CheckInPage(
            venueId: resolvedVenueId,
            venueLatitude: widget.venue.latitude,
            venueLongitude: widget.venue.longitude,
          ),
        ),
      );

      // Check-in tamamlandıysa → who's here sayfasına direkt geç.
      if (mounted && ActiveCheckinService().isCheckedInAt(resolvedVenueId)) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => VenuePeoplePage(
              venue: widget.venue,
              listVenueId: resolvedVenueId,
            ),
          ),
        );
      }

      _loadActiveCheckin();
      await _refreshCheckinStats(forcedVenueId: resolvedVenueId);
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) return;
        _refreshCheckinStats(forcedVenueId: resolvedVenueId);
      });
    } catch (e) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not prepare venue for check-in',
      );
      debugPrint('❌ Check-in venue resolve error: $e');
    } finally {
      if (mounted) {
        setState(() => _resolvingVenueForCheckin = false);
      }
    }
  }

  Future<void> _openAddStory() async {
    final checkinId = _activeCheckinId;
    if (checkinId == null) return;

    final file = await Navigator.push<File>(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraScreen(useFrontCamera: true),
      ),
    );

    if (file == null || !mounted) return;

    // Determine media type from extension.
    final filePath = file.path;
    final isVideo = filePath.endsWith('.mp4') ||
        filePath.endsWith('.mov') ||
        filePath.endsWith('.avi');
    final mediaType = isVideo ? 'video' : 'photo';

    // Overlay'i async gap'ten ÖNCE yakala — kullanıcı başka sayfaya geçse bile
    // kart root overlay üzerinde gösterilecek.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);

    setState(() => _storyUploading = true);

    try {
      await _storyRepo.createStory(
        checkinId: checkinId,
        file: file,
        mediaType: mediaType,
      );
      // Sayfa hâlâ açıksa tray'i yenile.
      if (mounted) {
        setState(() {
          _storyUploading = false;
          _storyTrayRefreshCount++;
        });
      }
      // Kutlama kartını göster — kullanıcı nerede olursa olsun.
      if (overlay != null) {
        showStorySharedCard(
          overlay,
          mediaFile: file,
          venueName: widget.venue.name,
          isVideo: isVideo,
        );
      }
    } catch (e, st) {
      debugPrint('❌ Story upload error: $e\n$st');
      if (!mounted) return;
      setState(() => _storyUploading = false);
      await showPremiumErrorDialog(context,
          message: 'Upload failed: $e');
    }
  }

  Future<void> _checkout() async {
    final checkinId = _activeCheckinId;
    if (checkinId == null) return;

    setState(() => _checkingOut = true);
    try {
      await _checkinRepo.checkout(checkinId);
      ActiveCheckinService().clear();
      if (!mounted) return;
      setState(() {
        _activeCheckinId = null;
        _activeCheckinVenueId = null;
        _activeCheckinVenuePlaceId = null;
        _checkingOut = false;
      });
      await _refreshCheckinStats();
    } catch (e) {
      debugPrint('❌ Checkout error: $e');
      if (!mounted) return;
      setState(() => _checkingOut = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check out. Please try again.')),
      );
    }
  }

  Future<void> _refreshCheckinStats({String? forcedVenueId}) async {
    if (_loadingCheckinStats) return;
    setState(() => _loadingCheckinStats = true);
    try {
      String? venueId = forcedVenueId;
      if (venueId == null || venueId.isEmpty) {
        try {
          venueId = await _resolveVenueIdForCheckin();
        } catch (_) {
          venueId = null;
        }
      }
      if (venueId == null || venueId.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingCheckinStats = false);
        return;
      }
      final VenueCheckinStats stats = await _venueContextRepo
          .getVenueCheckinStats(venueId);

      if (!mounted) return;
      setState(() {
        _resolvedVenueIdForCurrentDetail ??= venueId;
        _checkinCountActive = stats.checkinCountActive;
        _checkinCountMale = stats.male;
        _checkinCountFemale = stats.female;
        _loadingCheckinStats = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingCheckinStats = false);
    }
  }

  int? get _displayCheckinTotal {
    if (_checkinCountActive != null) return _checkinCountActive;
    if (_checkinCountMale != null && _checkinCountFemale != null) {
      return _checkinCountMale! + _checkinCountFemale!;
    }
    return null;
  }

  Widget _buildDescriptionSection(String description) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'About',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          description,
          style: TextStyle(
            fontSize: 14,
            height: 1.5,
            color: colors.onSurface.withValues(alpha: 0.75),
          ),
        ),
      ],
    );
  }

  Widget _buildUpcomingEventsSection(List<VenueUpcomingEvent> events) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Upcoming Events',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        ...events.map(
          (event) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? colors.surface
                  : colors.primary.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colors.outline.withValues(alpha: 0.18),
              ),
            ),
            child: Row(
              children: [
                Builder(builder: (_) {
                  final imgUrl = event.photos.isNotEmpty
                      ? event.photos.first
                      : event.photo;
                  return imgUrl != null && imgUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            imgUrl,
                            width: 48,
                            height: 48,
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => _eventIconPlaceholder(colors),
                          ),
                        )
                      : _eventIconPlaceholder(colors);
                }),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        event.formattedDate,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ),
                if (event.priceAed != null)
                  Text(
                    '${event.priceAed} AED',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                    ),
                  )
                else
                  Text(
                    'Free',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green.shade600,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _eventIconPlaceholder(ColorScheme colors) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.event_outlined, color: colors.primary, size: 22),
    );
  }

  Widget _buildCheckinStatsSection() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final total = _displayCheckinTotal;
    final male = _checkinCountMale;
    final female = _checkinCountFemale;
    final hasAnyData = total != null || male != null || female != null;
    final cardColor = isDark
        ? colors.surface.withValues(alpha: 0.82)
        : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.14)
        : Colors.black.withValues(alpha: 0.08);

    Widget statTile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isDark
              ? colors.surface.withValues(alpha: 0.96)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: colors.onSurface.withValues(alpha: 0.8)),
            const SizedBox(width: 8),
            Text(
              '$label: $value',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colors.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            blurRadius: 14,
            offset: const Offset(0, 6),
            color: isDark
                ? Colors.black.withValues(alpha: 0.28)
                : Colors.black.withValues(alpha: 0.06),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
        
          if (!hasAnyData && _loadingCheckinStats)
            const SizedBox(
              height: 18,
              width: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else if (!hasAnyData)
            Text(
              'Be the first to check in.',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.onSurface.withValues(alpha: 0.72),
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                statTile(
                  icon: Icons.people_outline_rounded,
                  label: 'Total',
                  value: '${total ?? 0}',
                ),
                statTile(
                  icon: Icons.man_rounded,
                  label: 'Men',
                  value: '${male ?? 0}',
                ),
                statTile(
                  icon: Icons.woman_rounded,
                  label: 'Women',
                  value: '${female ?? 0}',
                ),
              ],
            ),
        ],
      ),
    );
  }

  bool _hasValidLatLng(Venue v) {
    if (!v.latitude.isFinite || !v.longitude.isFinite) return false;
    if (v.latitude == 0 && v.longitude == 0) return false;
    return true;
  }

  bool get _canOpenDirections {
    final v = widget.venue;
    final pid = v.placeId?.trim();
    if (pid != null && pid.isNotEmpty) return true;
    if (_hasValidLatLng(v)) return true;
    return '${v.address} ${v.city}'.trim().isNotEmpty;
  }

  Future<void> _openDirections() async {
    final v = widget.venue;
    final hasLatLng = _hasValidLatLng(v);
    final placeId = v.placeId?.trim();
    final labelQuery =
        '${v.name} ${v.address} ${v.city}'.replaceAll(RegExp(r'\s+'), ' ').trim();
    final latLng = hasLatLng ? '${v.latitude},${v.longitude}' : '';
    final destinationForUrl = labelQuery.isNotEmpty ? labelQuery : latLng;
    final destinationForApp = labelQuery.isNotEmpty ? labelQuery : latLng;

    if (destinationForUrl.isEmpty) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'No location available for directions',
      );
      return;
    }

    // Google Maps universal URL: opens directions preview (ETA + Start button).
    final browserParams = <String, String>{
      'api': '1',
      'destination': destinationForUrl,
      'travelmode': 'driving',
    };
    if (placeId != null && placeId.isNotEmpty) {
      browserParams['destination_place_id'] = placeId;
    }
    final browserUri = Uri.https('www.google.com', '/maps/dir/', browserParams);

    // Platform-preferred deep links to open maps app directly when available.
    final List<Uri> launchOrder = [];
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Google Maps app scheme (iOS) in route-preview mode (not auto-start).
      final iosDaddr = placeId != null && placeId.isNotEmpty
          ? 'place_id:$placeId'
          : destinationForApp;
      launchOrder.add(
        Uri(
          scheme: 'comgooglemaps',
          queryParameters: {
            'daddr': iosDaddr,
            'directionsmode': 'driving',
            'views': 'traffic',
          },
        ),
      );
    }
    // Cross-platform fallback that keeps route preview visible.
    launchOrder.add(browserUri);

    for (final uri in launchOrder) {
      try {
        if (!await canLaunchUrl(uri)) continue;
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return;
      } catch (_) {
        // Try next fallback uri.
      }
    }

    if (!mounted) return;
    await showPremiumErrorDialog(context, message: 'Could not open maps');
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
    final opening = _venueDetails?['openingHours'];
    final isOpen = opening?['open_now'] == true;
    final weekdayText = opening?['weekday_text'];
    return Scaffold(
      body: Stack(
        children: [
          // ── Scrollable content ──────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Space reserved for the floating back button
                  const SizedBox(height: 52),

              /// HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _VenueDetailAvatarRing(
                    photoUrl: widget.venue.photoUrl,
                    hasStories: _headerStories.isNotEmpty,
                    allSeen: _headerStories.isNotEmpty && _headerStories.every((s) => s.viewedByMe),
                    onTap: _headerStories.isNotEmpty ? _openStoryViewer : null,
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

              const SizedBox(height: 8),

              /// STORY TRAY — başlık altında, cover image üstünde
              if (_resolvedVenueIdForCurrentDetail != null)
                StoryTray(
                  key: ValueKey('${_resolvedVenueIdForCurrentDetail!}_$_storyTrayRefreshCount'),
                  venueId: _resolvedVenueIdForCurrentDetail!,
                  isUploading: _storyUploading,
                  onAddStory: hasActiveCheckinHere ? _openAddStory : null,
                ),

              const SizedBox(height: 8),

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

              const SizedBox(height: 12),

              // Tag alanini simdilik gizliyoruz.

              /// ADDRESS
              Text(
                _venueDetails?['address'] ?? widget.venue.address,
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 6),

              /// CHECK-IN STATS
              _buildCheckinStatsSection(),
              const SizedBox(height: 10),

              /// 🟢 OPEN STATUS
              if (opening != null)
                Text(
                  isOpen ? 'Open now' : 'Closed',
                  style: TextStyle(
                    color: isOpen ? Colors.green : Colors.red,
                    fontWeight: FontWeight.w500,
                  ),
                ),

              /// 🕐 TODAY HOURS
              if (weekdayText != null && weekdayText.isNotEmpty)
                Text(
                  weekdayText[DateTime.now().weekday - 1],
                  style: const TextStyle(color: Colors.grey),
                ),
              if (_venueDetails?['rating'] != null)
                Row(
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 4),
                    Text(_venueDetails!['rating'].toStringAsFixed(1)),
                  ],
                ),

              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: _canOpenDirections ? () => _openDirections() : null,
                style: TextButton.styleFrom(foregroundColor: AppTheme.brandPrimary),
                icon: const Icon(Icons.map),
                label: const Text('Get Directions'),
              ),

              /// DESCRIPTION
              if (_enrichedVenueData?['description'] != null &&
                  (_enrichedVenueData!['description'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildDescriptionSection(
                  _enrichedVenueData!['description'] as String,
                ),
              ],

              /// UPCOMING EVENTS
              if (_enrichedVenueData?['upcomingEvents'] is List &&
                  (_enrichedVenueData!['upcomingEvents'] as List).isNotEmpty) ...[
                const SizedBox(height: 16),
                _buildUpcomingEventsSection(
                  (_enrichedVenueData!['upcomingEvents'] as List)
                      .whereType<Map>()
                      .map((e) => VenueUpcomingEvent.fromJson(
                            Map<String, dynamic>.from(e),
                          ))
                      .toList(),
                ),
              ],

              const SizedBox(height: 24),

              /// WHO'S HERE / CHECK IN
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _loadingActiveCheckin || _resolvingVenueForCheckin
                      ? null
                      : () async {
                          if (hasActiveCheckinHere) {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => VenuePeoplePage(
                                  venue: widget.venue,
                                  listVenueId:
                                      _activeCheckinVenueId ??
                                      _resolvedVenueIdForCurrentDetail,
                                ),
                              ),
                            );
                            _refreshCheckinStats();
                            return;
                          }
                          await _openCheckinFlow();
                        },
                  child: Text(
                    _resolvingVenueForCheckin
                        ? 'Preparing venue...'
                        : hasActiveCheckinHere
                        ? "Who's here?"
                        : "Check in",
                  ),
                ),
              ),

              /// CHECK OUT — sadece bu venue'da aktif check-in varken görünür
              if (hasActiveCheckinHere) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: _checkingOut
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Check out?'),
                                content: const Text(
                                  'You will leave this venue and your check-in will end.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child: const Text('Check out'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) await _checkout();
                          },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                    child: _checkingOut
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Check out'),
                  ),
                ),
              ],
                ],       // Column children
              ),         // Column
            ),           // SingleChildScrollView
          ),             // SafeArea

          // ── Floating back button — always visible regardless of scroll ──
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(left: 8, top: 6),
                child: Material(
                  color: Colors.black.withValues(alpha: 0.32),
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 18),
                    onPressed: () => Navigator.pop(context),
                    tooltip: 'Back',
                  ),
                ),
              ),
            ),
          ),
        ],   // Stack children
      ),     // Stack
    );
  }
}

// ─── Venue detail header avatar with story ring (stateless — state lives in parent) ───

class _VenueDetailAvatarRing extends StatelessWidget {
  final String photoUrl;
  final bool hasStories;
  final bool allSeen;
  final VoidCallback? onTap;

  static const _logoColors = [
    AppColors.magenta,
    AppColors.teal,
    AppColors.blue,
    AppColors.orange,
    AppColors.brand,
  ];

  const _VenueDetailAvatarRing({
    required this.photoUrl,
    required this.hasStories,
    required this.allSeen,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const avatarSize = 40.0;
    const ringWidth = 2.5;
    const gap = 2.0;
    const totalSize = avatarSize + (ringWidth + gap) * 2;

    final photo = photoUrl.isNotEmpty
        ? photoUrl
        : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4';

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(photo, width: avatarSize, height: avatarSize, fit: BoxFit.cover),
    );

    if (!hasStories) return avatar;

    final ringColors = allSeen
        ? [Colors.grey.shade400, Colors.grey.shade500]
        : _logoColors;

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: totalSize,
        height: totalSize,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: ringWidth + gap,
              top: ringWidth + gap,
              child: avatar,
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _DetailRingPainter(colors: ringColors, strokeWidth: ringWidth, radius: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;

  const _DetailRingPainter({required this.colors, required this.strokeWidth, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final rrect = RRect.fromRectAndRadius(rect.deflate(strokeWidth / 2), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(colors: [...colors, colors.first]).createShader(rect);
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(covariant _DetailRingPainter old) =>
      old.colors != colors || old.strokeWidth != strokeWidth;
}
