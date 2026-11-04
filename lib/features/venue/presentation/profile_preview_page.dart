import '../../people/data/friendship_changes.dart';
import '../../people/data/match_item_model.dart';
import '../../people/presentation/block_user_dialog.dart';
import '../../people/presentation/remove_friend_dialog.dart';
import '../../people/presentation/user_actions_sheet.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/daily_undo_quota.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_profile_model.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_ring_painter.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/moments_viewer_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:video_thumbnail/video_thumbnail.dart';

enum _UndoPhase { idle, awaitingConfirmation, optimistic }

enum ProfileActionState {
  showActions,
  incomingInterested,
  waitingResponse,
  proactivePass,
  reactivePass,
  matched,
}

/// Mekanın story grupları içinden [userId]'nin avatarında gösterilecek grubu
/// döner: yalnızca yayınlanmış (yükleniyor placeholder'ı olmayan) story'ler;
/// hiç yoksa null (halka çizilmez).
@visibleForTesting
StoryGroup? profileStoryGroupFor(List<StoryGroup> groups, String userId) {
  for (final group in groups) {
    if (group.user.id != userId) continue;
    final stories = group.stories
        .where((s) => !s.isUploadingPlaceholder)
        .toList();
    if (stories.isEmpty) return null;
    return StoryGroup(
      user: group.user,
      stories: stories,
      featuredPhotoUrl: group.featuredPhotoUrl,
    );
  }
  return null;
}

class ProfilePreviewPage extends StatefulWidget {
  static final Map<String, ProfileActionState> _actionStateCacheByUserId = {};
  static int _actionCacheRevision = 0;
  static int _actionSession = -1;

  static void clearActionStateCache() {
    _actionStateCacheByUserId.clear();
  }

  static ProfileActionState? peekCachedActionState(String? userId) {
    if (userId == null || userId.isEmpty) return null;
    if (_actionCacheRevision != FriendshipChanges.revision ||
        _actionSession != SecureStorage.sessionRevision) {
      _actionStateCacheByUserId.clear();
      _actionCacheRevision = FriendshipChanges.revision;
      _actionSession = SecureStorage.sessionRevision;
    }
    return _actionStateCacheByUserId[userId];
  }

  final String? checkinId;
  final String? venueId;
  final String? userId;
  final String? userName;
  final String? userUsername;
  final String? userPhoto;
  final bool isMatchedHint;
  final ({String id, DateTime version})? interestNotice;
  final String? chatIdHint;
  final ProfileActionState? actionStateHint;
  final String? fallbackBio;
  final String? hintVenueId;
  final String? hintVenueName;
  final String? hintVenueType;
  final String? hintVenuePhoto;
  final bool hideVenueInfo;
  final CheckinRepository? checkinRepository;
  final MatchRepository? matchRepository;

  const ProfilePreviewPage({
    super.key,
    this.checkinId,
    this.venueId,
    this.userId,
    this.userName,
    this.userUsername,
    this.userPhoto,
    this.isMatchedHint = false,
    this.interestNotice,
    this.chatIdHint,
    this.actionStateHint,
    this.fallbackBio,
    this.hintVenueId,
    this.hintVenueName,
    this.hintVenueType,
    this.hintVenuePhoto,
    this.hideVenueInfo = false,
    this.checkinRepository,
    this.matchRepository,
  }) : assert(
         checkinId != null || userId != null,
         'Either checkinId or userId must be provided.',
       );

  @override
  State<ProfilePreviewPage> createState() => _ProfilePreviewPageState();
}

