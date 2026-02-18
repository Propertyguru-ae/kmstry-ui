import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';

enum ProfileActionState {
  showActions,
  incomingInterested,
  waitingResponse,
  proactivePass,
  reactivePass,
  matched,
}

class ProfilePreviewPage extends StatefulWidget {
  final String checkinId;
  final String venueId;

  const ProfilePreviewPage({
    super.key,
    required this.checkinId,
    required this.venueId,
  });

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage> {
  final _repo = CheckinRepository();
  final _venueRepo = VenueCheckinRepository();
  bool _isVibeExpanded = false;
  bool _isVibeOverflowing = false;

  CheckinProfile? _profile;
  bool _loading = true;
  ProfileActionState? _actionState;

  /// When false: viewer is not at this venue (no active check-in here) -> hide posts & vibe.
  bool _showPostsAndVibe = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  bool _checkTextOverflow(String text, double maxWidth, TextStyle style) {
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 2,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _repo.getCheckinProfile(widget.checkinId);
      if (!mounted) return;

      bool showPostsAndVibe = false;
      try {
        final active = await _venueRepo.getActiveCheckin();
        if (active != null &&
            active.isActive &&
            active.venueId == widget.venueId) {
          showPostsAndVibe = true;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _actionState = _determineActionState(profile);
        _showPostsAndVibe = showPostsAndVibe;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ profile load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  ProfileActionState _determineActionState(CheckinProfile profile) {
    final myAction = profile.myActionAtThisVenue;
    final theirAction = profile.theirActionAtThisVenue;

    // 1) GLOBAL MATCH
    if (profile.isMatched) {
      return ProfileActionState.matched;
    }

    // 2) THEY SENT INTERESTED
    if (theirAction == 'interested') {
      if (myAction == 'interested') {
        return ProfileActionState.matched;
      }

      if (myAction == 'pass') {
        // Check timestamps to determine if pass was sent BEFORE or AFTER interested
        final myActionTime = profile.myActionCreatedAt;
        final theirActionTime = profile.theirActionCreatedAt;

        // Only hard lock if pass was sent AFTER receiving interested
        if (myActionTime != null &&
            theirActionTime != null &&
            myActionTime.isAfter(theirActionTime)) {
          // Reactive pass: I sent pass AFTER they sent interested (hard lock)
          return ProfileActionState.reactivePass;
        }

        // Proactive pass: I sent pass BEFORE they sent interested
        // Show incomingInterested so user can respond
        return ProfileActionState.incomingInterested;
      }

      return ProfileActionState.incomingInterested;
    }

    // 3) I SENT INTERESTED, WAITING
    if (myAction == 'interested') {
      // If they responded with PASS AFTER my interested → hard reject
      if (theirAction == 'pass' &&
          profile.theirActionCreatedAt != null &&
          profile.myActionCreatedAt != null &&
          profile.theirActionCreatedAt!.isAfter(profile.myActionCreatedAt!)) {
        return ProfileActionState.reactivePass;
      }

      // Otherwise still waiting
      return ProfileActionState.waitingResponse;
    }

    // 4) I SENT PASS (SOFT)
    if (myAction == 'pass') {
      return ProfileActionState.proactivePass;
    }

    // 5) NOTHING YET
    return ProfileActionState.showActions;
  }

  Future<void> _handleAction(String action) async {
    debugPrint("🔥 ACTION SENT: $action");

    if (_profile == null) return;

    // Only allow actions in showActions or incomingInterested states
    if (_actionState != ProfileActionState.showActions &&
        _actionState != ProfileActionState.incomingInterested) {
      return;
    }

    try {
      await _repo.sendFeedAction(
        targetUserId: _profile!.user.id,
        venueId: widget.venueId,
        //checkinId: widget.checkinId,
        action: action,
      );
      if (!mounted) return;

      // Reload profile to get updated state
      await _loadProfile();
    } catch (e) {
      debugPrint('❌ feed action error: $e');
    }
  }

  Future<void> _openChat() async {
    final profile = _profile;
    if (profile == null) return;

    debugPrint('🧪 OPEN CHAT → chatId = ${profile.chatId}');

    if (profile.chatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ChatId gelmedi (backend kontrol et)')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: profile.chatId!,
          otherUserId: profile.user.id,
          otherName: profile.user.fullName,
          otherPhotoUrl: (() {
            final first = profile.media.first;
            if (first.mediaType == MediaType.photo) return first.url;
            return first.thumbnailUrl ?? '';
          })(),
        ),
      ),
    );
  }

  List<CheckinProfileMedia> _mediaForViewer() {
    final featured = _profile!.media.firstWhere(
      (m) => m.isFeatured,
      orElse: () => _profile!.media.first,
    );
    final moments = _profile!.media.where((m) => !m.isFeatured).toList();
    return [featured, ...moments];
  }

  void _openMediaViewerAt(int index) {
    final mediaForViewer = _mediaForViewer();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MomentsViewerPage(
          media: mediaForViewer,
          initialIndex: index,
          allowFeature: false,
        ),
      ),
    );
  }

