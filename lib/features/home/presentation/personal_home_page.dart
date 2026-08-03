import 'dart:io';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/features/camera/presentation/camera_screen.dart';
import 'package:kmstry_frontend/features/media/text_overlay_composer.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/checkin/services/quick_checkin_launcher.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_bell.dart';
import 'package:kmstry_frontend/features/people/presentation/find_friends_page.dart';
import 'package:kmstry_frontend/features/people/presentation/who_is_nearby_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/discover_events_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/my_events_page.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

/// Location (map) tab position in the personal navbar: Home(0), Venues/map(1).
const int _kLocationTabIndex = 1;

/// Personal account landing tab — a lively feed: active check-in status, the
/// stories of followed venues & matched people, and today's events the user is
/// attending. Sections only render when they have content.
class PersonalHomePage extends StatefulWidget {
  const PersonalHomePage({super.key});

  @override
  State<PersonalHomePage> createState() => _PersonalHomePageState();
}

class _PersonalHomePageState extends State<PersonalHomePage> {
  final VenueCheckinRepository _checkinRepo = VenueCheckinRepository();
  final VenueRepository _venueRepo = VenueRepository();
  final StoryRepository _storyRepo = StoryRepository();
  final VenueEventRepository _eventRepo = VenueEventRepository();
  final VenueContextRepository _venueContextRepo = VenueContextRepository();
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();

  ActiveCheckin? _activeCheckin;
  Venue? _activeVenue;
  // Story yüklenirken balon çemberi döner (venue detay ile aynı davranış).
  bool _storyUploading = false;
  List<TodayEvent> _followedEvents = const [];
  // Boş-durum mesajını ayırt etmek için: kullanıcı hiç mekan takip ediyor mu?
  bool _followsAnyVenue = false;
  List<StoryGroup> _stories = const [];
  List<TodayEvent> _events = const [];
  List<Venue> _trendingVenues = const [];
  List<TodayEvent> _discoverEvents = const [];
  List<StoryItem> _myStories = const [];
  final Set<String> _viewedGroupIds = {};

  bool _loading = true;

  /// Home feed'i sahte stories/events ile önizleme. Env ile kontrol edilir:
  ///   flutter run --dart-define=USE_DUMMY_HOME=true   → mock data görünür
  ///   (varsayılan false)                              → gerçek endpoint'ler
  static const bool _useDummyData = bool.fromEnvironment(
    'USE_DUMMY_HOME',
    defaultValue: false,
  );

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (_useDummyData) {
      final results = await Future.wait([
        _checkinRepo.getActiveCheckin().catchError((_) => null),
        _eventRepo.getMyTodayEvents().catchError((_) => <TodayEvent>[]),
      ]);
      if (!mounted) return;
      final active = results[0] as ActiveCheckin?;
      // Real events the user is actually attending today come first, then the
      // dummy ones for layout preview.
      final realEvents = results[1] as List<TodayEvent>;
      setState(() {
        _activeCheckin = active;
        _stories = _dummyStories();
        _events = [...realEvents, ..._dummyEvents()];
        _loading = false;
      });
      if (active != null) {
        try {
          final venue = await _venueRepo.getVenueById(active.venueId);
          if (mounted) setState(() => _activeVenue = venue);
        } catch (_) {}
      }
      await Future.wait([_loadFollowedEvents(), _loadTrendingVenues(), _loadMyStories(), _loadDiscoverEvents()]);
      return;
    }