class _ProfilePreviewPageState extends State<ProfilePreviewPage>
    with WidgetsBindingObserver {
  late final _repo = widget.checkinRepository ?? CheckinRepository();
  late final _matchRepo = widget.matchRepository ?? MatchRepository();
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
  bool _isBlocked = false;
  // Karşı taraf BENİ blokladıysa true. Backend, iki yönlü blokta profili 403
  // (`Profile unavailable`) ile reddeder — bunu yakalayıp mesaj butonunu iki
  // taraf için de inaktif yapmakta kullanıyoruz. (_isBlocked = ben blokladım.)
  bool _blockedByOther = false;
  // Profil sunucuda yok (404): hesap askıya alınmış (ban) ya da silinmiş.
  // Listeden gelen ad/foto ile sahte profil gösterilmez.
  bool _profileUnavailable = false;
  // Kullanıcının bu mekandaki aktif story'leri (varsa avatarda halka).
  StoryGroup? _storyGroup;
  final Set<String> _viewedStoryIds = {};
  bool _isBlocking = false;
  bool _isReporting = false;
  bool _removingFriend = false;
  bool _ignoreMatchedHint = false;
  MatchItem? _friendship;
  int _friendshipRequest = 0;
  int _profileRequest = 0;
  bool _checkingFriendship = true;
  Future<void>? _pendingSend;
  bool get _isSendingAction => _pendingSend != null;
  _UndoPhase _undoPhase = _UndoPhase.idle;
  bool get _undoing => _undoPhase != _UndoPhase.idle;
  ({String action, Future<void> Function() submit})? _afterUndo;
  ProfileActionState? get _visibleAction {
    if (_undoPhase != _UndoPhase.optimistic || !_hasUndoableAction) {
      return _actionState;
    }
    return switch (_afterUndo?.action) {
      'interested' => ProfileActionState.waitingResponse,
      'pass' => ProfileActionState.proactivePass,
      _ => ProfileActionState.showActions,
    };
  }

  bool _hasCheckedFriendship = false;
  bool get _hasUndoableAction =>
      _actionState == ProfileActionState.waitingResponse ||
      _actionState == ProfileActionState.proactivePass ||
      _actionState == ProfileActionState.reactivePass;
  bool _interestUnavailable = false;
  int _acceptRequest = 0;
  Timer? _slowAcceptTimer;
  bool _accepting = false;
  bool _retryAccept = false;
  bool _openingChat = false;
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
    // Apply session invalidation before writing a newly confirmed state.
    ProfilePreviewPage.peekCachedActionState(userId);
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
    // A profile snapshot must not undo an accepted interest. The dedicated
    // friendship lookup below confirms removals once the write has finished.
    if (localState == ProfileActionState.matched) return localState!;
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
    WidgetsBinding.instance.addObserver(this);
    FriendshipChanges.changes.addListener(_onFriendshipChanged);
    _warmUndoQuota();
    _loadProfile();
  }

  @override
  void dispose() {
    _slowAcceptTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    FriendshipChanges.changes.removeListener(_onFriendshipChanged);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _warmUndoQuota();
      unawaited(_loadProfile());
    }
  }

  void _onFriendshipChanged() {
    final change = FriendshipChanges.changes.value;
    if (!mounted || change == null) return;
    ProfilePreviewPage._actionStateCacheByUserId.remove(change.userId);
    if (change.userId.isNotEmpty &&
        change.userId != (_profile?.user.id ?? widget.userId)) {
      return;
    }
    _ignoreMatchedHint = true;
    setState(() {
      // Reconnect asks for revalidation; it does not mean friendship ended.
      if (change.userId.isNotEmpty) {
        _friendship = change.active ? change.friendship ?? _friendship : null;
        if (!change.active || change.friendship != null) {
          _slowAcceptTimer?.cancel();
          ++_acceptRequest;
          _accepting = false;
        }
        _retryAccept = false;
        _interestUnavailable = !change.active && widget.interestNotice != null;
        _afterUndo = null;
        _actionState = change.active
            ? ProfileActionState.matched
            : ProfileActionState.showActions;
      }
      _storyGroup = null;
    });
    if (change.active && change.friendship != null) {
      ++_profileRequest;
      ++_friendshipRequest;
      _checkingFriendship = false;
      _rememberActionState(change.userId, ProfileActionState.matched);
      if (!_loading) return;
    }
    unawaited(_loadProfile());
  }

  Future<void> _refreshFriendship() async {
    final userId = _profile?.user.id ?? widget.userId;
    if (userId == null ||
        _profileUnavailable ||
        _blockedByOther ||
        _isSendingAction ||
        _undoing) {
      if (mounted) setState(() => _checkingFriendship = false);
      return;
    }
    final request = ++_friendshipRequest;
    final profileRequest = _profileRequest;
    bool isCurrent() =>
        mounted &&
        request == _friendshipRequest &&
        profileRequest == _profileRequest;
    setState(() => _checkingFriendship = true);
    try {
      final friendship = await _matchRepo.getFriendship(userId);
      if (!isCurrent()) return;
      setState(() {
        _friendship = friendship;
        _ignoreMatchedHint = true;
        if (friendship != null) {
          _actionState = ProfileActionState.matched;
        } else if (_actionState == ProfileActionState.matched) {
          if (widget.interestNotice != null) _interestUnavailable = true;
          _actionState = ProfileActionState.showActions;
        }
      });
      if (_actionState != null) _rememberActionState(userId, _actionState!);
    } catch (_) {
      // Do not offer a destructive action without an authoritative version.
      if (isCurrent()) {
        setState(() => _friendship = null);
      }
    } finally {
      if (isCurrent()) {
        setState(() {
          _hasCheckedFriendship = true;
          _checkingFriendship = false;
        });
      }
    }
  }

  Future<void> _removeFriend() async {
    final friendship = _friendship;
    if (_removingFriend || friendship == null) return;
    setState(() => _removingFriend = true);
    try {
      final name =
          _profile?.user.fullName ??
          _publicProfile?.fullName ??
          widget.userName ??
          'this person';
      if (!await confirmRemoveFriend(context, name) || !mounted) return;
      await _matchRepo.removeFriend(friendship);
      if (mounted) showFriendRemovedNotice(context);
    } catch (_) {
      if (mounted) showRemoveFriendFailedNotice(context);
      unawaited(_refreshFriendship());
    } finally {
      if (mounted) setState(() => _removingFriend = false);
    }
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
    if (_undoing || _accepting || (_isSendingAction && _hasUndoableAction)) {
      return;
    }
    final request = ++_profileRequest;
    ++_friendshipRequest;
    bool isCurrent() => mounted && request == _profileRequest;
    setState(() => _checkingFriendship = true);
    // Profil fetch'i 403 (`Profile unavailable`) dönerse iki yönlü blok vardır;
    // ben bloklamadıysam karşı taraf beni bloklamış demektir.
    bool blockedByOther = false;
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
          if (widget.interestNotice != null &&
              widget.userId != profile.user.id) {
            throw StateError('Check-in no longer identifies this requester');
          }
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
          if (!isCurrent()) return;
          final blockedIds = await _repo.getBlockedUserIds();
          if (!isCurrent()) return;
          setState(() {
            final determined = _determineActionState(profile);
            final localHint =
                _actionState ??
                (widget.interestNotice != null
                    ? ProfileActionState.incomingInterested
                    : null) ??
                _cachedActionStateFor(profile.user.id) ??
                widget.actionStateHint;
            _profile = profile;
            _publicProfile = null;
            _resolvedVenueId = resolvedVenueId;
            _actionState = _mergeServerAndLocalActionState(
              serverState: determined,
              localState: localHint,
            );
            _isBlocked = blockedIds.contains(profile.user.id);
            _blockedByOther = false;
            _showPostsAndVibe = showPostsAndVibe;
            _loading = false;
          });
          unawaited(_loadUserStories());
          _rememberActionState(profile.user.id, _actionState!);
          await _syncPendingInterestedState(profile.user.id, _actionState!);
          return;
        } catch (e) {
          // 403 → iki yönlü blok (karşı taraf beni bloklamış olabilir). Diğer
          // hatalar (expired/deleted checkin) fallback user mode ile devam eder.
          if (e is ApiException && e.statusCode == 403) blockedByOther = true;
          debugPrint('⚠️ checkin profile fallback to user mode: $e');
        }
      }

      if (!isCurrent()) return;
      final targetUserId = widget.userId;
      PublicUserProfile? publicProfile;
      var profileUnavailable = false;
      if (targetUserId != null && targetUserId.isNotEmpty) {
        try {
          publicProfile = await _repo.getPublicUserProfile(targetUserId);
          resolvedVenueId =
              publicProfile.activeCheckin?.venueId ?? resolvedVenueId;
        } catch (e) {
          // 403 → iki yönlü blok: karşı taraf beni bloklamış (ben bloklasaydım
          // _isBlocked zaten yakalıyor). Mesaj butonunu inaktif yapmak için işaretle.
          if (e is ApiException && e.statusCode == 403) blockedByOther = true;
          // 404 → hesap askıya alınmış ya da silinmiş.
          if (e is ApiException && e.statusCode == 404) {
            profileUnavailable = true;
          }
          debugPrint('⚠️ public profile fallback unavailable: $e');
        }
      }
      final blockedIds = await _repo.getBlockedUserIds();
      if (!isCurrent()) return;
      setState(() {
        _profile = null;
        _publicProfile = publicProfile;
        _resolvedVenueId = resolvedVenueId;
        _actionState = widget.isMatchedHint && !_ignoreMatchedHint
            ? ProfileActionState.matched
            : (_actionState ??
                  (widget.interestNotice != null
                      ? ProfileActionState.incomingInterested
                      : null) ??
                  _cachedActionStateFor(targetUserId) ??
                  widget.actionStateHint ??
                  ProfileActionState.showActions);
        _isBlocked = targetUserId != null && blockedIds.contains(targetUserId);
        _blockedByOther = blockedByOther;
        _profileUnavailable = profileUnavailable;
        _showPostsAndVibe = false;
        _loading = false;
      });
      unawaited(_loadUserStories());
    } catch (e) {
      debugPrint('❌ profile load error: $e');
      if (!isCurrent()) return;
      setState(() => _loading = false);
    } finally {
      if (isCurrent()) {
        await _refreshFriendship();
      }
    }
  }

  /// Kullanıcının check-in yaptığı mekandaki aktif story'leri. Story'ler
  /// mekan bazlı geldiği için mekan bağlamı (Who's here vb.) gerekir; yoksa ya
  /// da engelleme varsa halka gösterilmez. Hata halka için sessizce yutulur.
  Future<void> _loadUserStories() async {
    final revision = FriendshipChanges.revision;
    final userId = (_profile?.user.id ?? widget.userId ?? '').trim();
    final venueId =
        (_resolvedVenueId ??
                _profile?.checkin.venueId ??
                widget.hintVenueId ??
                '')
            .trim();
    if (userId.isEmpty || venueId.isEmpty || _isBlocked || _blockedByOther) {
      if (_storyGroup != null && mounted) setState(() => _storyGroup = null);
      return;
    }
    try {
      final groups = await StoryRepository().getVenueStories(venueId);
      if (!mounted || revision != FriendshipChanges.revision) return;
      final match = profileStoryGroupFor(groups, userId);
      setState(() => _storyGroup = match);
    } catch (e) {
      debugPrint('⚠️ profile stories unavailable: $e');
    }
  }

  bool _isStorySeen(StoryItem story) =>
      story.viewedByMe || _viewedStoryIds.contains(story.id);

  bool get _hasUnseenStory =>
      _storyGroup?.stories.any((s) => !_isStorySeen(s)) ?? false;

  Future<void> _openUserStories() async {
    final group = _storyGroup;
    if (group == null) return;
    // İlk izlenmemiş story'den başla; hepsi izlendiyse baştan.
    final firstUnseen = group.stories.indexWhere((s) => !_isStorySeen(s));
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: [group],
          initialStoryIndex: firstUnseen < 0 ? 0 : firstUnseen,
        ),
      ),
    );
    if (!mounted) return;
    if (result is StoryViewerResult && result.lastStoryIndex >= 0) {
      final seen = result.allFinished
          ? group.stories.map((s) => s.id)
          : [
              for (
                var i = 0;
                i <= result.lastStoryIndex && i < group.stories.length;
                i++
              )
                group.stories[i].id,
            ];
      setState(() => _viewedStoryIds.addAll(seen));
    }
    // Süresi dolan / silinen / raporlanan story'ler halkadan düşsün.
    unawaited(_loadUserStories());
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

  bool _sendWasRejected(Object error) =>
      error is ApiException &&
      error.statusCode >= 400 &&
      error.statusCode < 500 &&
      error.statusCode != 408;

  bool get _hasUnlimitedUndos {
    final member = UserSession.instance;
    final until = member.premiumUntil;
    return member.loaded &&
        member.has(PremiumFeature.unlimitedRewinds) &&
        (until == null || until.isAfter(DateTime.now()));
  }

  void _warmUndoQuota() {
    if (!_hasUnlimitedUndos && !_undoing) {
      unawaited(UserSession.instance.warmUndoQuota(_repo.getUndoQuota));
    }
  }

  Future<void> _undoAction() async {
    if (_undoing) {
      // Cancelling a queued choice only cancels that local intent.
      if (_afterUndo != null) setState(() => _afterUndo = null);
      return;
    }
    if (!_hasUndoableAction ||
        _isBlocked ||
        _blockedByOther ||
        _interestUnavailable) {
      return;
    }
    final target = _profile?.user.id ?? widget.userId;
    if (target == null || target.isEmpty) return;
    final session = SecureStorage.sessionRevision;
    final send = _pendingSend;
    final repo = _repo;
    final member = UserSession.instance;
    final unlimited = _hasUnlimitedUndos;
    final remaining = member.recentUndoQuota?.remaining;
    if (remaining == 0) {
      await PremiumGate.showDailyUndoLimit(context);
      return;
    }
    // Ignore any pre-tap read that finishes after the mutation.
    member.recordUndoQuota(null);
    // A lookup started before this tap must not restore the outgoing interest.
    ++_profileRequest;
    ++_friendshipRequest;
    setState(() {
      _checkingFriendship = false;
      _undoPhase = unlimited || (remaining != null && remaining > 0)
          ? _UndoPhase.optimistic
          : _UndoPhase.awaitingConfirmation;
    });

    Object? failure;
    Future<void> Function()? followUp;
    try {
      var needsRewind = true;
      if (send != null) {
        try {
          await send;
        } catch (e) {
          // A definitive rejection did not create an action. If the reply
          // was lost, the server still needs to receive the requested Undo.
          needsRewind = !_sendWasRejected(e);
        }
      }
      if (session != SecureStorage.sessionRevision) return;
      if (needsRewind) {
        final quota = await repo.undoAction(target);
        if (session != SecureStorage.sessionRevision) return;
        member.recordUndoQuota(quota);
        if (_actionState != ProfileActionState.matched) {
          _actionState = ProfileActionState.showActions;
          _rememberActionState(target, ProfileActionState.showActions);
        }
        unawaited(SecureStorage.removePendingInterestedUserId(target));
      }
    } catch (e) {
      failure = e;
      if (session == SecureStorage.sessionRevision &&
          e is ApiException &&
          e.data['error'] == 'REWIND_LIMIT_REACHED') {
        member.recordUndoQuota(DailyUndoQuota.fromResponse(e.data));
      }
    } finally {
      followUp = _afterUndo?.submit;
      _afterUndo = null;
      _undoPhase = _UndoPhase.idle;
      if (mounted) setState(() {});
    }
    if (session != SecureStorage.sessionRevision) return;
    if (failure == null) {
      if (_actionState == ProfileActionState.showActions &&
          !_interestUnavailable &&
          !_isBlocked &&
          !_blockedByOther) {
        await followUp?.call();
      } else if (mounted &&
          _actionState == ProfileActionState.matched &&
          _friendship == null) {
        unawaited(_refreshFriendship());
      }
      return;
    }
    if (!mounted) return;
    final code = failure is ApiException ? failure.data['error'] : null;
    if (code == 'MATCH_EXISTS') {
      setState(() => _actionState = ProfileActionState.matched);
      _rememberActionState(target, ProfileActionState.matched);
      unawaited(SecureStorage.removePendingInterestedUserId(target));
      await showPremiumErrorDialog(
        context,
        message: 'You have already matched. Use unmatch instead.',
      );
      if (mounted &&
          session == SecureStorage.sessionRevision &&
          _friendship == null) {
        unawaited(_refreshFriendship());
      }
    } else if (code == 'REWIND_LIMIT_REACHED') {
      await PremiumGate.showDailyUndoLimit(context);
    } else {
      await showPremiumErrorDialog(
        context,
        message: 'Could not undo. Please try again.',
      );
    }
  }

  Future<MatchItem?> _sendProfileAction(
    String action,
    String target,
    String? venue,
    int session,
    CheckinRepository repo,
    ({String id, DateTime version})? notice,
  ) async {
    String? actionVenue;
    if (notice == null && venue != null && venue.isNotEmpty) {
      try {
        final me = await AuthRepository().getMe();
        final contextType =
            me['lastActiveContext'] ?? me['last_active_context'];
        if (contextType?.toString().toUpperCase() == 'VENUE') {
          actionVenue = venue;
        }
      } catch (_) {
        // Keep the existing personal-action fallback when context is unavailable.
      }
    }
    if (session != SecureStorage.sessionRevision) return null;
    return repo.sendFeedAction(
      targetUserId: target,
      venueId: actionVenue,
      interestNotice: notice,
      action: action,
    );
  }

  Future<void> _handleAction(String action) async {
    if (_isBlocked || _blockedByOther || _interestUnavailable || _accepting) {
      return;
    }
    final choice = _visibleAction;
    if (choice != ProfileActionState.showActions &&
        choice != ProfileActionState.incomingInterested) {
      return;
    }
    if (_undoPhase == _UndoPhase.awaitingConfirmation ||
        (!_undoing && (_isSendingAction || _checkingFriendship))) {
      return;
    }
    final target = _profile?.user.id ?? widget.userId;
    if (target == null || target.isEmpty) return;
    final venue = _resolvedVenueId ?? _profile?.checkin.venueId;
    final repo = _repo;
    final notice = widget.interestNotice;
    final session = SecureStorage.sessionRevision;
    Future<MatchItem?> post() =>
        _sendProfileAction(action, target, venue, session, repo, notice);
    Future<void> submit() =>
        action == 'interested' &&
            (choice == ProfileActionState.incomingInterested || notice != null)
        ? _acceptInterest(target, session, post)
        : _submitProfileAction(action, target, choice!, session, post);
    if (_undoing) {
      setState(() => _afterUndo = (action: action, submit: submit));
      return;
    }
    _warmUndoQuota();
    await submit();
  }

  Future<void> _acceptInterest(
    String target,
    int session,
    Future<MatchItem?> Function() post,
  ) async {
    final recheckFirst = _retryAccept;
    final request = ++_acceptRequest;
    bool current() =>
        mounted &&
        session == SecureStorage.sessionRevision &&
        request == _acceptRequest;
    ++_profileRequest;
    ++_friendshipRequest;
    setState(() {
      _accepting = true;
      _retryAccept = false;
      _checkingFriendship = false;
    });
    MatchItem? confirmed;
    Object? failure;
    try {
      if (recheckFirst) {
        confirmed = await _matchRepo.getFriendship(target);
        if (!current()) return;
      }
      if (confirmed == null) {
        final response = post();
        // The write may already be committed while its response waits for
        // notification delivery. One read covers a missing realtime event.
        final earlyMatch = Completer<MatchItem?>();
        final timer = _slowAcceptTimer = Timer(
          const Duration(milliseconds: 400),
          () async {
            if (!current()) return;
            try {
              final friendship = await _matchRepo.getFriendship(target);
              if (current() && friendship != null) {
                earlyMatch.complete(friendship);
              }
            } catch (_) {
              // A failed or empty read cannot settle the original write.
            }
          },
        );
        try {
          confirmed = await Future.any([response, earlyMatch.future]);
        } finally {
          timer.cancel();
          if (identical(timer, _slowAcceptTimer)) _slowAcceptTimer = null;
        }
      }
    } catch (error) {
      failure = error;
    }
    if (!current()) return;
    // A timeout or a consumed receipt can follow a committed acceptance.
    // Older servers also omit friendship from a successful write.
    try {
      confirmed ??= await _matchRepo.getFriendship(target);
    } catch (_) {
      if (current()) {
        setState(() {
          _accepting = false;
          _retryAccept = true;
        });
      }
      return;
    }
    if (!current()) return;
    setState(() {
      _accepting = false;
      if (confirmed != null) {
        _friendship = confirmed;
        _actionState = ProfileActionState.matched;
      } else if (failure is ApiException &&
          failure.data['errorCode'] == 'INTEREST_UNAVAILABLE') {
        _interestUnavailable = true;
      } else if (failure == null && widget.interestNotice == null) {
        _actionState = ProfileActionState.waitingResponse;
      } else if (failure == null) {
        _interestUnavailable = true;
      } else {
        _retryAccept = true;
      }
    });
    if (_interestUnavailable) {
      ProfilePreviewPage._actionStateCacheByUserId.remove(target);
    } else if (!_retryAccept) {
      _rememberActionState(target, _actionState!);
      unawaited(_syncPendingInterestedState(target, _actionState!));
    }
  }

  Future<void> _submitProfileAction(
    String action,
    String targetUserId,
    ProfileActionState previousState,
    int session,
    Future<MatchItem?> Function() post,
  ) async {
    final nextState = action == 'interested'
        ? ProfileActionState.waitingResponse
        : ProfileActionState.proactivePass;
    ++_profileRequest;
    ++_friendshipRequest;
    final send = post();
    _actionState = nextState;
    _pendingSend = send;
    if (mounted) setState(() {});
    _rememberActionState(targetUserId, nextState);
    unawaited(_syncPendingInterestedState(targetUserId, nextState));
    try {
      final confirmed = await send;
      if (session == SecureStorage.sessionRevision &&
          confirmed != null &&
          !_undoing &&
          _actionState == nextState) {
        _friendship = confirmed;
        _actionState = ProfileActionState.matched;
        _rememberActionState(targetUserId, ProfileActionState.matched);
        unawaited(SecureStorage.removePendingInterestedUserId(targetUserId));
        return;
      }
    } catch (e) {
      if (session != SecureStorage.sessionRevision) return;
      if (e is ApiException && e.data['errorCode'] == 'INTEREST_UNAVAILABLE') {
        ProfilePreviewPage._actionStateCacheByUserId.remove(targetUserId);
        unawaited(SecureStorage.removePendingInterestedUserId(targetUserId));
        if (mounted) setState(() => _interestUnavailable = true);
      } else if (_actionState == nextState &&
          (!_undoing || _sendWasRejected(e))) {
        if (mounted) setState(() => _actionState = previousState);
        _rememberActionState(targetUserId, previousState);
        unawaited(_syncPendingInterestedState(targetUserId, previousState));
      }
      return;
    } finally {
      _pendingSend = null;
      if (mounted) setState(() {});
    }
    if (mounted &&
        session == SecureStorage.sessionRevision &&
        !_undoing &&
        action == 'interested') {
      await _refreshFriendship();
      if (mounted &&
          session == SecureStorage.sessionRevision &&
          _actionState == ProfileActionState.matched) {
        await _loadProfile();
      }
    }
  }

  Future<void> _openChat() async {
    if (_isBlocked || _blockedByOther) {
      await showPremiumErrorDialog(
        context,
        message: _blockedByOther
            ? 'Messaging is unavailable with this user.'
            : 'User is blocked. Unblock to message.',
      );
      return;
    }

    final target = _profile?.user.id ?? widget.userId;
    if (target == null || _openingChat || !_isMatchedActionState) return;
    final session = SecureStorage.sessionRevision;
    setState(() => _openingChat = true);
    try {
      var chatId = _friendship?.chatId ?? _profile?.chatId ?? widget.chatIdHint;
      if (chatId == null || chatId.isEmpty) {
        chatId = (await _matchRepo.getFriendship(target))?.chatId;
      }
      if (!mounted ||
          session != SecureStorage.sessionRevision ||
          !_isMatchedActionState ||
          _isBlocked ||
          _blockedByOther) {
        return;
      }
      if (chatId == null || chatId.isEmpty) {
        await _refreshFriendship();
        if (mounted && session == SecureStorage.sessionRevision) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Chat is currently unavailable.')),
          );
        }
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            chatId: chatId,
            otherUserId: target,
            otherName:
                _profile?.user.fullName ??
                _publicProfile?.fullName ??
                widget.userName ??
                'User',
            otherPhotoUrl: _previewAvatarUrl() ?? '',
          ),
        ),
      );
    } catch (_) {
      if (mounted && session == SecureStorage.sessionRevision) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open chat. Please try again.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _openingChat = false);
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
    if (!mounted) return;
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

    if (_isBlocking || !mounted) return;

    final wasBlocked = _isBlocked;
    setState(() => _isBlocking = true);
    try {
      final Future<bool> confirmation;
      if (wasBlocked) {
        confirmation = confirmAndUnblockUser(
          context,
          repository: _repo,
          targetUserId: targetUserId,
        );
      } else {
        confirmation = confirmAndBlockUser(
          context,
          repository: _repo,
          targetUserId: targetUserId,
        );
      }
      final changed = await confirmation;
      if (changed && mounted) setState(() => _isBlocked = !wasBlocked);
    } finally {
      if (mounted) setState(() => _isBlocking = false);
    }
  }

  Future<void> _openReportSheet() async {
    final targetUserId = _profile?.user.id ?? widget.userId;
    if (targetUserId == null || targetUserId.isEmpty) {
      await showPremiumErrorDialog(context, message: 'User is not available.');
      return;
    }
    if (_isReporting) return;

    setState(() => _isReporting = true);
    try {
      final reported = await showReportUserSheet(
        context,
        targetUserId: targetUserId,
        repository: _repo,
      );
      if (reported && mounted) setState(() => _isBlocked = true);
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }

  Future<void> _openTopActionsSheet() async {
    if (_isReporting || _isBlocking || _removingFriend) return;
    await showUserActionsSheet(
      context,
      isBlocked: _isBlocked,
      onRemoveFriend: _friendship != null && !_isBlocked && !_blockedByOther
          ? () => unawaited(_removeFriend())
          : null,
      onReport: () => unawaited(_openReportSheet()),
      onToggleBlock: () => unawaited(_toggleBlock()),
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

  Future<void> _openMediaViewerAt(int index) async {
    if (!_showPostsAndVibe || _profile == null || _profile!.media.isEmpty) {
      return;
    }
    final mediaForViewer = _mediaForViewer();
    await Navigator.push<bool>(
      context,
      momentsViewerRoute(
        builder: (_) => MomentsViewerPage(
          media: mediaForViewer,
          initialIndex: index,
          allowFeature: false,
          reportedUserId: _profile!.user.id,
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

    if (_interestUnavailable ||
        (widget.interestNotice != null && (_isBlocked || _blockedByOther))) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.person_off_outlined, size: 32),
              const SizedBox(height: 12),
              const Text('This request is no longer available.'),
              if (Navigator.canPop(context))
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Go back'),
                ),
            ],
          ),
        ),
      );
    }

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
    if (_profile == null && (!hasFallbackProfile || _profileUnavailable)) {
      return _buildUnavailableProfile(theme);
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
      _buildPreviewAvatar(
        avatarUrl,
        isDark,
        mediaReference: _previewAvatarReference(avatarUrl),
      ),
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
        _buildAnimatedActionBar(),
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
      // Engellenen kullanıcının moment'ları ve gidilen mekanları gizlenir.
      if (_isBlocked)
        _buildBlockedProfileNotice(onSurface, subColor)
      else ...[
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
        ] else if (visitedPlaces.isEmpty)
          _buildVisitedPlacesEmptyState(
            isDark: isDark,
            subColor: subColor,
            onSurface: onSurface,
          ),
      ],
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
                    onPressed: (_isReporting || _isBlocking || _removingFriend)
                        ? null
                        : _openTopActionsSheet,
                    icon: Icon(Icons.more_horiz_rounded, color: onSurface),
                  ),
                ],
              ),
            ),

            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadProfile,
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
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
                    if (!_isBlocked &&
                        _selectedProfileTab == 1 &&
                        visitedPlaces.isNotEmpty)
                      _buildVisitedPlacesSliver(
                        places: visitedPlaces,
                        isDark: isDark,
                        subColor: subColor,
                        onSurface: onSurface,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Durum değişince butonlar yerini yumuşakça durum çubuğuna bırakır.
  Widget _buildAnimatedActionBar() {
    if (_accepting) {
      return const SizedBox(
        height: 48,
        child: Center(child: Text('Connecting…')),
      );
    }
    if (_retryAccept) {
      return TextButton.icon(
        onPressed: () => _handleAction('interested'),
        icon: const Icon(Icons.refresh),
        label: const Text('Couldn’t confirm your connection. Try again'),
      );
    }
    // Do not render notification hints as actionable choices before the server
    // confirms the relationship. An existing match stays visually unchanged.
    // Drop any outgoing animated controls on the first frame of Undo.
    if ((_undoing || _isSendingAction) && _hasUndoableAction) {
      return _buildActionBar();
    }
    final keepUndoBar = _hasUndoableAction && _hasCheckedFriendship;
    if (_checkingFriendship &&
        _actionState != ProfileActionState.matched &&
        !keepUndoBar) {
      return const SizedBox(
        height: 48,
        child: Center(
          child: SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    const duration = Duration(milliseconds: 180);
    final currentKey = ValueKey<Object?>(_isBlocked ? 'blocked' : _actionState);
    return AnimatedSize(
      duration: duration,
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          // Kaybolan durum dokunuş almaz: Undo iki kez gönderilmesin.
          child: IgnorePointer(ignoring: child.key != currentKey, child: child),
        ),
        child: KeyedSubtree(key: currentKey, child: _buildActionBar()),
      ),
    );
  }

  Widget _buildActionBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? Colors.white70 : Colors.black54;
    if (_isBlocked) {
      return Text(
        'User blocked',
        style: TextStyle(color: subColor, fontSize: 16),
      );
    }

    switch (_visibleAction!) {
      case ProfileActionState.incomingInterested:
      case ProfileActionState.showActions:
        return Column(
          children: [
            if (_visibleAction == ProfileActionState.incomingInterested) ...[
              _buildIncomingInterestPrompt(isDark),
              const SizedBox(height: 12),
            ],
            // Eşit genişlik: seçimi boyut değil, Interested'ın rengi öne çıkarır.
            Row(
              children: [
                Expanded(
                  child: _ProfileActionButton(
                    label: 'Pass',
                    icon: Icons.close_rounded,
                    onTap: () => _handleAction('pass'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ProfileActionButton(
                    label: 'Interested',
                    icon: Icons.favorite_rounded,
                    primary: true,
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
        return _ProfileActionStatusBar(
          label: 'You passed',
          icon: Icons.close_rounded,
          onUndo: _undoPhase == _UndoPhase.awaitingConfirmation
              ? null
              : _undoAction,
        );

      case ProfileActionState.waitingResponse:
        return Column(
          children: [
            // Rewind: henüz match olmadan gönderilen interested geri alınabilir.
            _ProfileActionStatusBar(
              label: 'Interest sent',
              icon: Icons.check_rounded,
              highlighted: true,
              onUndo: _undoPhase == _UndoPhase.awaitingConfirmation
                  ? null
                  : _undoAction,
            ),
            const SizedBox(height: 8),
            Text(
              'If they choose Interested too, you can start chatting.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        );

      case ProfileActionState.matched:
        return const SizedBox.shrink();
    }
  }

  Widget _buildIncomingInterestPrompt(bool isDark) {
    final accent = isDark ? AppColors.blueDark : AppColors.blueLight;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_rounded, size: 15, color: accent),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Interested in you',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: accent,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          'Choose Interested to match and start chatting.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: isDark
                ? AppColors.darkTextSecondary
                : AppColors.lightTextSecondary,
            fontSize: 12.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _buildMatchedMessageButton() {
    // Herhangi bir yönde blok varsa (ben blokladım = _isBlocked, ya da karşı
    // taraf beni blokladı = _blockedByOther) mesajlaşma duraklatılır → buton
    // inaktif (gri + tıklanamaz). Basınca hata dialog'u yerine devre dışı görünür.
    final blocked = _isBlocked || _blockedByOther;
    return SizedBox(
      width: 184,
      height: 44,
      child: FilledButton.icon(
        onPressed: blocked || _openingChat ? null : _openChat,
        icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
        label: const Text('Message'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          backgroundColor: AppTheme.brandCta,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppTheme.brandCta.withValues(alpha: 0.30),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.55),
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

  /// Engellenen kullanıcının profil içeriği (moment'lar / gidilen mekanlar)
  /// yerine gösterilen bilgilendirme.
  /// Askıya alınmış/silinmiş hesap: profil, fotoğraf ve aksiyonlar gösterilmez.
  Widget _buildUnavailableProfile(ThemeData theme) {
    final onSurface = theme.colorScheme.onSurface;
    final subColor = onSurface.withValues(alpha: 0.6);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_outlined, size: 46, color: subColor),
              const SizedBox(height: 12),
              Text(
                'Profile unavailable',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'This account isn\'t available right now.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 13.5, height: 1.3),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedProfileNotice(Color onSurface, Color subColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Center(
        child: Column(
          children: [
            Icon(Icons.block_rounded, size: 46, color: subColor),
            const SizedBox(height: 12),
            Text(
              'You blocked this user',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: onSurface,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Their moments and visited places are hidden. Unblock to see their profile again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 13.5, height: 1.3),
            ),
          ],
        ),
      ),
    );
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

  // Guards against a rapid double-tap opening the venue detail page twice —
  // the resolve step is async, so two taps can both push before the first
  // navigation starts.
  bool _openingVenueDetail = false;

  Future<void> _openVisitedVenueDetail(CheckinVisitedPlace place) async {
    if (_openingVenueDetail) return;
    final venueId = (place.venueId ?? '').trim();
    if (venueId.isEmpty) return;
    _openingVenueDetail = true;
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
    if (!mounted) {
      _openingVenueDetail = false;
      return;
    }
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => VenueDetailPage(venue: resolvedVenue),
        ),
      );
    } finally {
      _openingVenueDetail = false;
    }
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

  MediaReference? _previewAvatarReference(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url == _profile?.user.photo) return _profile?.user.photoReference;
    if (url == _publicProfile?.photo) return _publicProfile?.photoReference;
    return null;
  }

  bool get _hasPreviewStats => _profile != null || _publicProfile != null;

  bool get _isPreviewVerified =>
      _profile?.user.isVerified == true || _publicProfile?.isVerified == true;

  /// Ortalanmış, karemsi (radius 32) avatar — personal profil ile aynı dil.
  Widget _buildPreviewAvatar(
    String? url,
    bool isDark, {
    MediaReference? mediaReference,
  }) {
    const size = 128.0;
    const radius = 32.0;
    // Kendi profilindeki story halkasıyla aynı ölçüler.
    const ringWidth = 3.0;
    const ringGap = 2.5;
    // Halkanın yeri her zaman ayrılır → story sonradan yüklenince avatar
    // zıplamaz.
    const totalSize = size + (ringWidth + ringGap) * 2;
    final group = (_isBlocked || _blockedByOther) ? null : _storyGroup;

    final avatar = ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? CachedImage(
                url,
                fit: BoxFit.cover,
                mediaReference: mediaReference,
                errorWidget: (_) => _previewAvatarFallback(isDark),
              )
            : _previewAvatarFallback(isDark),
      ),
    );

    return Center(
      child: Semantics(
        button: group != null,
        label: group != null ? 'View story' : null,
        child: GestureDetector(
          onTap: group == null ? null : _openUserStories,
          child: SizedBox(
            width: totalSize,
            height: totalSize,
            child: Stack(
              alignment: Alignment.center,
              children: [
                avatar,
                if (group != null)
                  Positioned.fill(
                    child: CustomPaint(
                      key: const ValueKey('profile-story-ring'),
                      painter: RoundedStoryRingPainter(
                        colors: _hasUnseenStory
                            ? RoundedStoryRingPainter.logoColors
                            : RoundedStoryRingPainter.seenColors,
                        strokeWidth: ringWidth,
                        radius: radius + ringGap,
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
          ? CachedImage(
              media.url,
              mediaReference: media.mediaReference,
              fit: BoxFit.cover,
            )
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
}

/// Pass / Interested sonrası aynı yerde, aynı ölçüde duran durum çubuğu.
/// [highlighted] gönderilen ilgiyi Interested'ın mavisiyle gösterir; Undo hep
/// sakindir, çünkü ana işlem bitmiştir.
class _ProfileActionStatusBar extends StatelessWidget {
  const _ProfileActionStatusBar({
    required this.label,
    required this.icon,
    required this.onUndo,
    this.highlighted = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onUndo;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final muted = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final accent = !highlighted
        ? muted
        : (isDark ? AppColors.blueDark : AppColors.blueLight);
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.fromLTRB(14, 0, 6, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: highlighted
            ? AppColors.blue.withValues(alpha: isDark ? 0.14 : 0.10)
            : (isDark ? const Color(0xFF0D1525) : const Color(0xFFF4F7FB)),
        border: Border.all(
          color: highlighted
              ? AppColors.blue.withValues(alpha: 0.30)
              : (isDark
                    ? const Color(0xFF162040)
                    : Colors.black.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: accent,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onUndo,
            icon: const Icon(Icons.undo_rounded, size: 16),
            label: Text(onUndo == null ? 'Undoing…' : 'Undo'),
            style: TextButton.styleFrom(
              foregroundColor: muted,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Profildeki Pass / Interested butonu. İkisi aynı ölçüde; [primary] düz mavi
/// birincil aksiyonu, diğeri venue detayındaki sade ikincil butonu çizer.
class _ProfileActionButton extends StatelessWidget {
  const _ProfileActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = primary || isDark
        ? Colors.white
        : AppColors.lightTextPrimary;
    final radius = BorderRadius.circular(14);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Ink(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: radius,
            color: primary
                ? AppColors.blue
                : (isDark ? const Color(0xFF0D1525) : const Color(0xFFF4F7FB)),
            border: primary
                ? null
                : Border.all(
                    color: isDark
                        ? const Color(0xFF162040)
                        : Colors.black.withValues(alpha: 0.08),
                  ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 18),
                const SizedBox(width: 6),
                // Büyük yazı boyutunda da butondan taşmasın.
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
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
}