  Widget _buildVideoCover({
    required CheckinProfileMedia media,
    BoxFit fit = BoxFit.cover,
    double? width,
    double? height,
    double iconSize = 42,
  }) {
    final thumbnail = media.thumbnailUrl;
    final hasThumbnail = thumbnail != null && thumbnail.isNotEmpty;

    return Stack(
      fit: StackFit.expand,
      children: [
        if (hasThumbnail)
          Image.network(
            thumbnail,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (_, __, ___) => Container(color: Colors.black87),
          )
        else
          Container(color: Colors.black87),
        Center(
          child: Icon(
            Icons.play_circle_fill,
            color: Colors.white,
            size: iconSize,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    /// LOADING STATE
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.white)),
      );
    }

    /// ERROR / EMPTY STATE
    if (_profile == null) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Text(
            'Profile unavailable',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final featuredMedia = _profile!.media.firstWhere(
      (m) => m.isFeatured,
      orElse: () => _profile!.media.first,
    );

    final moments = _profile!.media.where((p) => !p.isFeatured).toList();

    return Scaffold(
      body: Stack(
        children: [
          /// HERO MEDIA (FEATURED)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _openMediaViewerAt(0),
              child: featuredMedia.mediaType == MediaType.photo
                  ? Image.network(
                      featuredMedia.url,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.black,
                        child: const Icon(
                          Icons.person,
                          color: Colors.white70,
                          size: 48,
                        ),
                      ),
                    )
                  : _buildVideoCover(
                      media: featuredMedia,
                      fit: BoxFit.cover,
                      iconSize: 60,
                    ),
            ),
          ),

          /// DARK GRADIENT
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [Colors.black87, Colors.transparent],
                ),
              ),
            ),
          ),

          /// CONTENT
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /// BACK
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),

                const Spacer(),

                /// NAME
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    _profile!.user.fullName,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                /// ONLINE STATUS
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Online now',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),

                const SizedBox(height: 12),

                /// VIBE (only when viewer is at same venue)
                if (_showPostsAndVibe &&
                    _profile!.checkin.vibe != null &&
                    _profile!.checkin.vibe!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final vibeText = _profile!.checkin.vibe!;
                        const style = TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        );

                        _isVibeOverflowing = _checkTextOverflow(
                          vibeText,
                          constraints.maxWidth,
                          style,
                        );

                        return AnimatedSize(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                vibeText,
                                style: style,
                                maxLines: _isVibeExpanded ? null : 2,
                                overflow: _isVibeExpanded
                                    ? TextOverflow.visible
                                    : TextOverflow.ellipsis,
                              ),

                              if (_isVibeOverflowing)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _isVibeExpanded = !_isVibeExpanded;
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _isVibeExpanded ? 'See less' : 'See more',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 16),

                /// RECENT MOMENTS (only when viewer is at same venue)
                if (_showPostsAndVibe && moments.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Recent moments',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                if (_showPostsAndVibe && moments.isNotEmpty)
                  const SizedBox(height: 8),

                if (_showPostsAndVibe && moments.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Builder(
                      builder: (context) {
                        final count = moments.length;

                        // 🔥 1 FOTO
                        if (count == 1) {
                          return _buildMomentImage(
                            moments.first,
                            width: double.infinity,
                            height: 160,
                            initialIndex: 1,
                          );
                        }

                        // 🔥 2 FOTO
                        if (count == 2) {
                          return Row(
                            children: [
                              Expanded(
                                child: _buildMomentImage(
                                  moments[0],
                                  height: 140,
                                  initialIndex: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _buildMomentImage(
                                  moments[1],
                                  height: 140,
                                  initialIndex: 2,
                                ),
                              ),
                            ],
                          );
                        }

                        // 🔥 3+ FOTO (scroll)
                        return SizedBox(
                          height: 90,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: count,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (_, index) {
                              return _buildMomentImage(
                                moments[index],
                                width: 70,
                                height: 90,
                                initialIndex: index + 1,
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),

                const SizedBox(height: 90),
              ],
            ),
          ),

          /// ACTION BAR
          if (_actionState != null)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: _buildActionBarContainer(),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBarContainer() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.black.withOpacity(0.85)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner for incomingInterested
          if (_actionState == ProfileActionState.incomingInterested)
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: const Center(
                child: Text(
                  'Kmstry you! What do you think?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // Action buttons/content
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleAction('interested'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: const BorderSide(color: Colors.white),
                ),
                child: const Text('Kmstry 👋'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () => _handleAction('pass'),
                child: const Text('Not Kmstry'),
              ),
            ),
          ],
        );

      case ProfileActionState.proactivePass:
      case ProfileActionState.reactivePass:
        return const Center(
          child: Text(
            'No Kmstry already',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        );

      case ProfileActionState.waitingResponse:
        return const Center(
          child: Text(
            'Waiting response',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
        );

      case ProfileActionState.matched:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _openChat,
            child: const Text('Message'),
          ),
        );
    }
  }

  Widget _buildMomentImage(
    CheckinProfileMedia media, {
    double? width,
    required double height,
    required int initialIndex,
  }) {
    final constrainedChild = SizedBox(
      width: width,
      height: height,
      child: media.mediaType == MediaType.photo
          ? Image.network(
              media.url,
              fit: BoxFit.cover,
            )
          : _buildVideoCover(
              media: media,
              fit: BoxFit.cover,
              iconSize: 30,
            ),
    );

    return GestureDetector(
      onTap: () {
        _openMediaViewerAt(initialIndex);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: constrainedChild,
      ),
    );
  }
}