    final results = await Future.wait([
      _checkinRepo.getActiveCheckin().catchError((_) => null),
      _storyRepo.getHomeStories().catchError((_) => <StoryGroup>[]),
      _eventRepo.getMyTodayEvents().catchError((_) => <TodayEvent>[]),
    ]);
    if (!mounted) return;
    final active = results[0] as ActiveCheckin?;
    setState(() {
      _activeCheckin = active;
      _stories = results[1] as List<StoryGroup>;
      _events = results[2] as List<TodayEvent>;
      _loading = false;
      if (active == null) _activeVenue = null;
    });
    if (active != null) {
      try {
        final venue = await _venueRepo.getVenueById(active.venueId);
        if (mounted) setState(() => _activeVenue = venue);
      } catch (_) {
        // Non-fatal: banner still works with a minimal stub.
      }
    }
    await Future.wait([_loadFollowedEvents(), _loadTrendingVenues(), _loadMyStories(), _loadDiscoverEvents()]);
  }

  Future<void> _loadTrendingVenues() async {
    try {
      final anchor = _activeVenue;
      Position? position;
      if (anchor == null && await _locationPermissionService.isGranted()) {
        position = await Geolocator.getLastKnownPosition();
      }
      final venues = await _venueRepo.getTrendingVenues(
        latitude: anchor?.latitude ?? position?.latitude,
        longitude: anchor?.longitude ?? position?.longitude,
        limit: 10,
      );
      if (!mounted) return;
      setState(() => _trendingVenues = venues);
    } catch (_) {
      if (mounted) setState(() => _trendingVenues = const []);
    }
  }

  // "Happening Nearby" → takip edilmeyen mekanların yakın event'leri (ilk 5).
  Future<void> _loadDiscoverEvents() async {
    try {
      final anchor = _activeVenue;
      Position? position;
      if (anchor == null && await _locationPermissionService.isGranted()) {
        position = await Geolocator.getLastKnownPosition();
      }
      final events = await _eventRepo.getDiscoverEvents(
        latitude: anchor?.latitude ?? position?.latitude,
        longitude: anchor?.longitude ?? position?.longitude,
        limit: 5,
      );
      if (!mounted) return;
      setState(() => _discoverEvents = events);
    } catch (_) {
      if (mounted) setState(() => _discoverEvents = const []);
    }
  }

  // "Places you might like" → takip edilen venue'lerin yaklaşan event'leri.
  Future<void> _loadFollowedEvents() async {
    try {
      final events = await _eventRepo.getFollowedVenuesEvents(limit: 12);
      if (!mounted) return;
      setState(() {
        _followedEvents = events;
        // Event varsa zaten mekan takip ediliyor demektir.
        if (events.isNotEmpty) _followsAnyVenue = true;
      });
      // Event yoksa: hiç mi takip etmiyor, yoksa takip ettiklerinde event mi yok?
      if (events.isEmpty) {
        try {
          final follows = await _venueContextRepo.getFollowedVenues();
          if (mounted) {
            setState(() => _followsAnyVenue = follows.isNotEmpty);
          }
        } catch (_) {}
      }
    } catch (_) {
      if (mounted) setState(() => _followedEvents = const []);
    }
  }

  // ── TEMP dummy data (guarded by _useDummyData) ──────────────────────────
  StoryItem _dummyStory(String id, String seed, {bool viewed = false}) {
    final now = DateTime.now();
    return StoryItem(
      id: id,
      mediaUrl: 'https://picsum.photos/seed/$seed/600/1000',
      mediaType: 'photo',
      thumbnailUrl: 'https://picsum.photos/seed/$seed/200/320',
      expiresAt: now.add(const Duration(hours: 6)),
      createdAt: now,
      viewedByMe: viewed,
    );
  }

  List<StoryGroup> _dummyStories() {
    StoryGroup person(
      String id,
      String name,
      String seed, {
      bool viewed = false,
    }) {
      return StoryGroup(
        user: StoryUser(
          id: id,
          fullName: name,
          photo: 'https://picsum.photos/seed/$seed-a/200/200',
        ),
        stories: [_dummyStory('$id-s1', seed, viewed: viewed)],
      );
    }

    StoryGroup venue(String id, String label, String seed) {
      return StoryGroup(
        user: StoryUser(id: id, fullName: label),
        venueLabel: label,
        featuredPhotoUrl: 'https://picsum.photos/seed/$seed/300/300',
        stories: [
          _dummyStory('$id-s1', seed),
          _dummyStory('$id-s2', '$seed-2'),
        ],
      );
    }

    // Mixed friend + venue stories (venues carry a venueLabel → venue bubble).
    return [
      person('u-wai', 'wai', 'wai'),
      venue('v-1', 'test venue1', 'venue1'),
      person('u-deniz', 'deniz', 'deniz'),
      person('u-mehtap', 'mehtap', 'mehtap'),
      venue('v-2', 'test venue2', 'venue2'),
      person('u-ali', 'ali', 'ali', viewed: true),
    ];
  }

  List<TodayEvent> _dummyEvents() {
    final now = DateTime.now();
    TodayEvent ev(
      String id,
      String title,
      String venueId,
      String venueName,
      int hour,
      String seed,
    ) {
      final start = DateTime(now.year, now.month, now.day, hour, 0);
      return TodayEvent(
        event: VenueUpcomingEvent(
          id: id,
          title: title,
          startAt: start,
          endAt: start.add(const Duration(hours: 3)),
          photo: 'https://picsum.photos/seed/$seed/400/400',
        ),
        venueId: venueId,
        venueName: venueName,
      );
    }

    return [
      ev('e-1', 'Live DJ Night', 'v-1', 'test venue1', 22, 'ev1'),
      ev('e-2', 'Happy Hour', 'v-2', 'test venue2', 19, 'ev2'),
    ];
  }

  Venue _venueForNavigation(ActiveCheckin active) {
    final venue = _activeVenue;
    if (venue != null) return venue;
    return Venue(
      id: active.venueId,
      name: active.venueName ?? 'Venue',
      type: 'venue',
      status: '',
      address: '',
      city: '',
      photoUrl: active.venuePhoto ?? '',
      latitude: 0,
      longitude: 0,
      tag: '',
    );
  }

  void _openVenueDetail(ActiveCheckin active) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenueDetailPage(venue: _venueForNavigation(active)),
      ),
    );
  }

  void _openRecommendedVenue(Venue venue) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
    );
  }

  void _openWhoIsHere(ActiveCheckin active) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenuePeoplePage(
          venue: _venueForNavigation(active),
          listVenueId: active.venueId,
        ),
      ),
    );
  }

  void _openWhoIsNearby() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const WhoIsNearbyPage()),
    );
  }

  void _openMap() {
    // Switch to the location (map) tab in the shell so the navbar stays visible,
    // instead of pushing a full-screen route over it.
    final nav = AppShellNav.of(context);
    if (nav != null) {
      nav.selectTab(_kLocationTabIndex);
    } else {
      // Fallback (e.g. Home opened outside the shell): push the map standalone.
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: VenueHomePage()),
        ),
      );
    }
  }

  Future<void> _openStories(int index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            StoryViewerPage(groups: _stories, initialGroupIndex: index),
      ),
    );
    if (!mounted) return;
    // Mark the opened group as viewed so the ring greys out immediately.
    setState(() => _viewedGroupIds.add(_stories[index].user.id));
    if (result is StoryViewerResult) {
      // A refresh keeps viewed state in sync with the backend on next open.
      _loadHomeStories();
    }
  }

  Future<void> _loadHomeStories() async {
    if (_useDummyData) return; // keep the dummy list intact
    try {
      final stories = await _storyRepo.getHomeStories();
      if (mounted) setState(() => _stories = stories);
    } catch (_) {}
  }

  // ── "Your story" balonu ─────────────────────────────────────────────────
  Future<void> _loadMyStories() async {
    try {
      final stories = await _storyRepo.getMyStories();
      if (mounted) setState(() => _myStories = stories);
    } catch (_) {}
  }

  List<StoryItem> get _myRealStories =>
      _myStories.where((s) => !s.isUploadingPlaceholder).toList();

  // Balona basınca: story varsa direkt izle; yoksa (check-in varsa) ekle;
  // check-in yoksa bilgilendirme dialog'u. (Popup/seçenek menüsü yok.)
  void _onMeStoryTap() {
    if (_myRealStories.isNotEmpty) {
      _viewMyStory();
      return;
    }
    if (_activeCheckin == null) {
      _showCheckinToShareDialog();
      return;
    }
    _openAddStoryForActiveCheckin();
  }

  // "+" rozetine basınca: her zaman story ekle (check-in yoksa bilgilendir).
  void _onMeAddStoryTap() {
    if (_activeCheckin == null) {
      _showCheckinToShareDialog();
      return;
    }
    _openAddStoryForActiveCheckin();
  }

  /// Kendi mevcut story'sini izle (venue detaydaki mantıkla aynı).
  void _viewMyStory() {
    final mine = _myRealStories;
    if (mine.isEmpty) return;
    final meGroup = StoryGroup(
      user: StoryUser(id: 'me', fullName: 'You'),
      stories: _myStories,
      isCurrentUserOwner: true,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [meGroup],
          initialGroupIndex: 0,
        ),
      ),
    ).then((_) {
      if (mounted) _loadMyStories();
    });
  }

  /// Check-in yokken: story paylaşmak için önce check-in gerektiğini anlatan
  /// etkileyici bilgilendirme + "yakındaki mekanlar" CTA'sı. (App-geneli dialog
  /// stili: ikon-başlıklı AlertDialog, tema şekli.)
  void _showCheckinToShareDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.auto_awesome_rounded, size: 28),
        title: const Text('Share your moment'),
        content: const Text(
          "Check in to a venue first — that's where your story comes alive for "
          'everyone there. Find a spot near you and start sharing!',
        ),
        // Her ikisi de text buton → yanyana sığar.
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              QuickCheckinLauncher().launch(context);
            },
            child: const Text('Browse nearby spots'),
          ),
        ],
      ),
    );
  }

  /// Aktif check-in varken: kamera aç → çekilen medyayı story olarak paylaş.
  Future<void> _openAddStoryForActiveCheckin() async {
    final checkinId = _activeCheckin?.id;
    if (checkinId == null || checkinId.isEmpty) return;

    final dynamic captureResult = await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const CameraScreen(useFrontCamera: true),
      ),
    );
    if (!mounted) return;

    final File? file = captureResult is CapturedMedia
        ? captureResult.file
        : captureResult as File?;
    final overlay = captureResult is CapturedMedia
        ? captureResult.overlay
        : null;
    if (file == null) return;

    final path = file.path.toLowerCase();
    final isVideo =
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.m4v');

    // Kutlama kartı için overlay'i async gap'ten önce yakala.
    final rootOverlay = Overlay.maybeOf(context, rootOverlay: true);

    setState(() => _storyUploading = true);

    try {
      await _storyRepo.createStory(
        checkinId: checkinId,
        file: file,
        mediaType: isVideo ? 'video' : 'photo',
        textOverlayJson: overlay?.toJsonString(),
      );
      if (mounted) {
        setState(() => _storyUploading = false);
        _loadHomeStories();
        _loadMyStories();
      }
      // "Story shared" kutlama kartı — venue detay ile aynı bileşen.
      if (rootOverlay != null) {
        final venueName = (_activeVenue?.name.trim().isNotEmpty ?? false)
            ? _activeVenue!.name
            : (_activeCheckin?.venueName ?? 'your venue');
        showStorySharedCard(
          rootOverlay,
          mediaFile: file,
          venueName: venueName,
          isVideo: isVideo,
        );
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _storyUploading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Story paylaşılamadı. Tekrar dene.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _openEvent(TodayEvent item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VenueEventDetailPage(event: item.event, venueId: item.venueId),
      ),
    );
  }

  void _openMyEvents() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const MyEventsPage(initialFilter: 'today'),
      ),
    );
  }

  void _openDiscoverEvents() {
    final anchor = _activeVenue;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverEventsPage(
          latitude: anchor?.latitude,
          longitude: anchor?.longitude,
        ),
      ),
    );
  }

  // "Up Next at Your Spots" → See more: takip edilen mekanların tüm event'leri
  // (Happening Nearby ile aynı takvim/filtre tasarımı, scope='followed').
  void _openFollowedEvents() {
    final anchor = _activeVenue;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DiscoverEventsPage(
          latitude: anchor?.latitude,
          longitude: anchor?.longitude,
          scope: 'followed',
          title: 'Up Next at Your Spots',
        ),
      ),
    );
  }

  bool _isGroupViewed(StoryGroup group) {
    if (_viewedGroupIds.contains(group.user.id)) return true;
    return group.stories.isNotEmpty && group.stories.every((s) => s.viewedByMe);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final colors = theme.colorScheme;
    final bg = isDark ? const Color(0xFF0B0F17) : theme.scaffoldBackgroundColor;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.grey[200];

    final active = _activeCheckin;
    final hasStories = _stories.isNotEmpty;
    final hasEvents = _events.isNotEmpty;
    final hasFollowedEvents = _followedEvents.isNotEmpty;
    final hasTrending = _trendingVenues.isNotEmpty;
    final hasDiscover = _discoverEvents.isNotEmpty;
    final nothingYet =
        !_loading &&
        active == null &&
        !hasStories &&
        !hasEvents &&
        !hasFollowedEvents &&
        !hasTrending;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const AppLogo(),
        title: Text(
          'Home',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Find friends',
            icon: Icon(
              Icons.person_add_alt_1_outlined,
              color: colors.onSurface,
            ),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FindFriendsPage()),
              );
            },
          ),
          const NotificationBell(),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadAll,
        child: ListView(
          key: const PageStorageKey<String>('personal-home-scroll'),
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const SizedBox(height: 16),
            // ── Active check-in / check-in CTA ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: active != null
                  ? Column(
                      children: [
                        _ActiveCheckinBanner(
                          checkin: active,
                          onVenueTap: () => _openVenueDetail(active),
                          onWhosHere: () => _openWhoIsHere(active),
                        ),
                        const SizedBox(height: 12),
                        _WhoIsNearbyBanner(onTap: _openWhoIsNearby),
                      ],
                    )
                  : (_loading
                        ? const SizedBox.shrink()
                        : _CheckinCta(
                            onTap: () async {
                              await QuickCheckinLauncher().launch(context);
                              if (mounted) _loadAll();
                            },
                          )),
            ),

            // ── Explore map CTA ────────────────────────────────────────────
            // Gated on !_loading so it doesn't pop in before the async sections
            // (stories / events / active check-in) — everything appears together.
            if (!_loading) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _MapCta(onTap: _openMap),
              ),
            ],

            // ── Up Next at Your Spots — takip edilen venue'lerin event'leri.
            //    Veri yoksa (ve yükleme bittiyse) etkileyici boş-durum mesajı.
            if (hasFollowedEvents) ...[
              const SizedBox(height: 24),
              _SectionTitle(
                title: 'Up Next at Your Spots',
                actionLabel: 'See more',
                onAction: _openFollowedEvents,
              ),
              const SizedBox(height: 12),
              _FollowedEventsRow(
                events: _followedEvents,
                onTap: _openEvent,
              ),
            ] else if (!_loading) ...[
              const SizedBox(height: 24),
              _SectionTitle(title: 'Up Next at Your Spots'),
              const SizedBox(height: 12),
              _FollowedEventsEmpty(followsAnyVenue: _followsAnyVenue),
            ],

            // ── Stories row — her zaman "Your story" balonu + varsa
            //    arkadaş/venue story'leri. Check-in yoksa balon inactive olur.
            if (!_loading) ...[
              const SizedBox(height: 22),
              _SectionTitle(title: 'Stories'),
              const SizedBox(height: 12),
              _StoriesRow(
                stories: _stories,
                isViewed: _isGroupViewed,
                onTap: _openStories,
                hasActiveCheckin: _activeCheckin != null,
                hasMyStory: _myRealStories.isNotEmpty,
                // Öncelik: gerçek story → kullanıcının avatarı → check-in'de
                // seçilen featured foto (avatar yoksa).
                myBubbleImageUrl: _myRealStories.isNotEmpty
                    ? (_myRealStories.first.thumbnailUrl ??
                          _myRealStories.first.mediaUrl)
                    : ((_activeCheckin?.userPhoto?.isNotEmpty ?? false)
                          ? _activeCheckin!.userPhoto
                          : _activeCheckin?.featuredPhoto),
                onMeTap: _onMeStoryTap,
                onMeAddTap: _onMeAddStoryTap,
                isUploading: _storyUploading,
              ),
            ],

            // ── Today's events — veri yoksa boş-durum mesajı + See more ──────
            if (hasEvents) ...[
              const SizedBox(height: 20),
              _SectionTitle(
                title: "Today's events",
                actionLabel: 'See more',
                onAction: _openMyEvents,
              ),
              const SizedBox(height: 10),
              ..._events.map(
                (e) => Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: _EventCard(item: e, onTap: () => _openEvent(e)),
                ),
              ),
            ] else if (!_loading) ...[
              const SizedBox(height: 20),
              _SectionTitle(
                title: "Today's events",
                actionLabel: 'See more',
                onAction: _openMyEvents,
              ),
              const SizedBox(height: 10),
              const _TodaysEventsEmpty(),
            ],

            // ── Trending Now — most-searched venues (same design as
            //    "Places you might like") ────────────────────────────────────
            if (hasTrending) ...[
              const SizedBox(height: 20),
              _SectionTitle(title: 'Trending Now'),
              const SizedBox(height: 12),
              _RecommendedVenuesRow(
                venues: _trendingVenues,
                onTap: _openRecommendedVenue,
              ),
            ],

            // ── Happening Nearby — takip edilmeyen mekanların yakın event'leri.
            if (hasDiscover) ...[
              const SizedBox(height: 20),
              _SectionTitle(
                title: 'Happening Nearby',
                actionLabel: 'See more',
                onAction: _openDiscoverEvents,
              ),
              const SizedBox(height: 12),
              _DiscoverEventsList(
                events: _discoverEvents,
                onTap: _openEvent,
              ),
            ],

            if (nothingYet)
              Padding(
                padding: const EdgeInsets.only(top: 60),
                child: Center(
                  child: Text(
                    'Follow venues and match with people\nto light up your home feed.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: colors.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, this.actionLabel, this.onAction});

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.onSurface,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                actionLabel!,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StoriesRow extends StatelessWidget {
  const _StoriesRow({
    required this.stories,
    required this.isViewed,
    required this.onTap,
    required this.hasActiveCheckin,
    required this.hasMyStory,
    required this.onMeTap,
    required this.onMeAddTap,
    this.myBubbleImageUrl,
    this.isUploading = false,
  });

  final List<StoryGroup> stories;
  final bool Function(StoryGroup) isViewed;
  final void Function(int index) onTap;

  /// "Your story" balonu: check-in varsa aktif (story ekle/izle), yoksa inactive
  /// (basınca bilgilendirme + "yakındaki mekanlar" CTA'sı).
  final bool hasActiveCheckin;
  final bool hasMyStory;
  final VoidCallback onMeTap;
  final VoidCallback onMeAddTap;
  final String? myBubbleImageUrl;
  final bool isUploading;

  @override
  Widget build(BuildContext context) {
    // İlk item her zaman "Your story" balonu.
    final itemCount = stories.length + 1;
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, i) {
          if (i == 0) {
            return _MeStoryBubble(
              active: hasActiveCheckin,
              hasStory: hasMyStory,
              imageUrl: myBubbleImageUrl,
              onTap: onMeTap,
              onAddTap: onMeAddTap,
              uploading: isUploading,
            );
          }
          final s = stories[i - 1];
          return _StoryBubble(
            group: s,
            viewed: isViewed(s),
            onTap: () => onTap(i - 1),
          );
        },
      ),
    );
  }
}

