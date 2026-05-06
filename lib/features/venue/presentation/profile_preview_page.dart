import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';

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
  final String? fallbackBio;
  final String? hintVenueId;
  final String? hintVenueName;
  final String? hintVenueType;
  final String? hintVenuePhoto;

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
    this.fallbackBio,
    this.hintVenueId,
    this.hintVenueName,
    this.hintVenueType,
    this.hintVenuePhoto,
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
  static const Color _darkPrimary = AppTheme.brandPrimary;
  static const Color _darkPrimary2 = AppTheme.brandPrimary;
  bool _areMomentsExpanded = false;

  CheckinProfile? _profile;
  bool _loading = true;
  ProfileActionState? _actionState;
  String? _resolvedVenueId;

  /// When false: viewer is not at this venue (no active check-in here) -> hide posts & vibe.
  bool _showPostsAndVibe = false;
  bool _isBlocked = false;
  bool _isBlocking = false;
  bool _isReporting = false;
  bool _isSendingAction = false;
  String? _sendingActionType;

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
    final venueIdForAction = _resolvedVenueId ?? _profile?.checkin.venueId;
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
      setState(() {
        _isSendingAction = true;
        _sendingActionType = action;
      });
      bool isVenueContext = false;
      try {
        final me = await AuthRepository().getMe();
        final contextRaw =
            (me['lastActiveContext'] ?? me['last_active_context'])?.toString();
        isVenueContext = contextRaw?.toUpperCase() == 'VENUE';
      } catch (_) {
        // Context okunamazsa güvenli varsayım: PERSONAL gibi davran.
        isVenueContext = false;
      }

      await _repo.sendFeedAction(
        targetUserId: targetUserId,
        venueId: isVenueContext ? venueIdForAction : null,
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
      if (action != 'interested') {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Not Kmstry gönderildi.')));
      }
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
        setState(() {
          _isSendingAction = false;
          _sendingActionType = null;
        });
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

  Future<void> _openHintVenueDetail() async {
    final venueId = (widget.hintVenueId ?? _resolvedVenueId ?? '').trim();
    if (venueId.isEmpty) return;
    final venue = Venue(
      id: venueId,
      name: ((widget.hintVenueName ?? '').trim().isNotEmpty)
          ? widget.hintVenueName!.trim()
          : 'Venue',
      type: ((widget.hintVenueType ?? '').trim().isNotEmpty)
          ? widget.hintVenueType!.trim()
          : 'venue',
      status: 'Open',
      address: '',
      city: '',
      photoUrl: (widget.hintVenuePhoto ?? '').trim(),
      latitude: 0.0,
      longitude: 0.0,
      tag: '#NearbyNow',
      source: 'db',
      isInDb: true,
      canCheckin: true,
    );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)));
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
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
                      "Once blocked, you will no longer see each other in the app and your conversation will be closed.",
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
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User is not available.')));
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
                                  'Thanks for your report. This user has been blocked automatically, and your chat has been closed for your safety.',
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

  Future<void> _openBioVibeSheet(String text, bool isDark) async {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final sheetTitleColor = isDark ? Colors.white : Colors.black;
    final sheetBodyColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : Colors.black.withValues(alpha: 0.88);
    final sheetActionColor = isDark ? Colors.white : Colors.black;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? _darkSurface.withValues(alpha: 0.95)
                    : colors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: isDark
                      ? _darkBorder.withValues(alpha: 0.92)
                      : colors.outline.withValues(alpha: 0.22),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.1),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Padding(
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
                          color: Colors.white.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'About',
                      style: TextStyle(
                        color: sheetTitleColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(ctx).size.height * 0.45,
                      ),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Text(
                          text,
                          style: TextStyle(
                            color: sheetBodyColor,
                            fontSize: 16,
                            height: 1.5,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Text(
                          'See less',
                          style: TextStyle(
                            color: sheetActionColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
    final canShowHeroMedia = hasMedia;
    final canShowMoments = _showPostsAndVibe && hasMedia;
    final featuredMedia = canShowHeroMedia
        ? _profile!.media.firstWhere(
            (m) => m.isFeatured,
            orElse: () => _profile!.media.first,
          )
        : null;

    final moments = canShowMoments
        ? _profile!.media.where((p) => !p.isFeatured).toList()
        : <CheckinProfileMedia>[];
    final displayName = _profile?.user.fullName ?? widget.userName ?? 'User';
    final displayUsername = (_profile?.user.username ?? widget.userUsername)
        ?.trim();
    final fallbackBio = (widget.fallbackBio ?? '').trim();
    final profileVibe = (_profile?.checkin.vibe ?? '').trim();
    final inlineBio = profileVibe.isNotEmpty ? profileVibe : fallbackBio;

    final canOpenVenue =
        (widget.hintVenueId != null && widget.hintVenueId!.trim().isNotEmpty) ||
        (_resolvedVenueId != null && _resolvedVenueId!.trim().isNotEmpty);

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Stack(
        fit: StackFit.expand,
        children: [
          /// HERO MEDIA (FEATURED)
          Positioned.fill(
            child: GestureDetector(
              onTap: canShowMoments ? () => _openMediaViewerAt(0) : null,
              child: !canShowHeroMedia
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
          if (!canShowHeroMedia)
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
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                            child: Container(
                              color: isDark
                                  ? _darkSurface.withValues(alpha: 0.72)
                                  : Colors.black.withOpacity(0.3),
                              child: TextButton(
                                onPressed: _isReporting
                                    ? null
                                    : _openReportSheet,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  disabledForegroundColor: Colors.white54,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: const VisualDensity(
                                    horizontal: VisualDensity.minimumDensity,
                                    vertical: VisualDensity.minimumDensity,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(
                                  _isReporting ? 'Reporting...' : 'Report',
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
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
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                  minimumSize: const Size(0, 40),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: const VisualDensity(
                                    horizontal: VisualDensity.minimumDensity,
                                    vertical: VisualDensity.minimumDensity,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: Text(_isBlocked ? 'Unblock' : 'Block'),
                              ),
                            ),
                          ),
                        ),
                      ],
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
                      if (canOpenVenue) ...[
                        OutlinedButton.icon(
                          onPressed: _openHintVenueDetail,
                          icon: const Icon(Icons.place_outlined, size: 15),
                          label: const Text('Venue'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                            backgroundColor: Colors.black.withValues(
                              alpha: 0.22,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            minimumSize: const Size(0, 34),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            visualDensity: const VisualDensity(
                              horizontal: -1,
                              vertical: -1,
                            ),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],

                      /// NAME
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
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
                                color: AppTheme.brandPrimary,
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

                      /// ABOUT CARD (vibe > bio): check-in olsa da olmasa da aynı premium görünüm.
                      if (inlineBio.isNotEmpty)
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
                                  final vibeText = inlineBio;
                                  final style = const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    height: 1.5,
                                    fontStyle: FontStyle.italic,
                                  );

                                  final isVibeOverflowing = _checkTextOverflow(
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (isVibeOverflowing)
                                        GestureDetector(
                                          onTap: () {
                                            _openBioVibeSheet(vibeText, isDark);
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              top: 12,
                                            ),
                                            child: Text(
                                              'See more',
                                              style: TextStyle(
                                                color: isDark
                                                    ? Colors.white
                                                    : const Color.fromARGB(
                                                        255,
                                                        250,
                                                        250,
                                                        250,
                                                      ),
                                                fontWeight: FontWeight.bold,
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
    if (_isBlocked) {
      return Text(
        'User blocked',
        style: const TextStyle(color: Colors.white70, fontSize: 16),
      );
    }

    switch (_actionState!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        if (_isSendingAction && _sendingActionType == 'interested') {
          return const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.1,
                  color: AppTheme.brandPrimary,
                ),
              ),
              SizedBox(width: 8),
              Text(
                'Request sending...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          );
        }
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
                  height: 52,
                  child: OutlinedButton(
                    onPressed: _isSendingAction
                        ? null
                        : () => _handleAction('interested'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: const Size(0, 52),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0.5,
                    ),
                    child: const Text('Kmstry 👋'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSendingAction
                        ? null
                        : () => _handleAction('pass'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      minimumSize: const Size(0, 52),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: const VisualDensity(
                        horizontal: VisualDensity.minimumDensity,
                        vertical: VisualDensity.minimumDensity,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
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
        return const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color(0xFF22C55E),
            ),
            SizedBox(width: 6),
            Text(
              'Request sent',
              style: TextStyle(
                color: Color(0xFF22C55E),
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case ProfileActionState.matched:
        return SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _openChat,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              minimumSize: const Size(0, 52),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: const VisualDensity(
                horizontal: VisualDensity.minimumDensity,
                vertical: VisualDensity.minimumDensity,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
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
