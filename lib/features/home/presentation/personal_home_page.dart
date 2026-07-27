import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/layout/app_shell.dart';
import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/checkin/services/quick_checkin_launcher.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_bell.dart';
import 'package:kmstry_frontend/features/people/data/suggested_person_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/presentation/who_is_nearby_page.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/active_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
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
  final MatchRepository _matchRepo = MatchRepository();
  final LocationPermissionService _locationPermissionService =
      LocationPermissionService();

  ActiveCheckin? _activeCheckin;
  Venue? _activeVenue;
  List<Venue> _recommendedVenues = const [];
  List<StoryGroup> _stories = const [];
  List<TodayEvent> _events = const [];
  List<SuggestedPersonItem> _suggestedPeople = const [];
  final Set<String> _viewedGroupIds = {};

  bool _loading = true;

  /// TEMP: preview the home feed with fake stories/events on a real device.
  /// Flip to false to go back to the live endpoints.
  static const bool _useDummyData = true;

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
      await Future.wait([_loadRecommendedVenues(), _loadSuggestedPeople()]);
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
    await Future.wait([_loadRecommendedVenues(), _loadSuggestedPeople()]);
  }

  Future<void> _loadSuggestedPeople() async {
    try {
      final people = await _matchRepo.getSuggestedForYou(limit: 10);
      if (!mounted) return;
      setState(() => _suggestedPeople = people);
    } catch (_) {
      if (mounted) setState(() => _suggestedPeople = const []);
    }
  }

  Future<void> _loadRecommendedVenues() async {
    try {
      final anchor = _activeVenue;
      Position? position;
      if (anchor == null && await _locationPermissionService.isGranted()) {
        position = await Geolocator.getLastKnownPosition();
        position ??= await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
          timeLimit: const Duration(seconds: 4),
        );
      }
      final venues = await _venueRepo.getRecommendedVenuesForMe(
        latitude: anchor?.latitude ?? position?.latitude,
        longitude: anchor?.longitude ?? position?.longitude,
        pageSize: 10,
      );
      if (!mounted) return;
      setState(() => _recommendedVenues = venues);
    } catch (_) {
      if (mounted) setState(() => _recommendedVenues = const []);
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

  void _openSuggestedPerson(SuggestedPersonItem item) {
    final active = item.activeCheckin;
    final shared = item.sharedVenue;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: active?.id,
          venueId: active?.venueId,
          hintVenueId: active?.venueId ?? shared?.id,
          hintVenueName: active?.venueName ?? shared?.name,
          hintVenueType: active?.venueType ?? shared?.type,
          hintVenuePhoto: active?.venuePhoto ?? shared?.photo,
          userId: item.id,
          userName: item.displayName,
          userUsername: item.username,
          userPhoto: item.photo,
          fallbackBio: item.bio,
        ),
      ),
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
    final hasRecommendations = _recommendedVenues.isNotEmpty;
    final hasSuggestedPeople = _suggestedPeople.isNotEmpty;
    final nothingYet =
        !_loading &&
        active == null &&
        !hasStories &&
        !hasEvents &&
        !hasRecommendations &&
        !hasSuggestedPeople;

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
        actions: const [NotificationBell(), SizedBox(width: 4)],
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

            // ── Personalized venue recommendations ───────────────────────
            if (hasRecommendations) ...[
              const SizedBox(height: 24),
              _SectionTitle(title: 'Places you might like'),
              const SizedBox(height: 12),
              _RecommendedVenuesRow(
                venues: _recommendedVenues,
                onTap: _openRecommendedVenue,
              ),
            ],

            // ── Stories row ────────────────────────────────────────────────
            if (hasStories) ...[
              const SizedBox(height: 22),
              _SectionTitle(title: 'Stories'),
              const SizedBox(height: 12),
              _StoriesRow(
                stories: _stories,
                isViewed: _isGroupViewed,
                onTap: _openStories,
              ),
            ],

            // ── Today's events ─────────────────────────────────────────────
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
            ],

            // ── People suggestions from shared venue taste ─────────────────
            if (hasSuggestedPeople) ...[
              const SizedBox(height: 20),
              _SectionTitle(title: 'Suggested for you'),
              const SizedBox(height: 12),
              _SuggestedPeopleRow(
                people: _suggestedPeople,
                onTap: _openSuggestedPerson,
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
  });

  final List<StoryGroup> stories;
  final bool Function(StoryGroup) isViewed;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 14),
        itemBuilder: (context, i) => _StoryBubble(
          group: stories[i],
          viewed: isViewed(stories[i]),
          onTap: () => onTap(i),
        ),
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
          ? Image.network(
              image,
              width: avatarSize,
              height: avatarSize,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
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
      height: 214,
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
          width: 212,
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
                  height: 116,
                  child: photo.isNotEmpty
                      ? Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
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

class _SuggestedPeopleRow extends StatelessWidget {
  const _SuggestedPeopleRow({required this.people, required this.onTap});

  final List<SuggestedPersonItem> people;
  final ValueChanged<SuggestedPersonItem> onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 206,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: people.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final person = people[index];
          return _SuggestedPersonCard(
            person: person,
            onTap: () => onTap(person),
          );
        },
      ),
    );
  }
}

class _SuggestedPersonCard extends StatelessWidget {
  const _SuggestedPersonCard({required this.person, required this.onTap});

  final SuggestedPersonItem person;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final photo = person.photo?.trim() ?? '';
    final shared = person.sharedVenue;
    final reason = person.suggestionReason.trim().isNotEmpty
        ? person.suggestionReason.trim()
        : 'You both visited similar places';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 218,
          padding: const EdgeInsets.all(12),
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
              _SuggestedPersonAvatar(photo: photo, label: person.displayName),
              const SizedBox(height: 8),
              Text(
                person.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                person.username.isNotEmpty
                    ? '@${person.username}'
                    : 'New person',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.58),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 11.5,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (shared != null && shared.name.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      Icons.place_rounded,
                      size: 13,
                      color: colors.onSurface.withValues(alpha: 0.48),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        shared.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: colors.onSurface.withValues(alpha: 0.58),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestedPersonAvatar extends StatelessWidget {
  const _SuggestedPersonAvatar({required this.photo, required this.label});

  final String photo;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 68,
        height: 68,
        child: photo.isNotEmpty
            ? Image.network(
                photo,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback(colors),
              )
            : _fallback(colors),
      ),
    );
  }

  Widget _fallback(ColorScheme colors) {
    final initial = label.trim().isNotEmpty
        ? label.trim()[0].toUpperCase()
        : '?';
    return Container(
      color: colors.primary.withValues(alpha: 0.13),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: colors.primary,
          fontSize: 26,
          fontWeight: FontWeight.w900,
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
                      ? Image.network(
                          photo,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _photoFallback(colors),
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
            const TextSpan(text: 'You have an active check-in at '),
            TextSpan(
              text: venueName,
              style: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w800,
                decoration: TextDecoration.underline,
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
                        'Share your moments. Catch the vibe.',
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