/// Kullanıcının kendi "Your story" balonu (karemsi). Aktifken (+ ile) story
/// eklenir; inactive iken gri görünür ve basınca check-in bilgilendirmesi çıkar.
class _MeStoryBubble extends StatefulWidget {
  const _MeStoryBubble({
    required this.active,
    required this.hasStory,
    required this.onTap,
    required this.onAddTap,
    this.imageUrl,
    this.uploading = false,
  });

  final bool active;
  final bool hasStory;
  final VoidCallback onTap;
  final VoidCallback onAddTap;
  final String? imageUrl;
  final bool uploading;

  @override
  State<_MeStoryBubble> createState() => _MeStoryBubbleState();
}

class _MeStoryBubbleState extends State<_MeStoryBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    if (widget.uploading) _spin.repeat();
  }

  @override
  void didUpdateWidget(covariant _MeStoryBubble old) {
    super.didUpdateWidget(old);
    if (widget.uploading && !_spin.isAnimating) {
      _spin.repeat();
    } else if (!widget.uploading && _spin.isAnimating) {
      _spin.stop();
      _spin.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final uploading = widget.uploading;

    const avatarSize = 58.0;
    const ringPad = 3.0;
    const ringStroke = 2.4;
    const avatarRadius = 12.0;
    final totalSize = avatarSize + (ringPad + ringStroke) * 2;

    // Story varsa marka-gradyan halka (izlenebilir); check-in var ama story yok
    // → düz primary; check-in yok → gri (inactive).
    const brandColors = [
      AppColors.magenta,
      AppColors.teal,
      AppColors.blue,
      AppColors.orange,
      AppColors.brand,
    ];
    final List<Color> ringColors = (widget.hasStory || uploading)
        ? brandColors
        : (widget.active
              ? [colors.primary, colors.primary]
              : [
                  colors.onSurface.withValues(alpha: 0.2),
                  colors.onSurface.withValues(alpha: 0.2),
                ]);

    Widget base = ClipRRect(
      borderRadius: BorderRadius.circular(avatarRadius),
      child: (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
          ? CachedImage(widget.imageUrl!,
              width: avatarSize, height: avatarSize, fit: BoxFit.cover)
          : Container(
              width: avatarSize,
              height: avatarSize,
              color: colors.onSurface.withValues(alpha: 0.06),
              child: Icon(
                Icons.person_rounded,
                color: colors.onSurface.withValues(alpha: 0.35),
                size: 30,
              ),
            ),
    );
    if (!widget.active && !uploading) {
      base = Opacity(opacity: 0.55, child: base);
    }

    final ring = CustomPaint(
      size: Size(totalSize, totalSize),
      painter: _HomeSquareRingPainter(
        colors: ringColors,
        strokeWidth: ringStroke,
        radius: avatarRadius + ringPad + ringStroke,
      ),
    );

    return GestureDetector(
      onTap: uploading ? null : widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Dış Stack: "+" rozeti balonun dış köşesine taşabilsin (kolay basılır).
          Stack(
            clipBehavior: Clip.none,
            children: [
              SizedBox(
                width: totalSize,
                height: totalSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Yükleme sırasında halka döner (venue detay ile aynı efekt).
                    uploading
                        ? RotationTransition(turns: _spin, child: ring)
                        : ring,
                    base,
                  ],
                ),
              ),
              // Yüklenmiyorsa "+" ekle rozeti (ayrı tıklanır); check-in yok → kilit.
              if (!uploading)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: GestureDetector(
                    onTap: widget.onAddTap,
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: widget.active
                            ? colors.primary
                            : colors.onSurface.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.scaffoldBackgroundColor,
                          width: 2.5,
                        ),
                      ),
                      child: Icon(
                        widget.active ? Icons.add_rounded : Icons.lock_rounded,
                        size: 15,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Your story',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w400,
              color: colors.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({
    required this.group,
    required this.viewed,
    required this.onTap,
  });

  final StoryGroup group;
  final bool viewed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isVenue = group.venueLabel != null;
    final image = group.bubbleImageUrl;
    final label = isVenue ? group.venueLabel! : group.user.displayName;

    // Match the app's story tray: a rounded-SQUARE avatar with a sweep-gradient
    // ring (brand colors when unseen, grey when seen).
    const avatarSize = 58.0;
    const ringPad = 3.0;
    const ringStroke = 2.4;
    const avatarRadius = 12.0;
    final totalSize = avatarSize + (ringPad + ringStroke) * 2;

    Widget avatar = ClipRRect(
      borderRadius: BorderRadius.circular(avatarRadius),
      child: (image != null && image.isNotEmpty)
          ? CachedImage(
              image,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorWidget: (context) =>
                  _avatarFallback(colors, isVenue, label, avatarSize),
            )
          : _avatarFallback(colors, isVenue, label, avatarSize),
    );

    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: totalSize + 8,
        child: Column(
          children: [
            SizedBox(
              width: totalSize,
              height: totalSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: Size(totalSize, totalSize),
                    painter: _HomeSquareRingPainter(
                      colors: viewed
                          ? [
                              colors.onSurface.withValues(alpha: 0.22),
                              colors.onSurface.withValues(alpha: 0.22),
                            ]
                          : const [
                              AppColors.magenta,
                              AppColors.teal,
                              AppColors.blue,
                              AppColors.orange,
                              AppColors.brand,
                            ],
                      strokeWidth: ringStroke,
                      radius: avatarRadius + ringPad + ringStroke,
                    ),
                  ),
                  avatar,
                  // Venue badge — marks this bubble as a venue, not a person.
                  if (isVenue)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 2,
                          ),
                        ),
                        child: const Icon(
                          Icons.storefront,
                          size: 10,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isVenue ? FontWeight.w700 : FontWeight.w400,
                color: colors.onSurface.withValues(alpha: isVenue ? 0.95 : 0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _avatarFallback(
    ColorScheme colors,
    bool isVenue,
    String label,
    double size,
  ) {
    if (isVenue) {
      return Container(
        width: size,
        height: size,
        color: AppColors.brand.withValues(alpha: 0.16),
        alignment: Alignment.center,
        child: const Icon(Icons.storefront, size: 24, color: AppColors.brand),
      );
    }
    final initial = label.isNotEmpty ? label[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      color: colors.primary.withValues(alpha: 0.15),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: colors.primary,
        ),
      ),
    );
  }
}

class _RecommendedVenuesRow extends StatelessWidget {
  const _RecommendedVenuesRow({required this.venues, required this.onTap});

  final List<Venue> venues;
  final ValueChanged<Venue> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 282,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: venues.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final venue = venues[index];
          return _RecommendedVenueCard(venue: venue, onTap: () => onTap(venue));
        },
      ),
    );
  }
}

