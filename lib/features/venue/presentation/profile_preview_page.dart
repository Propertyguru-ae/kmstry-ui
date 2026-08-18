import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

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
  final String? userPhoto;
  final bool isMatchedHint;
  final String? chatIdHint;
  final ProfileActionState? actionStateHint;
  final String? fallbackBio;
  final String? hintVenueId;
  final String? hintVenueName;
  final String? hintVenueType;
  final String? hintVenuePhoto;
  final bool hideVenueInfo;

  const ProfilePreviewPage({
    super.key,
    this.checkinId,
    this.venueId,
    this.userId,
    this.userName,
    this.userUsername,
    this.userPhoto,
    this.isMatchedHint = false,
    this.chatIdHint,
    this.actionStateHint,
    this.fallbackBio,
    this.hintVenueId,
    this.hintVenueName,
    this.hintVenueType,
    this.hintVenuePhoto,
    this.hideVenueInfo = false,
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
  final _venueContextRepository = VenueContextRepository();
  static const Color _darkBg = Color(0xFF0B0F17);
  static const Color _darkSurface = Color(0xFF161C28);
  static const Color _darkBorder = Color(0xFF252D3D);

  CheckinProfile? _profile;
  PublicUserProfile? _publicProfile;
  bool _loading = true;
  ProfileActionState? _actionState;
  String? _resolvedVenueId;

  /// When false: viewer is not at this venue (no active check-in here) -> hide posts & vibe.
  bool _showPostsAndVibe = false;
  bool _showSuggestedForYou = false;
  bool _isBlocked = false;
  bool _isBlocking = false;
  bool _isReporting = false;
  bool _isSendingAction = false;
  int _selectedProfileTab = 0;
  final Map<String, String?> _videoPosterPathByUrl = {};
  final Map<String, Future<String?>> _videoPosterFutureByUrl = {};

  Future<String?> _getVideoPoster(String url) {
    final cached = _videoPosterPathByUrl[url];
    if (cached != null && cached.isNotEmpty) return Future.value(cached);
    final pending = _videoPosterFutureByUrl[url];
    if (pending != null) return pending;
    final future = _generateVideoPoster(url);
    _videoPosterFutureByUrl[url] = future;
    return future;
  }

  Future<String?> _generateVideoPoster(String url) async {
    try {
      final path = await VideoThumbnail.thumbnailFile(
        video: url,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 420,
        quality: 72,
      );
      _videoPosterPathByUrl[url] = path;
      return path;
    } catch (_) {
      _videoPosterPathByUrl[url] = null;
      return null;
    } finally {
      _videoPosterFutureByUrl.remove(url);
    }
  }

  Widget _buildVideoPosterLayer(
    CheckinProfileMedia media, {
    required BoxFit fit,
    double? width,
    double? height,
  }) {
    final thumb = media.thumbnailUrl;
    final hasThumb = thumb != null && thumb.isNotEmpty;
    if (hasThumb) {
      return CachedImage(
        thumb,
        width: width,
        height: height,
        fit: fit,
        errorWidget: (context) => Container(color: Colors.black87),
      );
    }

    return FutureBuilder<String?>(
      future: _getVideoPoster(media.url),
      builder: (context, snap) {
        final localPoster = snap.data;
        if (localPoster != null && localPoster.isNotEmpty) {
          return Image.file(
            File(localPoster),
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) =>
                Container(color: Colors.black87),
          );
        }
        return Container(color: Colors.black87);
      },
    );
  }

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

  String _formatWhatBringsLabel(String raw) {
    final normalized = raw.trim();
    if (normalized.isEmpty) return normalized;
    final parts = normalized
        .split(RegExp(r'[_\s]+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return normalized;
    return parts
        .map(
          (word) =>
              '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
        )
        .join(' ');
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
            _publicProfile = null;
            _resolvedVenueId = resolvedVenueId;
            _actionState = _mergeServerAndLocalActionState(
              serverState: determined,
              localState: localHint,
            );
            _isBlocked = blockedIds.contains(profile.user.id);
            _showPostsAndVibe = showPostsAndVibe;
            _showSuggestedForYou = false;
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
      PublicUserProfile? publicProfile;
      if (targetUserId != null && targetUserId.isNotEmpty) {
        try {
          publicProfile = await _repo.getPublicUserProfile(targetUserId);
          resolvedVenueId =
              publicProfile.activeCheckin?.venueId ?? resolvedVenueId;
        } catch (e) {
          debugPrint('⚠️ public profile fallback unavailable: $e');
        }
      }
      final blockedIds = await _repo.getBlockedUserIds();
      if (!mounted) return;
      setState(() {
        _profile = null;
        _publicProfile = publicProfile;
        _resolvedVenueId = resolvedVenueId;
        _actionState = widget.isMatchedHint
            ? ProfileActionState.matched
            : (_cachedActionStateFor(targetUserId) ??
                  _actionState ??
                  widget.actionStateHint ??
                  ProfileActionState.showActions);
        _isBlocked = targetUserId != null && blockedIds.contains(targetUserId);
        _showPostsAndVibe = false;
        _showSuggestedForYou =
            _actionState != ProfileActionState.matched &&
            widget.checkinId == null &&
            (resolvedVenueId == null || resolvedVenueId.isEmpty);
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

  Future<void> _undoAction() async {
    if (_isSendingAction) return;
    final targetUserId = _profile?.user.id ?? widget.userId;
    if (targetUserId == null || targetUserId.isEmpty) return;

    // ── OPTIMISTIC: anında aksiyon alınabilir duruma dön, network arka planda ──
    final previousState = _actionState;
    setState(() => _actionState = ProfileActionState.showActions);
    _rememberActionState(targetUserId, ProfileActionState.showActions);
    unawaited(SecureStorage.removePendingInterestedUserId(targetUserId));

    try {
      await _repo.undoAction(targetUserId);
    } on ApiException catch (e) {
      // Hata: optimistic durumu geri al ve uygun mesajı göster.
      if (mounted) {
        setState(() => _actionState = previousState);
        _rememberActionState(
          targetUserId,
          previousState ?? ProfileActionState.showActions,
        );
      }
      if (!mounted) return;
      final code = e.data['error']?.toString();
      if (e.statusCode == 403 && code == 'REWIND_LIMIT_REACHED') {
        await PremiumGate.ensure(
          context,
          PremiumFeature.unlimitedRewinds,
          title: 'Out of rewinds today',
          message:
              'You\'ve used all your free rewinds today. Upgrade to KMSTRY+ for unlimited rewinds.',
        );
      } else if (e.statusCode == 409 && code == 'MATCH_EXISTS') {
        await showPremiumErrorDialog(
          context,
          message: 'You have already matched. Use unmatch instead.',
        );
      } else {
        await showPremiumErrorDialog(
          context,
          message: 'Could not undo. Please try again.',
        );
      }
    } catch (e) {
      debugPrint('❌ undo action error: $e');
      if (mounted) {
        setState(() => _actionState = previousState);
        _rememberActionState(
          targetUserId,
          previousState ?? ProfileActionState.showActions,
        );
      }
    }
  }

  Future<void> _handleAction(String action) async {
    if (_isBlocked) {
      return;
    }
    if (_isSendingAction) return;

    final targetUserId = _profile?.user.id ?? widget.userId;
    final venueIdForAction = _resolvedVenueId ?? _profile?.checkin.venueId;
    if (targetUserId == null || targetUserId.isEmpty) return;
    final isAcceptFlow =
        action == 'interested' &&
        _actionState == ProfileActionState.incomingInterested;

    // Only allow actions in showActions or incomingInterested states
    if (_actionState != ProfileActionState.showActions &&
        _actionState != ProfileActionState.incomingInterested) {
      return;
    }

    // ── OPTIMISTIC: UI anında yeni duruma geçer, network arka planda döner ──
    // Böylece butona basınca uzun spinner beklemek yok; hata olursa geri alınır.
    final previousState = _actionState;
    final nextState = action == 'interested'
        ? (isAcceptFlow
              ? ProfileActionState.matched
              : ProfileActionState.waitingResponse)
        : ProfileActionState.proactivePass;

    setState(() {
      _actionState = nextState;
      _isSendingAction = false;
    });
    _rememberActionState(targetUserId, nextState);
    if (action == 'interested' && !isAcceptFlow) {
      unawaited(SecureStorage.addPendingInterestedUserId(targetUserId));
    } else {
      unawaited(SecureStorage.removePendingInterestedUserId(targetUserId));
    }

    // Network'ü arka planda çalıştır; UI'ı bloke etme.
    unawaited(() async {
      try {
        bool isVenueContext = false;
        try {
          final me = await AuthRepository().getMe();
          final contextRaw =
              (me['lastActiveContext'] ?? me['last_active_context'])
                  ?.toString();
          isVenueContext = contextRaw?.toUpperCase() == 'VENUE';
        } catch (_) {
          isVenueContext = false;
        }

        await _repo.sendFeedAction(
          targetUserId: targetUserId,
          venueId: isVenueContext ? venueIdForAction : null,
          action: action,
        );

        // Only "interested" can create a mutual match server-side; sync in bg.
        if (action == 'interested' && mounted) {
          unawaited(_loadProfile());
        }
      } catch (e) {
        debugPrint('❌ feed action error: $e');
        // Hata: optimistic durumu geri al.
        if (mounted) {
          setState(() => _actionState = previousState);
          _rememberActionState(
            targetUserId,
            previousState ?? ProfileActionState.showActions,
          );
        }
      }
    }());
  }

  Future<void> _openChat() async {
    if (_isBlocked) {
      await showPremiumErrorDialog(
        context,
        message: 'User is blocked. Unblock to message.',
      );
      return;
    }

    final profile = _profile;
    debugPrint('🔥 profile: $profile');
    if (profile == null) {
      final userId = widget.userId;
      if (userId == null || userId.isEmpty) {
        await showPremiumErrorDialog(
          context,
          message: 'Chat is not available.',
        );
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
      await showPremiumErrorDialog(
        context,
        message: isMatched
            ? 'Henüz chat açılmadı. İlk mesajı göndererek başlatabilirsin.'
            : 'Henüz chat açılmadı / eşleşme yok.',
      );
    }
  }

  Future<void> _openHintVenueDetail() async {
    final venueId = (_resolvedVenueId ?? widget.hintVenueId ?? '').trim();
    if (venueId.isEmpty) return;
    Venue? venue;
    try {
      final venueData = await _venueContextRepository.getVenueById(venueId);
      final map = Map<String, dynamic>.from(venueData);
      if ((map['id'] == null || map['id'].toString().isEmpty)) {
        map['id'] = venueId;
      }
      if ((map['source'] == null || map['source'].toString().isEmpty)) {
        map['source'] = 'db';
      }
      if ((map['isInDb'] == null) && (map['is_in_db'] == null)) {
        map['isInDb'] = true;
      }
      if ((map['canCheckin'] == null) && (map['can_checkin'] == null)) {
        map['canCheckin'] = true;
      }
      venue = Venue.fromJson(map);
      if (venue.id.isEmpty) venue = null;
    } catch (_) {
      venue = null;
    }
    final resolvedVenue =
        venue ??
        Venue(
          id: venueId,
          name: _previewVenueName(),
          type:
              _publicProfile?.activeCheckin?.venueType ??
              (((widget.hintVenueType ?? '').trim().isNotEmpty)
                  ? widget.hintVenueType!.trim()
                  : 'venue'),
          status: 'Open',
          address: '',
          city: '',
          photoUrl:
              _publicProfile?.activeCheckin?.venuePhoto ??
              (widget.hintVenuePhoto ?? '').trim(),
          latitude: 0.0,
          longitude: 0.0,
          tag: '#NearbyNow',
          source: 'db',
          isInDb: true,
          canCheckin: true,
        );
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: resolvedVenue)),
    );
  }

  bool get _isMatchedActionState => _actionState == ProfileActionState.matched;

  List<CheckinVisitedPlace> get _visitedPlaces =>
      _profile?.visitedPlaces ?? _publicProfile?.visitedPlaces ?? const [];

  Future<void> _toggleBlock() async {
    final targetUserId = _profile?.user.id ?? widget.userId;
    if (targetUserId == null || targetUserId.isEmpty) {
      await showPremiumErrorDialog(context, message: 'User is not available.');
      return;
    }

    if (_isBlocking) return;

    if (!_isBlocked) {
      await _openBlockConfirmDialog(targetUserId);
      return;
    }
    await _openUnblockConfirmDialog(targetUserId);
  }

  Future<void> _openBlockConfirmDialog(String targetUserId) async {
    bool submitting = false;
    bool submitted = false;
    String? submitError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final colors = theme.colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: isDark ? _darkSurface : colors.surface,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark
                      ? _darkBorder.withValues(alpha: 0.9)
                      : colors.outline.withValues(alpha: 0.24),
                ),
              ),
              title: Text(
                submitted ? 'Blocked' : 'Block user?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : colors.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!submitted)
                    Text(
                      "Once blocked, you will no longer see each other in the app and messaging will be paused. Your chat history will stay visible.",
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.86)
                            : colors.onSurface.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  if (submitted)
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This user has been blocked. You will no longer see each other in the app.',
                            style: TextStyle(
                              color: isDark ? Colors.white : colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      submitError!,
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (!submitted) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                setModalState(() {
                                  submitting = true;
                                  submitError = null;
                                });
                                if (mounted) {
                                  setState(() => _isBlocking = true);
                                }
                                try {
                                  await _repo.blockUser(targetUserId);
                                  if (!mounted) return;
                                  setState(() => _isBlocked = true);
                                  setModalState(() {
                                    submitting = false;
                                    submitted = true;
                                  });
                                  await Future<void>.delayed(
                                    const Duration(seconds: 2),
                                  );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                } catch (_) {
                                  setModalState(() {
                                    submitting = false;
                                    submitError = 'Could not block user.';
                                  });
                                } finally {
                                  if (mounted) {
                                    setState(() => _isBlocking = false);
                                  }
                                }
                              },
                        child: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Block'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: submitting
                            ? null
                            : () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: VisualDensity.minimumDensity,
                            vertical: VisualDensity.minimumDensity,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ],
              ),
              actions: const [],
            );
          },
        );
      },
    );
  }

  Future<void> _openUnblockConfirmDialog(String targetUserId) async {
    bool submitting = false;
    bool submitted = false;
    String? submitError;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final isDark = theme.brightness == Brightness.dark;
        final colors = theme.colorScheme;

        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: isDark ? _darkSurface : colors.surface,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 20,
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isDark
                      ? _darkBorder.withValues(alpha: 0.9)
                      : colors.outline.withValues(alpha: 0.24),
                ),
              ),
              title: Text(
                submitted ? 'Unblocked' : 'Unblock user?',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : colors.onSurface,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!submitted)
                    Text(
                      'If you unblock this user, you may be able to see each other again in the app and continue messaging.',
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.86)
                            : colors.onSurface.withValues(alpha: 0.85),
                        height: 1.35,
                      ),
                    ),
                  if (submitted)
                    Row(
                      children: [
                        const Icon(
                          Icons.check_circle_rounded,
                          size: 20,
                          color: Color(0xFF22C55E),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'This user has been unblocked. You may now see each other again in the app.',
                            style: TextStyle(
                              color: isDark ? Colors.white : colors.onSurface,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (submitError != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      submitError!,
                      style: TextStyle(
                        color: colors.error,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (!submitted) ...[
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: submitting
                            ? null
                            : () async {
                                setModalState(() {
                                  submitting = true;
                                  submitError = null;
                                });
                                if (mounted) {
                                  setState(() => _isBlocking = true);
                                }
                                try {
                                  await _repo.unblockUser(targetUserId);
                                  if (!mounted) return;
                                  setState(() => _isBlocked = false);
                                  setModalState(() {
                                    submitting = false;
                                    submitted = true;
                                  });
                                  await Future<void>.delayed(
                                    const Duration(seconds: 2),
                                  );
                                  if (ctx.mounted) Navigator.of(ctx).pop();
                                } catch (_) {
                                  setModalState(() {
                                    submitting = false;
                                    submitError = 'Could not unblock user.';
                                  });
                                } finally {
                                  if (mounted) {
                                    setState(() => _isBlocking = false);
                                  }
                                }
                              },
                        child: submitting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Unblock'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Center(
                      child: TextButton(
                        onPressed: submitting
                            ? null
                            : () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, 32),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: const VisualDensity(
                            horizontal: VisualDensity.minimumDensity,
                            vertical: VisualDensity.minimumDensity,
                          ),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                  ],
                ],
              ),
              actions: const [],
            );
          },
        );
      },
    );
  }

  Future<void> _openReportSheet() async {
    final targetUserId = _profile?.user.id ?? widget.userId;
    if (targetUserId == null || targetUserId.isEmpty) {
      await showPremiumErrorDialog(context, message: 'User is not available.');
      return;
    }
    if (_isReporting) return;

    final options = <({String key, String label})>[
      (key: 'FAKE_PROFILE', label: 'Fake profile'),
      (key: 'INAPPROPRIATE_CONTENT', label: 'Inappropriate content'),
      (key: 'HARASSMENT', label: 'Harassment'),
      (key: 'SPAM_SCAM', label: 'Spam / scam'),
      (key: 'UNDERAGE_ACCOUNT', label: 'Underage account'),
      (key: 'OTHER', label: 'Other'),
    ];

    String selected = options.first.key;
    final otherCtrl = TextEditingController();
    bool submitting = false;
    bool submitted = false;
    String? submitError;

    if (mounted) setState(() => _isReporting = true);
    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final colors = theme.colorScheme;
          final isDark = theme.brightness == Brightness.dark;
          return StatefulBuilder(
            builder: (ctx, setModalState) {
              final isOther = selected == 'OTHER';
              final canSubmit =
                  !submitting && (!isOther || otherCtrl.text.trim().isNotEmpty);
              return Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  MediaQuery.of(ctx).viewInsets.bottom + 16,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? _darkSurface.withValues(alpha: 0.96)
                        : colors.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? _darkBorder.withValues(alpha: 0.9)
                          : colors.outline.withValues(alpha: 0.2),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isDark ? 0.35 : 0.12,
                        ),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colors.onSurface.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (!submitted) ...[
                        Text(
                          'What do you want to report?',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...options.map(
                          (o) => RadioListTile<String>(
                            value: o.key,
                            groupValue: selected,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            activeColor: colors.primary,
                            title: Text(
                              o.label,
                              style: TextStyle(color: colors.onSurface),
                            ),
                            onChanged: submitting
                                ? null
                                : (v) {
                                    if (v == null) return;
                                    setModalState(() => selected = v);
                                  },
                          ),
                        ),
                        if (isOther) ...[
                          const SizedBox(height: 8),
                          TextField(
                            controller: otherCtrl,
                            enabled: !submitting,
                            maxLines: 3,
                            inputFormatters: [
                              LengthLimitingTextInputFormatter(150),
                            ],
                            decoration: const InputDecoration(
                              hintText: 'Help us understand what happened',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => setModalState(() {}),
                          ),
                          const SizedBox(height: 6),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              '${otherCtrl.text.characters.length}/150',
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.onSurface.withValues(alpha: 0.65),
                              ),
                            ),
                          ),
                        ],
                        if (submitError != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            submitError!,
                            style: TextStyle(color: colors.error, fontSize: 13),
                          ),
                        ],
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: canSubmit
                                ? () async {
                                    setModalState(() {
                                      submitting = true;
                                      submitError = null;
                                    });
                                    var reportSucceeded = false;
                                    try {
                                      await _repo.reportUser(
                                        targetUserId: targetUserId,
                                        reason: selected,
                                        details: selected == 'OTHER'
                                            ? otherCtrl.text.trim()
                                            : null,
                                      );
                                      reportSucceeded = true;
                                    } catch (_) {
                                      setModalState(() {
                                        submitting = false;
                                        submitError =
                                            'Could not submit report. Please try again.';
                                      });
                                    }
                                    if (!reportSucceeded) return;

                                    // Report başarılıysa block adımı best-effort:
                                    // block çağrısı hata verse bile kullanıcıya report hatası göstermeyelim.
                                    if (!_isBlocked) {
                                      try {
                                        await _repo.blockUser(targetUserId);
                                      } catch (_) {}
                                      if (mounted) {
                                        setState(() => _isBlocked = true);
                                      }
                                    }
                                    setModalState(() {
                                      submitting = false;
                                      submitted = true;
                                    });
                                  }
                                : null,
                            child: submitting
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: colors.onPrimary,
                                    ),
                                  )
                                : const Text('Report'),
                          ),
                        ),
                      ] else ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: colors.primary.withValues(alpha: 0.32),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.verified_user_rounded,
                                color: Color(0xFF22C55E),
                                size: 20,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Thanks for your report. This user has been blocked automatically, and messaging has been paused for your safety.',
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Done'),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      otherCtrl.dispose();
      if (mounted) setState(() => _isReporting = false);
    }
  }

  Future<void> _openTopActionsSheet() async {
    if (_isReporting || _isBlocking) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final colors = theme.colorScheme;
        final isDark = theme.brightness == Brightness.dark;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? _darkSurface.withValues(alpha: 0.90)
                        : Colors.white.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : colors.onSurface.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.flag_outlined,
                          color: colors.onSurface.withValues(alpha: 0.9),
                        ),
                        title: const Text('Report'),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await _openReportSheet();
                        },
                      ),
                      ListTile(
                        leading: Icon(
                          Icons.block_rounded,
                          color: _isBlocked
                              ? colors.tertiary
                              : colors.onSurface.withValues(alpha: 0.9),
                        ),
                        title: Text(_isBlocked ? 'Unblock' : 'Block'),
                        onTap: () async {
                          Navigator.of(ctx).pop();
                          await _toggleBlock();
                        },
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

  List<CheckinProfileMedia> _mediaForViewer() {
    final media = List<CheckinProfileMedia>.from(_profile!.media);
    if (media.isEmpty) return media;
    final featured = media.firstWhere(
      (m) => m.isFeatured,
      orElse: () => media.first,
    );
    final featuredIndex = media.indexWhere((m) {
      if (featured.id.isNotEmpty && m.id.isNotEmpty) {
        return m.id == featured.id;
      }
      return identical(m, featured);
    });
    if (featuredIndex > 0) {
      final item = media.removeAt(featuredIndex);
      media.insert(0, item);
    }
    return media;
  }

  void _openMediaViewerAt(int index) {
    if (!_showPostsAndVibe || _profile == null || _profile!.media.isEmpty) {
      return;
    }
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
    return Stack(
      fit: StackFit.expand,
      children: [
        _buildVideoPosterLayer(media, fit: fit, width: width, height: height),
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

    final displayName =
        _profile?.user.fullName ??
        _publicProfile?.fullName ??
        widget.userName ??
        'User';
    final displayUsername =
        (_profile?.user.username ??
                _publicProfile?.username ??
                widget.userUsername)
            ?.trim();
    final topBarTitle = displayUsername != null && displayUsername.isNotEmpty
        ? '@${displayUsername.replaceFirst(RegExp(r'^@+'), '')}'
        : displayName;
    final fallbackBio = (widget.fallbackBio ?? '').trim();
    final profileVibe = (_profile?.checkin.vibe ?? '').trim();
    final publicBio = (_publicProfile?.bio ?? '').trim();
    final inlineBio = profileVibe.isNotEmpty
        ? profileVibe
        : (publicBio.isNotEmpty ? publicBio : fallbackBio);
    final checkinWhatBrings = _profile?.checkin.whatBringsToKmstry ?? const [];

    final canOpenVenue =
        (widget.hintVenueId != null && widget.hintVenueId!.trim().isNotEmpty) ||
        (_publicProfile?.activeCheckin?.venueId != null &&
            _publicProfile!.activeCheckin!.venueId!.trim().isNotEmpty) ||
        (_resolvedVenueId != null && _resolvedVenueId!.trim().isNotEmpty);

    // Uygulama geneli tek profil tasarımı — personal profil ile aynı düzen:
    // ortalanmış avatar, altında @username, friends/venues yerine
    // interested/pass action bar, yatay kayan moment'lar. Geri tuşu + üç nokta
    // yerleri korunur.
    final onSurface = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white60 : Colors.black54;
    final avatarUrl = _previewAvatarUrl();
    final moments =
        (_showPostsAndVibe && _profile != null && _profile!.media.isNotEmpty)
        ? _mediaForViewer()
        : <CheckinProfileMedia>[];
    final visitedPlaces = _visitedPlaces;
    final profileContent = <Widget>[
      _buildPreviewAvatar(avatarUrl, isDark),
      const SizedBox(height: 14),
      if (_hasPreviewStats) ...[
        _buildPreviewStats(onSurface, subColor),
        const SizedBox(height: 14),
      ],
      if (!_isMatchedActionState)
        Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                displayName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (_isPreviewVerified) ...[
              const SizedBox(width: 4),
              const Icon(
                Icons.verified,
                color: AppTheme.brandPrimary,
                size: 20,
              ),
            ],
          ],
        ),
      if (_isMatchedActionState) ...[
        const SizedBox(height: 18),
        _buildMatchedMessageButton(),
      ] else if (_actionState != null) ...[
        const SizedBox(height: 18),
        _buildActionBar(),
      ],
      if (_isMatchedActionState) ...[
        const SizedBox(height: 18),
        _buildMatchedProfileInfo(
          displayName: displayName,
          bio: inlineBio,
          onSurface: onSurface,
          subColor: subColor,
        ),
      ] else if (inlineBio.isNotEmpty) ...[
        const SizedBox(height: 18),
        Text(
          inlineBio,
          textAlign: TextAlign.center,
          style: TextStyle(color: onSurface, fontSize: 15, height: 1.4),
        ),
      ],
      if (!widget.hideVenueInfo && _isMatchedActionState) ...[
        const SizedBox(height: 12),
        _buildFriendActiveCheckinRow(
          canOpenVenue: canOpenVenue,
          onSurface: onSurface,
          subColor: subColor,
        ),
      ] else if (!widget.hideVenueInfo && canOpenVenue) ...[
        const SizedBox(height: 12),
        _buildFriendActiveCheckinRow(
          canOpenVenue: true,
          onSurface: onSurface,
          subColor: subColor,
        ),
      ],
      if (_showPostsAndVibe && checkinWhatBrings.isNotEmpty) ...[
        const SizedBox(height: 18),
        SizedBox(
          height: 76,
          child: OverflowBox(
            maxWidth: MediaQuery.sizeOf(context).width,
            maxHeight: 76,
            child: SizedBox(
              width: MediaQuery.sizeOf(context).width,
              height: 76,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.grey[200]!,
                    ),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Text(
                        'What brings you to KMSTRY?',
                        style: TextStyle(
                          color: onSurface.withValues(alpha: 0.76),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: checkinWhatBrings.map((item) {
                          return Container(
                            margin: const EdgeInsets.only(right: 7),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.brandPrimary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: AppTheme.brandPrimary.withValues(
                                  alpha: 0.28,
                                ),
                              ),
                            ),
                            child: Text(
                              _formatWhatBringsLabel(item),
                              style: TextStyle(
                                color: onSurface,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      SizedBox(
        height: (_showPostsAndVibe && checkinWhatBrings.isNotEmpty) ? 0 : 20,
      ),
      SizedBox(
        height: 1,
        child: OverflowBox(
          maxWidth: MediaQuery.sizeOf(context).width,
          maxHeight: 1,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: 1,
            child: ColoredBox(color: onSurface.withValues(alpha: 0.12)),
          ),
        ),
      ),
      const SizedBox(height: 14),
      _buildProfileContentTabs(onSurface, subColor, isDark),
      const SizedBox(height: 16),
      if (_selectedProfileTab == 0) ...[
        _buildMomentsTabContent(
          moments: moments,
          canOpenVenue: canOpenVenue,
          isDark: isDark,
          subColor: subColor,
          onSurface: onSurface,
        ),
        // "Suggested for you" bölümü gizlendi.
        // ignore: dead_code
        if (false && _showSuggestedForYou && moments.isEmpty)
          _buildSuggestedForYou(onSurface, subColor, isDark),
      ] else if (visitedPlaces.isEmpty)
        _buildVisitedPlacesEmptyState(
          isDark: isDark,
          subColor: subColor,
          onSurface: onSurface,
        ),
    ];

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ── TOP BAR: geri (sol) + isim (orta) + üç nokta (sağ) ───────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  const AppBackButton(),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      topBarTitle,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: (_isReporting || _isBlocking)
                        ? null
                        : _openTopActionsSheet,
                    icon: Icon(Icons.more_horiz_rounded, color: onSurface),
                  ),
                ],
              ),
            ),

            Expanded(
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      8,
                      20,
                      _selectedProfileTab == 1 && visitedPlaces.isNotEmpty
                          ? 0
                          : 28,
                    ),
                    sliver: SliverList.list(children: profileContent),
                  ),
                  if (_selectedProfileTab == 1 && visitedPlaces.isNotEmpty)
                    _buildVisitedPlacesSliver(
                      places: visitedPlaces,
                      isDark: isDark,
                      subColor: subColor,
                      onSurface: onSurface,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    if (_isBlocked) {
      return Text(
        'User blocked',
        style: TextStyle(color: subColor, fontSize: 16),
      );
    }

    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_actionState == ProfileActionState.incomingInterested)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  'You caught their attention.',
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            Row(
              children: [
                // PASS — nötr buzlu cam (ikincil, kibar).
                Expanded(
                  child: _GlassActionButton(
                    label: 'Pass',
                    icon: Icons.close_rounded,
                    onTap: () => _handleAction('pass'),
                    isDark: isDark,
                  ),
                ),
                const SizedBox(width: 12),
                // INTERESTED — marka gradyanlı, öne çıkan birincil aksiyon.
                Expanded(
                  child: _BrandActionButton(
                    label: 'Interested',
                    icon: Icons.favorite_rounded,
                    onTap: () => _handleAction('interested'),
                  ),
                ),
              ],
            ),
          ],
        );

      case ProfileActionState.proactivePass:
      case ProfileActionState.reactivePass:
        // Bu iki state zaten "pass benim" demek (proactive: ben pass attım;
        // reactive: onlar interested attıktan sonra ben pass attım). Bu yüzden
        // Undo her zaman gösterilir — optimistic pass'te _profile henüz
        // reload edilmediğinden myActionAtThisVenue'ye güvenmiyoruz.
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'You passed.',
              style: TextStyle(color: subColor, fontSize: 16),
            ),
            const SizedBox(width: 10),
            TextButton.icon(
              onPressed: _isSendingAction ? null : _undoAction,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Undo'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.brandPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
          ],
        );

      case ProfileActionState.waitingResponse:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color(0xFF22C55E),
            ),
            const SizedBox(width: 6),
            const Text(
              'Interest sent',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            // Rewind: henüz match olmadan gönderilen interested geri alınabilir.
            TextButton.icon(
              onPressed: _isSendingAction ? null : _undoAction,
              icon: const Icon(Icons.undo_rounded, size: 18),
              label: const Text('Undo'),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.brandPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
              ),
            ),
          ],
        );

      case ProfileActionState.matched:
        return const SizedBox.shrink();
    }
  }

  Widget _buildMatchedMessageButton() {
    return SizedBox(
      width: 184,
      height: 44,
      child: OutlinedButton.icon(
        onPressed: _openChat,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
        label: const Text('Message'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: AppTheme.brandPrimary,
          side: BorderSide(
            color: AppTheme.brandPrimary.withValues(alpha: 0.62),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }

  Widget _buildMatchedProfileInfo({
    required String displayName,
    required String bio,
    required Color onSurface,
    required Color subColor,
  }) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (_isPreviewVerified) ...[
                const SizedBox(width: 4),
                const Icon(
                  Icons.verified,
                  color: AppTheme.brandPrimary,
                  size: 16,
                ),
              ],
            ],
          ),
          if (bio.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              bio,
              style: TextStyle(color: onSurface, fontSize: 14, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }

  /// Public sosyal istatistikler: arkadaş (match) ve takip edilen venue sayısı.
  /// Sadece rakam gösterilir — başkasının listesine gidilmez.
  Widget _buildPreviewStats(Color onSurface, Color subColor) {
    final friendCount =
        _profile?.user.friendCount ?? _publicProfile?.friendCount;
    final followedVenueCount =
        _profile?.user.followedVenueCount ?? _publicProfile?.followedVenueCount;
    Widget stat(int value, String label) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$value',
            style: TextStyle(
              color: onSurface,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              color: subColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        stat(friendCount ?? 0, 'Friends'),
        const SizedBox(width: 56),
        stat(followedVenueCount ?? 0, 'Venues'),
      ],
    );
  }

  Widget _buildFriendActiveCheckinRow({
    required bool canOpenVenue,
    required Color onSurface,
    required Color subColor,
  }) {
    if (!canOpenVenue) {
      return Align(
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(Icons.location_off_outlined, size: 18, color: subColor),
            const SizedBox(width: 6),
            Text(
              'No active check-in',
              style: TextStyle(color: subColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final venueName = _previewVenueName();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _openHintVenueDetail,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Icon(
                Icons.location_on_rounded,
                size: 18,
                color: AppTheme.brandPrimary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  venueName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.chevron_right_rounded, size: 18, color: subColor),
            ],
          ),
        ),
      ),
    );
  }

  /// Kişinin ilk adı (yoksa tam ad, o da yoksa "They"). "Mehmet şurada" gibi
  /// cümlelerde kullanılır.
  String _previewFirstName() {
    final full =
        (_profile?.user.fullName ?? _publicProfile?.fullName ?? widget.userName)
            ?.trim();
    if (full == null || full.isEmpty) return 'They';
    return full.split(RegExp(r'\s+')).first;
  }

  String _previewVenueName() {
    final hintName = widget.hintVenueName?.trim();
    if (hintName != null && hintName.isNotEmpty) return hintName;
    final publicVenueName = _publicProfile?.activeCheckin?.venueName?.trim();
    if (publicVenueName != null && publicVenueName.isNotEmpty) {
      return publicVenueName;
    }
    return 'Venue';
  }

  Widget _buildProfileContentTabs(
    Color onSurface,
    Color subColor,
    bool isDark,
  ) {
    Widget tab({
      required int index,
      required IconData icon,
      required String label,
    }) {
      final selected = _selectedProfileTab == index;
      return Expanded(
        child: InkWell(
          onTap: () => setState(() => _selectedProfileTab = index),
          borderRadius: BorderRadius.circular(14),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected
                  ? AppTheme.brandPrimary.withValues(
                      alpha: isDark ? 0.22 : 0.14,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? AppTheme.brandPrimary.withValues(alpha: 0.48)
                    : onSurface.withValues(alpha: 0.10),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: selected ? AppTheme.brandPrimary : subColor,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? onSurface : subColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        tab(index: 0, icon: Icons.auto_awesome_rounded, label: 'Moments'),
        const SizedBox(width: 8),
        tab(index: 1, icon: Icons.place_rounded, label: 'Visited Places'),
      ],
    );
  }

  Widget _buildMomentsTabContent({
    required List<CheckinProfileMedia> moments,
    required bool canOpenVenue,
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    if (_showPostsAndVibe && moments.isNotEmpty) {
      return SizedBox(
        height: 176,
        child: OverflowBox(
          maxWidth: MediaQuery.sizeOf(context).width,
          maxHeight: 176,
          child: SizedBox(
            width: MediaQuery.sizeOf(context).width,
            height: 176,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: moments.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (_, index) {
                return SizedBox(
                  width: 132,
                  height: 176,
                  child: _buildMomentImage(
                    moments[index],
                    height: 176,
                    initialIndex: index,
                    borderRadius: 14,
                  ),
                );
              },
            ),
          ),
        ),
      );
    }

    if (!_showPostsAndVibe && canOpenVenue) {
      return _buildFriendDifferentVenueMomentsState(
        isDark: isDark,
        subColor: subColor,
        onSurface: onSurface,
      );
    }

    return _buildFriendNoMomentsState(isDark, subColor);
  }

  Widget _buildVisitedPlacesEmptyState({
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.visibility_off_outlined, size: 46, color: subColor),
            const SizedBox(height: 12),
            Text(
              'Visited places are not shared.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'When they share check-ins on their profile, the latest places will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 13.5, height: 1.3),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitedPlacesSliver({
    required List<CheckinVisitedPlace> places,
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    const tileHeight = 104.0;
    const separatorHeight = 10.0;
    final childCount = places.length * 2 - 1;

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          if (index.isOdd) return const SizedBox(height: separatorHeight);
          final place = places[index ~/ 2];
          return SizedBox(
            height: tileHeight,
            child: _buildVisitedPlaceTile(
              place: place,
              isDark: isDark,
              subColor: subColor,
              onSurface: onSurface,
            ),
          );
        }, childCount: childCount),
      ),
    );
  }

  Widget _buildVisitedPlaceTile({
    required CheckinVisitedPlace place,
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    final hasPhoto = (place.venuePhoto ?? '').trim().isNotEmpty;
    return InkWell(
      onTap: () => _openVisitedVenueDetail(place),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isDark ? _darkSurface : const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: onSurface.withValues(alpha: 0.10)),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 58,
                height: 58,
                child: hasPhoto
                    ? CachedImage(
                        place.venuePhoto!.trim(),
                        fit: BoxFit.cover,
                        errorWidget: (_) =>
                            _buildVisitedPlacePlaceholder(isDark, subColor),
                      )
                    : _buildVisitedPlacePlaceholder(isDark, subColor),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    place.venueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _visitedPlaceSubtitle(place),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _formatVisitedDate(place.checkedInAt),
                    style: TextStyle(color: subColor, fontSize: 12.5),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: subColor, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _buildVisitedPlacePlaceholder(bool isDark, Color subColor) {
    return Container(
      color: isDark ? _darkBorder : const Color(0xFFE9EEF5),
      child: Icon(Icons.place_rounded, color: subColor, size: 28),
    );
  }

  String _visitedPlaceSubtitle(CheckinVisitedPlace place) {
    final type = (place.venueType ?? '').trim();
    if (type.isEmpty) return 'Venue';
    return _formatWhatBringsLabel(type);
  }

  String _formatVisitedDate(DateTime date) {
    final local = date.toLocal();
    if (local.millisecondsSinceEpoch == 0) return '';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '${months[local.month - 1]} ${local.day} · $hour:$minute $period';
  }

  Future<void> _openVisitedVenueDetail(CheckinVisitedPlace place) async {
    final venueId = (place.venueId ?? '').trim();
    if (venueId.isEmpty) return;
    Venue? venue;
    try {
      final venueData = await _venueContextRepository.getVenueById(venueId);
      final map = Map<String, dynamic>.from(venueData);
      if ((map['id'] == null || map['id'].toString().isEmpty)) {
        map['id'] = venueId;
      }
      if ((map['source'] == null || map['source'].toString().isEmpty)) {
        map['source'] = 'db';
      }
      if ((map['isInDb'] == null) && (map['is_in_db'] == null)) {
        map['isInDb'] = true;
      }
      if ((map['canCheckin'] == null) && (map['can_checkin'] == null)) {
        map['canCheckin'] = true;
      }
      venue = Venue.fromJson(map);
      if (venue.id.isEmpty) venue = null;
    } catch (_) {
      venue = null;
    }
    final resolvedVenue =
        venue ??
        Venue(
          id: venueId,
          name: place.venueName,
          type: place.venueType ?? 'venue',
          status: 'Open',
          address: '',
          city: '',
          photoUrl: (place.venuePhoto ?? '').trim(),
          latitude: 0.0,
          longitude: 0.0,
          tag: '#Visited',
          source: 'db',
          isInDb: true,
          canCheckin: true,
        );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => VenueDetailPage(venue: resolvedVenue)),
    );
  }

  Widget _buildFriendNoMomentsState(bool isDark, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.camera_alt_outlined, size: 48, color: subColor),
            const SizedBox(height: 12),
            Text(
              'No moments yet',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Moments will appear here when you are at the same venue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendDifferentVenueMomentsState({
    required bool isDark,
    required Color subColor,
    required Color onSurface,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: subColor),
            const SizedBox(height: 12),
            Text(
              '${_previewFirstName()} is at ${_previewVenueName()}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'To catch the live vibe and see their moments, join them at the same venue.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 13.5, height: 1.3),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _openHintVenueDetail,
                icon: const Icon(Icons.location_on_rounded, size: 18),
                label: const Text('View venue'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(140, 42),
                  backgroundColor: AppTheme.brandPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Preview avatar için fotoğraf URL'i. Kullanıcının gerçek profil fotoğrafı
  /// varsa o kalıcı olarak kullanılır (featured/check-in avatarı ezmez). Profil
  /// fotoğrafı yoksa: featured check-in fotoğrafı → ilk check-in fotoğrafı →
  /// hint → null (person icon).
  String? _previewAvatarUrl() {
    // Önce gerçek profil fotoğrafı — varsa featured/check-in avatarına bakma.
    final profilePhotoFirst = _profile?.user.photo?.trim();
    if (profilePhotoFirst != null && profilePhotoFirst.isNotEmpty) {
      return profilePhotoFirst;
    }
    final publicProfilePhotoFirst = _publicProfile?.photo?.trim();
    if (publicProfilePhotoFirst != null && publicProfilePhotoFirst.isNotEmpty) {
      return publicProfilePhotoFirst;
    }

    final checkinAvatar = _profile?.checkin.avatarPhoto?.trim();
    if (checkinAvatar != null && checkinAvatar.isNotEmpty) {
      return checkinAvatar;
    }
    final publicCheckinAvatar = _publicProfile?.activeCheckin?.avatarPhoto
        ?.trim();
    if (publicCheckinAvatar != null && publicCheckinAvatar.isNotEmpty) {
      return publicCheckinAvatar;
    }
    final photos =
        _profile?.media
            .where((m) => m.mediaType == MediaType.photo && m.url.isNotEmpty)
            .toList() ??
        const <CheckinProfileMedia>[];
    if (photos.isNotEmpty) {
      final featured = photos.firstWhere(
        (m) => m.isFeatured,
        orElse: () => photos.first,
      );
      return featured.url;
    }
    final profilePhoto = _profile?.user.photo?.trim();
    if (profilePhoto != null && profilePhoto.isNotEmpty) {
      return profilePhoto;
    }
    final publicProfilePhoto = _publicProfile?.photo?.trim();
    if (publicProfilePhoto != null && publicProfilePhoto.isNotEmpty) {
      return publicProfilePhoto;
    }
    // Fallback modu (aktif check-in yok, _profile null): açan ekranın geçtiği
    // profil fotoğrafını kullan (ör. username aramasından).
    final hintPhoto = widget.userPhoto?.trim();
    if (hintPhoto != null && hintPhoto.isNotEmpty) {
      return hintPhoto;
    }
    return null;
  }

  bool get _hasPreviewStats => _profile != null || _publicProfile != null;

  bool get _isPreviewVerified =>
      _profile?.user.isVerified == true || _publicProfile?.isVerified == true;

  /// Ortalanmış, karemsi (radius 32) avatar — personal profil ile aynı dil.
  Widget _buildPreviewAvatar(String? url, bool isDark) {
    const size = 128.0;
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: SizedBox(
          width: size,
          height: size,
          child: url != null
              ? CachedImage(
                  url,
                  fit: BoxFit.cover,
                  errorWidget: (_) => _previewAvatarFallback(isDark),
                )
              : _previewAvatarFallback(isDark),
        ),
      ),
    );
  }

  Widget _previewAvatarFallback(bool isDark) {
    return Container(
      color: isDark ? _darkSurface : const Color(0xFFEDEFF3),
      child: Icon(
        Icons.person,
        size: 56,
        color: isDark ? Colors.white38 : Colors.black26,
      ),
    );
  }

  Widget _buildMomentImage(
    CheckinProfileMedia media, {
    double? width,
    required double height,
    required int initialIndex,
    double borderRadius = 20,
  }) {
    final constrainedChild = SizedBox(
      width: width,
      height: height,
      child: media.mediaType == MediaType.photo
          ? CachedImage(media.url, fit: BoxFit.cover)
          : _buildVideoCover(media: media, fit: BoxFit.cover, iconSize: 30),
    );

    return GestureDetector(
      onTap: () {
        _openMediaViewerAt(initialIndex);
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: constrainedChild,
      ),
    );
  }

  /// Instagram tarzı "Suggested for you" — içeriği olmayan profillerde alttaki
  /// boşluğu dolduran, yatay kayan büyük persona öneri kartları (mock).
  Widget _buildSuggestedForYou(Color onSurface, Color subColor, bool isDark) {
    const personas = _kSuggestedPersonas;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Suggested for you',
              style: TextStyle(
                color: onSurface,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              'See all',
              style: TextStyle(
                color: AppColors.blue,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          height: 250,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.zero,
            itemCount: personas.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, index) {
              final p = personas[index];
              return _SuggestedPersonaCard(
                persona: p,
                isDark: isDark,
                onTap: () => _openPersonaProfile(p),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  void _openPersonaProfile(_SuggestedPersona persona) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          userId: persona.id,
          userName: persona.fullName,
          userUsername: persona.username,
          userPhoto: persona.photo,
        ),
      ),
    );
  }
}

/// Suggested for you için mock persona verisi.
class _SuggestedPersona {
  const _SuggestedPersona({
    required this.id,
    required this.fullName,
    required this.username,
    required this.photo,
  });

  final String id;
  final String fullName;
  final String username;
  final String photo;
}

const List<_SuggestedPersona> _kSuggestedPersonas = [
  _SuggestedPersona(
    id: 'persona_ayla',
    fullName: 'Ayla Toprak',
    username: 'ayla_tprk',
    photo: 'https://i.pravatar.cc/300?img=47',
  ),
  _SuggestedPersona(
    id: 'persona_nurtac',
    fullName: 'Nurtaç Kaya',
    username: 'tcnurtackaya',
    photo: 'https://i.pravatar.cc/300?img=32',
  ),
  _SuggestedPersona(
    id: 'persona_deniz',
    fullName: 'Deniz Mutlu',
    username: 'denizdekibalik',
    photo: 'https://i.pravatar.cc/300?img=12',
  ),
  _SuggestedPersona(
    id: 'persona_selin',
    fullName: 'Selin Aydın',
    username: 'selin.ayd',
    photo: 'https://i.pravatar.cc/300?img=45',
  ),
  _SuggestedPersona(
    id: 'persona_mert',
    fullName: 'Mert Yıldırım',
    username: 'mrt.yldrm',
    photo: 'https://i.pravatar.cc/300?img=15',
  ),
];

/// Büyük, kibar persona öneri kartı — foto + full name + username; basınca
/// o profile gider.
class _SuggestedPersonaCard extends StatelessWidget {
  const _SuggestedPersonaCard({
    required this.persona,
    required this.isDark,
    required this.onTap,
  });

  final _SuggestedPersona persona;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cardColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.03);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final onSurface = isDark ? Colors.white : Colors.black;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 168,
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 14),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppColors.magenta.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
              child: ClipOval(
                child: CachedImage(
                  persona.photo,
                  fit: BoxFit.cover,
                  errorWidget: (_) => Container(
                    color: isDark ? Colors.white12 : const Color(0xFFEDEFF3),
                    child: Icon(
                      Icons.person,
                      size: 44,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              persona.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '@${persona.username}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: subColor, fontSize: 13),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: 140,
              height: 34,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  gradient: const LinearGradient(
                    colors: [AppColors.magenta, AppColors.blue],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Text(
                    'View profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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

/// Marka gradyanlı, öne çıkan birincil aksiyon butonu (Interested).
/// Uygulama geneli gradient (magenta→blue) + yumuşak gölge — kibar ve belirgin.
class _BrandActionButton extends StatelessWidget {
  const _BrandActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          height: 54,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              colors: [AppColors.magenta, AppColors.blue],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.magenta.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: Colors.white, size: 19),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
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

/// Nötr buzlu cam ikincil buton (Pass). Şeffaf yüzey + blur + ince kenarlık —
/// uygulama geneli glassmorphism dili.
class _GlassActionButton extends StatelessWidget {
  const _GlassActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isDark,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : Colors.black87;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Material(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 54,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: fg.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, color: fg.withValues(alpha: 0.85), size: 19),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: fg,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
