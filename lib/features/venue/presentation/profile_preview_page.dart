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
  static const Color _darkBg = Color(0xFF0B0F17);
  static const Color _darkSurface = Color(0xFF161C28);
  static const Color _darkBorder = Color(0xFF252D3D);
  static const Color _darkPrimary = Color(0xFF4DA3FF);
  static const Color _darkPrimary2 = Color(0xFF2563EB);
  bool _isVibeExpanded = false;
  bool _isVibeOverflowing = false;
  bool _areMomentsExpanded = false;

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
      maxLines: 3,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    return textPainter.didExceedMaxLines;
  }

  Future<void> _loadProfile() async {
    try {
      bool showPostsAndVibe = false;
      String? resolvedVenueId = widget.venueId;
      final shouldCheckActive =
          (widget.checkinId != null && widget.checkinId!.isNotEmpty) ||
          (widget.venueId != null && widget.venueId!.isNotEmpty);
      final active = shouldCheckActive
          ? await _venueRepo.getActiveCheckin()
          : null;
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
          final sameVenueAsCheckin =
              profileVenueId != null &&
              profileVenueId.isNotEmpty &&
              active != null &&
              active.isActive &&
              active.venueId == profileVenueId;
          final sameVenueFallback =
              (profileVenueId == null || profileVenueId.isEmpty) &&
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
        const SnackBar(
          content: Text('Bu profile şu an yeni aksiyon gönderilemez.'),
        ),
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
                ? (isAcceptFlow ? 'Kmstry accepted.' : 'Interested gönderildi.')
                : 'Not Kmstry gönderildi.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('❌ feed action error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aksiyon gönderilemedi. Lütfen tekrar dene.'),
        ),
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
    debugPrint('🔥 profile: $profile');
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
    if (!_showPostsAndVibe || _profile == null || _profile!.media.isEmpty)
      return;
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF111827), Color(0xFF0B0F17)],
        ),
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
                color: _darkPrimary.withValues(alpha: 0.22),
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
                color: _darkPrimary2.withValues(alpha: 0.18),
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
    final displayUsername = (_profile?.user.username ?? widget.userUsername)
        ?.trim();

    final age = _profile != null
        ? (DateTime.now().year - _profile!.user.birthdate.year)
        : null;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
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
                      ? Colors.black.withValues(alpha: 0.18)
                      : Colors.black.withOpacity(0.16),
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
                    isDark ? _darkBg : Colors.black.withOpacity(0.92),
                    isDark
                        ? Colors.black.withValues(alpha: 0.48)
                        : Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.4, 0.8],
                ),
              ),
            ),
          ),

          /// CONTENT
          CustomScrollView(
            // Kullanıcı scroll etmesin; içerik toggle ile konumlansın.
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: ClipOval(
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                      child: Container(
                        color: isDark
                            ? _darkSurface.withValues(alpha: 0.72)
                            : Colors.black.withOpacity(0.3),
                        child: IconButton(
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ),
                ),
                actions: [
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          color: isDark
                              ? _darkSurface.withValues(alpha: 0.72)
                              : Colors.black.withOpacity(0.3),
                          child: TextButton(
                            onPressed: _isBlocking ? null : _toggleBlock,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              disabledForegroundColor: Colors.white54,
                            ),
                            child: Text(_isBlocked ? 'Unblock' : 'Block'),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                // Kapalı durumda içerik aşağıda kalsın (resim daha çok görünsün),
                // moments açılınca üst boşluk azalır ve içerik yukarı kayar.
                expandedHeight:
                    MediaQuery.of(context).size.height *
                    (_areMomentsExpanded ? 0.30 : 0.56),
                flexibleSpace: const FlexibleSpaceBar(
                  background: SizedBox.shrink(),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    20,
                    _areMomentsExpanded ? 0 : 6,
                    20,
                    _areMomentsExpanded ? 28 : 80,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// NAME & AGE
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              '$displayName${age != null ? ', $age' : ''}',
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -1,
                              ),
                            ),
                          ),
                          if (_profile?.user.isVerified == true)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8, left: 4),
                              child: Icon(
                                Icons.verified,
                                color: Colors.blue,
                                size: 24,
                              ),
                            ),
                        ],
                      ),

                      /// USERNAME
                      if (displayUsername != null && displayUsername.isNotEmpty)
                        Text(
                          '@$displayUsername',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withOpacity(0.7),
                            fontWeight: FontWeight.w500,
                          ),
                        ),

                      const SizedBox(height: 16),

                      /// ACTIONS (Kmstry, Not Kmstry, etc.)
                      if (_actionState != null) _buildActionBar(),

                      const SizedBox(height: 24),

                      /// VIBE CARD
                      if (_showPostsAndVibe &&
                          _profile != null &&
                          _profile!.checkin.vibe != null &&
                          _profile!.checkin.vibe!.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(24),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                            child: Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? _darkSurface.withValues(alpha: 0.56)
                                    : Colors.white.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(24),
                                border: Border.all(
                                  color: isDark
                                      ? _darkBorder.withValues(alpha: 0.9)
                                      : Colors.white.withOpacity(0.15),
                                ),
                              ),
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final vibeText = _profile!.checkin.vibe!;
                                  final style = const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.5,
                                    fontStyle: FontStyle.italic,
                                  );

                                  _isVibeOverflowing = _checkTextOverflow(
                                    vibeText,
                                    constraints.maxWidth,
                                    style,
                                  );

                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(
                                        Icons.format_quote_rounded,
                                        color: Colors.white54,
                                        size: 24,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        vibeText,
                                        style: style,
                                        maxLines: _isVibeExpanded ? null : 3,
                                        overflow: _isVibeExpanded
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                      ),
                                      if (_isVibeOverflowing)
                                        GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              _isVibeExpanded =
                                                  !_isVibeExpanded;
                                            });
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: Text(
                                              _isVibeExpanded
                                                  ? 'See less'
                                                  : 'See more',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                decoration:
                                                    TextDecoration.underline,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 8),

                      /// RECENT MOMENTS (toggle)
                      if (_showPostsAndVibe && moments.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                _areMomentsExpanded = !_areMomentsExpanded;
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _areMomentsExpanded
                                        ? 'Close moments'
                                        : 'See moments',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Icon(
                                    _areMomentsExpanded
                                        ? Icons.keyboard_arrow_up_rounded
                                        : Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        AnimatedSize(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeInOut,
                          child: _areMomentsExpanded
                              ? Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 180,
                                      child: ListView.separated(
                                        scrollDirection: Axis.horizontal,
                                        physics: const BouncingScrollPhysics(),
                                        itemCount: moments.length,
                                        separatorBuilder: (context, index) =>
                                            const SizedBox(width: 12),
                                        itemBuilder: (_, index) {
                                          return Container(
                                            width: 130,
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withOpacity(0.2),
                                                  blurRadius: 10,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: _buildMomentImage(
                                              moments[index],
                                              height: 180,
                                              initialIndex: index + 1,
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                )
                              : const SizedBox.shrink(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    final theme = Theme.of(context);

    if (_isBlocked) {
      return Text(
        'User blocked',
        style: const TextStyle(color: Colors.white70, fontSize: 16),
      );
    }

    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_actionState == ProfileActionState.incomingInterested)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Kmstry you! What do you think?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 40,
                  child: OutlinedButton(
                    onPressed: _isSendingAction
                        ? null
                        : () => _handleAction('interested'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: const Text('Kmstry 👋'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: _isSendingAction
                        ? null
                        : () => _handleAction('pass'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Not Kmstry'),
                  ),
                ),
              ],
            ),
          ],
        );

      case ProfileActionState.proactivePass:
      case ProfileActionState.reactivePass:
        return const Text(
          'No Kmstry already',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        );

      case ProfileActionState.waitingResponse:
        return const Text(
          'Waiting response',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        );

      case ProfileActionState.matched:
        return SizedBox(
          height: 40,
          child: ElevatedButton(
            onPressed: _openChat,
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(
                horizontal: VisualDensity.minimumDensity,
                vertical: VisualDensity.minimumDensity,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
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
        borderRadius: BorderRadius.circular(20),
        child: constrainedChild,
      ),
    );
  }
}