class _RecommendedVenueCard extends StatelessWidget {
  const _RecommendedVenueCard({required this.venue, required this.onTap});

  final Venue venue;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final photo = venue.photoUrl.isNotEmpty
        ? venue.photoUrl
        : (venue.photos.isNotEmpty ? venue.photos.first : '');
    final reason = (venue.recommendationReason ?? '').trim().isNotEmpty
        ? venue.recommendationReason!.trim()
        : 'Similar to places you like';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 272,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 164,
                  child: photo.isNotEmpty
                      ? CachedImage(
                          photo,
                          fit: BoxFit.cover,
                          errorWidget: (context) =>
                              _venuePhotoFallback(colors),
                        )
                      : _venuePhotoFallback(colors),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _venueMeta(venue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.58),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        reason,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.primary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _venuePhotoFallback(ColorScheme colors) {
    return Container(
      color: colors.primary.withValues(alpha: 0.12),
      child: Icon(
        Icons.place_rounded,
        color: colors.primary.withValues(alpha: 0.75),
        size: 32,
      ),
    );
  }

  String _venueMeta(Venue venue) {
    final parts = <String>[_typeLabel(venue.type)];
    final distance = _formatDistance(venue.distanceMeters);
    if (distance != null) parts.add(distance);
    final active = venue.checkinCountActive ?? 0;
    if (active > 0) parts.add('$active here now');
    return parts.join(' · ');
  }

