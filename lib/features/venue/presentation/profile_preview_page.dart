import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
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
  static final Map<String, ProfileActionState> _actionStateCacheByUserId = {};

  static void clearActionStateCache() {
    _actionStateCacheByUserId.clear();
  }

  static ProfileActionState? peekCachedActionState(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    return _actionStateCacheByUserId[userId];
  }

  final String? checkinId;
  final String? venueId;
  final String? userId;
  final String? userName;
  final String? userUsername;
  final bool isMatchedHint;
  final String? chatIdHint;
  final ProfileActionState? actionStateHint;

  const ProfilePreviewPage({
    super.key,
    this.checkinId,
    this.venueId,
    this.userId,
    this.userName,
    this.userUsername,
    this.isMatchedHint = false,
    this.chatIdHint,
    this.actionStateHint,
  }) : assert(
         checkinId != null || userId != null,
         'Either checkinId or userId must be provided.',
       );

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage> {
  final _repo = CheckinRepository();
  final _matchRepo = MatchRepository();
  final _venueRepo = VenueCheckinRepository();
  bool _isVibeExpanded = false;
  bool _isVibeOverflowing = false;

  CheckinProfile? _profile;
  bool _loading = true;
  ProfileActionState? _actionState;
  String? _resolvedVenueId;

  /// When false: viewer is not at this venue (no active check-in here) -> hide posts & vibe.
  bool _showPostsAndVibe = false;
  bool _isBlocked = false;
  bool _isBlocking = false;
  bool _isSendingAction = false;

  ProfileActionState? _cachedActionStateFor(String? userId) {
    return ProfilePreviewPage.peekCachedActionState(userId);
  }

  void _rememberActionState(String? userId, ProfileActionState state) {
    if (userId == null || userId.isEmpty) return;
    ProfilePreviewPage._actionStateCacheByUserId[userId] = state;
  }

  Future<void> _syncPendingInterestedState(
    String? userId,
    ProfileActionState state,
  ) async {
    if (userId == null || userId.isEmpty) return;
    if (state == ProfileActionState.waitingResponse) {
      await SecureStorage.addPendingInterestedUserId(userId);
      return;
    }
    await SecureStorage.removePendingInterestedUserId(userId);
  }

  ProfileActionState _mergeServerAndLocalActionState({
    required ProfileActionState serverState,
    ProfileActionState? localState,
  }) {
    // Prevent temporary stale backend states from downgrading a local matched state.
    if (localState == ProfileActionState.matched &&
        serverState != ProfileActionState.matched) {
      return localState!;
    }

    // Keep optimistic/local UX state when backend still returns "showActions"
    // due to eventual consistency or venue-independent action flow.
    if (serverState == ProfileActionState.showActions &&
        localState != null &&
        localState != ProfileActionState.showActions) {
      return localState;
    }
    return serverState;
  }

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
      bool showPostsAndVibe = false;
      String? resolvedVenueId = widget.venueId;
      final shouldCheckActive = (widget.checkinId != null && widget.checkinId!.isNotEmpty) ||
          (widget.venueId != null && widget.venueId!.isNotEmpty);
      final active = shouldCheckActive ? await _venueRepo.getActiveCheckin() : null;
      if (resolvedVenueId == null || resolvedVenueId.isEmpty) {
        resolvedVenueId = active?.venueId;
      }

      final checkinId = widget.checkinId;
      if (checkinId != null && checkinId.isNotEmpty) {
        try {
          final profile = await _repo.getCheckinProfile(checkinId);
          // Prefer API check-in venue (DB UUID). Caller may pass Google [Venue.id] as venueId — do not use that for gating.
          final profileVenueId = profile.checkin.venueId;
          if (profileVenueId != null && profileVenueId.isNotEmpty) {
            resolvedVenueId = profileVenueId;
          } else {
            resolvedVenueId ??= active?.venueId;
          }
          final sameVenueAsCheckin = profileVenueId != null &&
              profileVenueId.isNotEmpty &&
              active != null &&
              active.isActive &&
              active.venueId == profileVenueId;
          final sameVenueFallback = (profileVenueId == null ||
                  profileVenueId.isEmpty) &&
              active != null &&
              active.isActive &&
              resolvedVenueId != null &&
              resolvedVenueId.isNotEmpty &&
              active.venueId == resolvedVenueId;
          if (sameVenueAsCheckin || sameVenueFallback) {
            showPostsAndVibe = true;
          }
          if (!mounted) return;
          final blockedIds = await _repo.getBlockedUserIds();
          if (!mounted) return;
          setState(() {
            final determined = _determineActionState(profile);
            final localHint =
                _cachedActionStateFor(profile.user.id) ??
                widget.actionStateHint ??
                _actionState;
            _profile = profile;
            _resolvedVenueId = resolvedVenueId;
            _actionState = _mergeServerAndLocalActionState(
              serverState: determined,
              localState: localHint,
            );
            _isBlocked = blockedIds.contains(profile.user.id);
            _showPostsAndVibe = showPostsAndVibe;
            _loading = false;
          });
          _rememberActionState(profile.user.id, _actionState!);
          await _syncPendingInterestedState(profile.user.id, _actionState!);
          return;
        } catch (e) {
          // If checkin profile is unavailable (expired/deleted), still allow opening by user fallback.
          debugPrint('⚠️ checkin profile fallback to user mode: $e');
        }
      }

      if (!mounted) return;
      final targetUserId = widget.userId;
      final blockedIds = await _repo.getBlockedUserIds();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _resolvedVenueId = resolvedVenueId;
        _actionState = widget.isMatchedHint
            ? ProfileActionState.matched
            : (_cachedActionStateFor(targetUserId) ??
                  _actionState ??
                  widget.actionStateHint ??
                  ProfileActionState.showActions);
        _isBlocked = targetUserId != null && blockedIds.contains(targetUserId);
        _showPostsAndVibe = false;
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
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unblock user to send actions.')),
      );
      return;
    }

    if (_isSendingAction) return;

    debugPrint("🔥 ACTION SENT: $action");

    final targetUserId = _profile?.user.id ?? widget.userId;
    final venueId = _resolvedVenueId ?? _profile?.checkin.venueId;
    if (targetUserId == null || targetUserId.isEmpty) return;
    final isAcceptFlow =
        action == 'interested' &&
        _actionState == ProfileActionState.incomingInterested;

    // Only allow actions in showActions or incomingInterested states
    if (_actionState != ProfileActionState.showActions &&
        _actionState != ProfileActionState.incomingInterested) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu profile şu an yeni aksiyon gönderilemez.')),
      );
      return;
    }

    try {
      setState(() => _isSendingAction = true);
      await _repo.sendFeedAction(
        targetUserId: targetUserId,
        venueId: venueId,
        //checkinId: widget.checkinId,
        action: action,
      );
      if (!mounted) return;

      // Optimistic state update to immediately disable action buttons.
      final nextState = action == 'interested'
          ? (isAcceptFlow
                ? ProfileActionState.matched
                : ProfileActionState.waitingResponse)
          : ProfileActionState.proactivePass;
      setState(() {
        _actionState = nextState;
      });
      _rememberActionState(targetUserId, nextState);
      if (action == 'interested' && !isAcceptFlow) {
        await SecureStorage.addPendingInterestedUserId(targetUserId);
      } else {
        await SecureStorage.removePendingInterestedUserId(targetUserId);
      }

      // Best effort reload profile to sync authoritative server state.
      await _loadProfile();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'interested'
                ? (isAcceptFlow
                      ? 'Kmstry accepted.'
                      : 'Interested gönderildi.')
                : 'Not Kmstry gönderildi.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ feed action error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aksiyon gönderilemedi. Lütfen tekrar dene.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isSendingAction = false);
      }
    }
  }

  Future<void> _openChat() async {
    if (_isBlocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User is blocked. Unblock to message.')),
      );
      return;
    }

    final profile = _profile;
    if (profile == null) {
      final userId = widget.userId;
      if (userId == null || userId.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Chat is not available.')));
        return;
      }
      String? fallbackChatId = widget.chatIdHint;
      try {
        fallbackChatId ??= await _matchRepo.getChatIdForUser(userId);
      } catch (_) {}
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            chatId: fallbackChatId,
            otherUserId: userId,
            otherName: widget.userName ?? 'User',
            otherPhotoUrl: '',
          ),
        ),
      );
      return;
    }

    String? resolvedChatId = profile.chatId;
    if ((resolvedChatId == null || resolvedChatId.isEmpty) &&
        profile.user.id.isNotEmpty) {
      try {
        resolvedChatId = await _matchRepo.getChatIdForUser(profile.user.id);
      } catch (_) {}
    }
    final isMatched = profile.isMatched;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: resolvedChatId,
          otherUserId: profile.user.id,
          otherName: profile.user.fullName,
          otherPhotoUrl: (() {
            if (profile.media.isEmpty) return '';
            final first = profile.media.first;
            if (first.mediaType == MediaType.photo) return first.url;
            return first.thumbnailUrl ?? '';
          })(),
        ),
      ),
    );
    if ((resolvedChatId == null || resolvedChatId.isEmpty) && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMatched
                ? 'Henüz chat açılmadı. İlk mesajı göndererek başlatabilirsin.'
                : 'Henüz chat açılmadı / eşleşme yok.',
          ),
        ),
      );
    }
  }

  Future<void> _toggleBlock() async {
    final targetUserId = _profile?.user.id ?? widget.userId;
    if (targetUserId == null || targetUserId.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User is not available.')));
      return;
    }

    if (_isBlocking) return;

    setState(() => _isBlocking = true);
    try {
      if (_isBlocked) {
        await _repo.unblockUser(targetUserId);
      } else {
        await _repo.blockUser(targetUserId);
      }
      if (!mounted) return;
      setState(() => _isBlocked = !_isBlocked);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isBlocked ? 'Could not unblock user.' : 'Could not block user.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
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
    if (!_showPostsAndVibe || _profile == null || _profile!.media.isEmpty) return;
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
            errorBuilder: (context, error, stackTrace) =>
                Container(color: Colors.black87),
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

  Widget _buildEmptyGradientBackground(bool isDark) {
    if (!isDark) {
      // Light mode must stay clean white.
      return Container(color: Colors.white);
    }

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            left: -80,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF1FE4D2).withValues(alpha: 0.25),
              ),
            ),
          ),

          Positioned(
            bottom: -120,
            right: -80,
            child: Container(
              width: 350,
              height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFF6B4A).withValues(alpha: 0.18),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    /// LOADING STATE
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    final hasFallbackProfile = widget.userId != null || widget.userName != null;

    /// ERROR / EMPTY STATE
    if (_profile == null && !hasFallbackProfile) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: Center(
          child: Text(
            'Profile unavailable',
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
        ),
      );
    }

    final hasMedia = _profile != null && _profile!.media.isNotEmpty;
    final canShowMedia = _showPostsAndVibe && hasMedia;
    final featuredMedia = canShowMedia
        ? _profile!.media.firstWhere(
            (m) => m.isFeatured,
            orElse: () => _profile!.media.first,
          )
        : null;

    final moments = canShowMedia
        ? _profile!.media.where((p) => !p.isFeatured).toList()
        : <CheckinProfileMedia>[];
    final displayName = _profile?.user.fullName ?? widget.userName ?? 'User';
    final displayUsername =
        (_profile?.user.username ?? widget.userUsername)?.trim();
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          /// HERO MEDIA (FEATURED)
          Positioned.fill(
            child: GestureDetector(
              onTap: canShowMedia ? () => _openMediaViewerAt(0) : null,
              child: !canShowMedia
                  ? Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildEmptyGradientBackground(isDark),
                        Center(
                          child: Icon(
                            Icons.person,
                            color: isDark ? Colors.white70 : Colors.black45,
                            size: 48,
                          ),
                        ),
                      ],
                    )
                  : featuredMedia!.mediaType == MediaType.photo
                  ? Image.network(
                      featuredMedia.url,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: theme.colorScheme.surface,
                        child: Center(
                          child: Icon(
                            Icons.person,
                            color: isDark ? Colors.white70 : Colors.black45,
                            size: 48,
                          ),
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

          /// ProfilePage ile ayni blur + gradient katmani
          if (!canShowMedia)
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                child: Container(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.2)
                      : Colors.white.withValues(alpha: 0.2),
                ),
              ),
            ),

          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    isDark ? Colors.black : Colors.white,
                    isDark
                        ? Colors.black.withValues(alpha: 0.4)
                        : Colors.white.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.8],
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        onPressed: () => Navigator.pop(context),
                      ),
                      TextButton(
                        onPressed: _isBlocking ? null : _toggleBlock,
                        style: TextButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : Colors.black87,
                          disabledForegroundColor: isDark
                              ? Colors.white54
                              : Colors.black38,
                        ),
                        child: Text(_isBlocked ? 'Unblock' : 'Block'),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                /// NAME
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    displayName,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                /// USERNAME
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    (displayUsername != null && displayUsername.isNotEmpty)
                        ? '@$displayUsername'
                        : '',
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                /// VIBE (only when viewer is at same venue)
                if (_showPostsAndVibe &&
                    _profile != null &&
                    _profile!.checkin.vibe != null &&
                    _profile!.checkin.vibe!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final vibeText = _profile!.checkin.vibe!;
                        final style = TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
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
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : theme.colorScheme.primary,
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
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'Recent moments',
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
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
                            separatorBuilder: (context, index) =>
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isDark ? Colors.black : theme.colorScheme.surface).withValues(
          alpha: 0.85,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Banner for incomingInterested
          if (_actionState == ProfileActionState.incomingInterested)
            Container(
              padding: const EdgeInsets.only(bottom: 12),
              child: Center(
                child: Text(
                  'Kmstry you! What do you think?',
                  style: TextStyle(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (_isBlocked) {
      return Center(
        child: Text(
          'User blocked',
          style: TextStyle(
            color: isDark ? Colors.white70 : theme.colorScheme.onSurface,
            fontSize: 16,
          ),
        ),
      );
    }

    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isSendingAction
                    ? null
                    : () => _handleAction('interested'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                  side: BorderSide(
                    color: isDark ? Colors.white : theme.colorScheme.onSurface,
                  ),
                ),
                child: const Text('Kmstry 👋'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _isSendingAction ? null : () => _handleAction('pass'),
                child: const Text('Not Kmstry'),
              ),
            ),
          ],
        );

      case ProfileActionState.proactivePass:
      case ProfileActionState.reactivePass:
        return Center(
          child: Text(
            'No Kmstry already',
            style: TextStyle(
              color: isDark ? Colors.white70 : theme.colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        );

      case ProfileActionState.waitingResponse:
        return Center(
          child: Text(
            'Waiting response',
            style: TextStyle(
              color: isDark ? Colors.white70 : theme.colorScheme.onSurface,
              fontSize: 16,
            ),
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
          ? Image.network(media.url, fit: BoxFit.cover)
          : _buildVideoCover(media: media, fit: BoxFit.cover, iconSize: 30),
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