  String _typeLabel(String type) {
    switch (type.toLowerCase()) {
      case 'bar':
        return 'Bar';
      case 'club':
        return 'Nightclub';
      case 'cafe':
        return 'Cafe';
      case 'lounge':
        return 'Lounge';
      case 'restaurant':
        return 'Restaurant';
      default:
        return 'Venue';
    }
  }

  String? _formatDistance(int? meters) {
    if (meters == null) return null;
    if (meters < 1000) return '${meters}m';
    return '${(meters / 1000).toStringAsFixed(meters < 10000 ? 1 : 0)}km';
  }
}

/// "Places you might like" — horizontal carousel of upcoming events from the
/// venues the user follows. Cover photo + title + description + a CTA that
/// opens the event detail.
/// "Up Next at Your Spots" boş-durumu: kullanıcı henüz mekan takip etmiyorsa ya
/// da takip ettiklerinin yaklaşan event'i yoksa gösterilen etkileyici mesaj.
class _FollowedEventsEmpty extends StatelessWidget {
  const _FollowedEventsEmpty({required this.followsAnyVenue});

  /// Kullanıcı en az bir mekan takip ediyor mu? Mesaj buna göre değişir.
  final bool followsAnyVenue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    // Mekan takip ediyor ama etkinlik yok → farklı mesaj.
    final title = followsAnyVenue
        ? 'No upcoming events at the venues you follow.'
        : "Follow your favorite spots and never miss what's next.";
    final subtitle = followsAnyVenue
        ? 'Check back soon — new events will show up here.'
        : 'Follow venues to stay in the loop on their upcoming events.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.event_available_rounded,
                color: colors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FollowedEventsRow extends StatelessWidget {
  const _FollowedEventsRow({required this.events, required this.onTap});

  final List<TodayEvent> events;
  final ValueChanged<TodayEvent> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 288,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: events.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final item = events[index];
          return _FollowedEventCard(item: item, onTap: () => onTap(item));
        },
      ),
    );
  }
}

class _FollowedEventCard extends StatelessWidget {
  const _FollowedEventCard({required this.item, required this.onTap});

  final TodayEvent item;
  final VoidCallback onTap;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  String _dateLabel(DateTime dt) {
    final l = dt.toLocal();
    final time =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '${_weekdays[l.weekday - 1]}, ${l.day} ${_months[l.month - 1]} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final event = item.event;
    // Kapak: event'in ilk fotoğrafı, yoksa venue fotoğrafı.
    final photo = (event.photo != null && event.photo!.isNotEmpty)
        ? event.photo!
        : (event.photos.isNotEmpty
              ? event.photos.first
              : (item.venuePhoto ?? ''));
    final description = (event.description ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 230,
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                    child: SizedBox(
                      width: double.infinity,
                      height: 120,
                      child: photo.isNotEmpty
                          ? CachedImage(
                              photo,
                              fit: BoxFit.cover,
                              errorWidget: (context) => _cover(colors),
                            )
                          : _cover(colors),
                    ),
                  ),
                  Positioned(
                    left: 10,
                    bottom: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _dateLabel(event.startAt),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Expanded(
                        child: Text(
                          description.isNotEmpty
                              ? description
                              : 'Tap to see what this event is about.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.62),
                            fontSize: 12.5,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.primary,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                'View details',
                                style: TextStyle(
                                  color: colors.onPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_rounded,
                                size: 15,
                                color: colors.onPrimary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cover(ColorScheme colors) {
    return Container(
      color: colors.primary.withValues(alpha: 0.12),
      child: Icon(
        Icons.event,
        color: colors.primary.withValues(alpha: 0.75),
        size: 32,
      ),
    );
  }
}

/// Happening Nearby → yatay (manzara) kartların alt alta listesi.
/// Solda kapak fotoğrafı, sağda mekan adı / başlık / tarih / açıklama.
class _DiscoverEventsList extends StatelessWidget {
  const _DiscoverEventsList({required this.events, required this.onTap});

  final List<TodayEvent> events;
  final ValueChanged<TodayEvent> onTap;

  // Kart yüksekliği + kartlar arası boşluk (scroll yüksekliğini hesaplamak için).
  static const double _cardHeight = 122;
  static const double _gap = 12;
  static const int _maxVisible = 3;

  @override
  Widget build(BuildContext context) {
    // 3 veya daha az kart → düz liste. Fazlası → 3 kart yüksekliğinde kayan liste.
    if (events.length <= _maxVisible) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (int i = 0; i < events.length; i++) ...[
              if (i > 0) const SizedBox(height: _gap),
              _DiscoverEventCard(
                item: events[i],
                onTap: () => onTap(events[i]),
              ),
            ],
          ],
        ),
      );
    }

    // 3 tam kart + sonraki kartın bir kısmını (peek) göster → "devamı var" sinyali.
    const double peek = 30;
    final scrollHeight =
        _cardHeight * _maxVisible + _gap * _maxVisible + peek;
    return SizedBox(
      height: scrollHeight,
      // Alt kenarda solma (fade) efekti: peek eden kart aşağı doğru silinir,
      // böylece kaydırılabilir olduğu belli olur.
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black, Colors.black, Colors.transparent],
          stops: [0.0, 0.86, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, peek),
          physics: const BouncingScrollPhysics(),
          itemCount: events.length,
          separatorBuilder: (context, index) => const SizedBox(height: _gap),
          itemBuilder: (context, index) => _DiscoverEventCard(
            item: events[index],
            onTap: () => onTap(events[index]),
          ),
        ),
      ),
    );
  }
}

class _DiscoverEventCard extends StatelessWidget {
  const _DiscoverEventCard({required this.item, required this.onTap});

  final TodayEvent item;
  final VoidCallback onTap;

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static const List<String> _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
  ];

  String _dateLabel(DateTime dt) {
    final l = dt.toLocal();
    final time =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '${_weekdays[l.weekday - 1]}, ${l.day} ${_months[l.month - 1]} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final event = item.event;
    final photo = (event.photo != null && event.photo!.isNotEmpty)
        ? event.photo!
        : (event.photos.isNotEmpty
              ? event.photos.first
              : (item.venuePhoto ?? ''));
    final description = (event.description ?? '').trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
            ],
          ),
          child: SizedBox(
            height: 122,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(16),
                  ),
                  child: SizedBox(
                    width: 112,
                    height: 122,
                    child: photo.isNotEmpty
                        ? CachedImage(
                            photo,
                            fit: BoxFit.cover,
                            width: 112,
                            height: 122,
                            errorWidget: (context) => _cover(colors),
                          )
                        : _cover(colors),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 11, 6, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          item.venueName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.55),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          event.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.schedule,
                              size: 13,
                              color: colors.primary.withValues(alpha: 0.8),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _dateLabel(event.startAt),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.onSurface.withValues(alpha: 0.6),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Flexible(
                            child: Text(
                              description,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface.withValues(alpha: 0.62),
                                fontSize: 12.5,
                                height: 1.3,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Center(
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color: colors.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(ColorScheme colors) {
    return Container(
      color: colors.primary.withValues(alpha: 0.12),
      child: Icon(
        Icons.event,
        color: colors.primary.withValues(alpha: 0.75),
        size: 30,
      ),
    );
  }
}

/// "Today's events" boş-durumu: bugün için katılınan bir event yok.
class _TodaysEventsEmpty extends StatelessWidget {
  const _TodaysEventsEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.06),
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(
                Icons.celebration_outlined,
                color: colors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                "You haven't joined any events for today.",
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.8),
                  fontSize: 13.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.item, required this.onTap});

  final TodayEvent item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final event = item.event;
    final photo = event.photo ?? item.venuePhoto ?? '';
    final local = event.startAt.toLocal();
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.onSurface.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: photo.isNotEmpty
                      ? CachedImage(
                          photo,
                          fit: BoxFit.cover,
                          errorWidget: (context) => _photoFallback(colors),
                        )
                      : _photoFallback(colors),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.schedule, size: 13, color: colors.primary),
                          const SizedBox(width: 4),
                          Text(
                            'Today · $time',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: colors.primary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        event.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.venueName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurface.withValues(alpha: 0.3),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _photoFallback(ColorScheme colors) {
    return Container(
      color: colors.primary.withValues(alpha: 0.12),
      child: Icon(Icons.event, color: colors.primary.withValues(alpha: 0.7)),
    );
  }
}

/// "You have an active check-in at {venue}" banner. The venue name is tappable
/// (→ venue detail) and a "See who's here" button opens the attendee list.
class _ActiveCheckinBanner extends StatelessWidget {
  const _ActiveCheckinBanner({
    required this.checkin,
    required this.onVenueTap,
    required this.onWhosHere,
  });

  final ActiveCheckin checkin;
  final VoidCallback onVenueTap;
  final VoidCallback onWhosHere;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final venueName = (checkin.venueName ?? '').trim();

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colors.primary.withValues(alpha: 0.14)
            : colors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.primary.withValues(alpha: 0.30)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_circle,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Active check-in',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _ActiveCheckinLine(
                      venueName: venueName,
                      onVenueTap: onVenueTap,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onWhosHere,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.groups_outlined, size: 20),
              label: const Text(
                "See who's here",
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveCheckinLine extends StatelessWidget {
  const _ActiveCheckinLine({required this.venueName, required this.onVenueTap});

  final String venueName;
  final VoidCallback onVenueTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final baseStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w700,
      color: colors.onSurface,
      height: 1.25,
    );

    if (venueName.isEmpty) {
      return Text('You have an active check-in', style: baseStyle);
    }

    return GestureDetector(
      onTap: onVenueTap,
      child: RichText(
        text: TextSpan(
          style: baseStyle,
          children: [
            const TextSpan(text: 'You are at '),
            TextSpan(
              text: venueName,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w900,
                fontSize: 17,
                letterSpacing: 0.2,
                decorationColor: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Who's nearby" banner — shown only alongside an active check-in.
class _WhoIsNearbyBanner extends StatelessWidget {
  const _WhoIsNearbyBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.onSurface.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.explore_rounded,
                  color: colors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Who's nearby",
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'People checking in at venues near yours — within about '
                      '300 m of where you checked in.',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.3,
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: colors.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Venue map CTA that opens the location tab.
class _MapCta extends StatelessWidget {
  const _MapCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.04)
                : Colors.black.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.onSurface.withValues(alpha: 0.10)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.map_outlined,
                  color: colors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Catch the vibe',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Find a place, check in, and see what is happening now.',
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colors.onSurface.withValues(alpha: 0.35),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Check-in CTA shown when there's no active check-in.
class _CheckinCta extends StatelessWidget {
  const _CheckinCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [colors.primary, colors.primary.withValues(alpha: 0.82)],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.onPrimary.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.add_location_alt_outlined,
                    color: colors.onPrimary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Check in',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.onPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Share your moments. Check in now.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.onPrimary.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colors.onPrimary.withValues(alpha: 0.9),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded-square sweep-gradient story ring, mirroring the app's story tray so
/// home bubbles keep the same "karemsi" shape.
class _HomeSquareRingPainter extends CustomPainter {
  final List<Color> colors;
  final double strokeWidth;
  final double radius;

  const _HomeSquareRingPainter({
    required this.colors,
    required this.strokeWidth,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect =
        Offset(strokeWidth / 2, strokeWidth / 2) &
        Size(size.width - strokeWidth, size.height - strokeWidth);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final shader = SweepGradient(
      colors: [...colors, colors.first],
    ).createShader(rect);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..shader = shader
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HomeSquareRingPainter old) =>
      old.colors != colors;
}
