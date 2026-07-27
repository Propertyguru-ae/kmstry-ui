import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/data/username_search_item_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Username-based friend search + friend-request entry. Nearby discovery now
/// lives in its own navbar destination (WhoIsNearbyPage).
class FindFriendsPage extends StatefulWidget {
  const FindFriendsPage({super.key});

  @override
  State<FindFriendsPage> createState() => _FindFriendsPageState();
}

class _FindFriendsPageState extends State<FindFriendsPage> {
  final MatchRepository _repo = MatchRepository();
  final NotificationRepository _notificationRepo = NotificationRepository();
  final TextEditingController _queryCtrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<UsernameSearchItem> _items = const [];
  Set<String> _incomingInterestedUserIds = const {};
  Set<String> _pendingInterestedUserIds = const {};

  @override
  void initState() {
    super.initState();
    _warmRelationshipHints();
    _loadPendingInterestedHints();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryCtrl.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = _queryCtrl.text.trim();
    if (query.length < 2) {
      setState(() {
        _loading = false;
        _error = null;
        _items = const [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search(query);
    });
  }

  Future<void> _search(String query) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _repo.findByUsername(query);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _items = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not search right now.';
      });
    }
  }

  Future<void> _warmRelationshipHints() async {
    try {
      final notifications = await _notificationRepo.getNotifications(
        limit: 100,
      );
      final incoming = <String>{};
      for (final n in notifications) {
        if (n.type != 'interested' && n.type != 'liked_you') continue;
        final data = n.data ?? const <String, dynamic>{};
        String? read(List<String> keys) {
          for (final key in keys) {
            final raw = data[key];
            if (raw == null) continue;
            final value = raw.toString().trim();
            if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
          }
          return null;
        }

        final uid = read(const [
          'user_id',
          'sender_id',
          'requester_id',
          'actor_user_id',
          'userId',
          'senderId',
          'requesterId',
          'actorUserId',
        ]);
        if (uid != null) incoming.add(uid);
      }
      if (!mounted) return;
      setState(() => _incomingInterestedUserIds = incoming);
    } catch (_) {
      // Non-blocking hint loader.
    }
  }

  Future<void> _loadPendingInterestedHints() async {
    try {
      final ids = await SecureStorage.getPendingInterestedUserIds();
      if (!mounted) return;
      setState(() => _pendingInterestedUserIds = ids);
    } catch (_) {
      // Non-blocking hint loader.
    }
  }

  ProfileActionState? _inferActionStateHint(UsernameSearchItem item) {
    final myAction = item.myAction?.toLowerCase();
    final theirAction = item.theirAction?.toLowerCase();
    final relationshipState = item.relationshipState?.toLowerCase();
    final hasBackendRelationshipSignals =
        (relationshipState != null && relationshipState.isNotEmpty) ||
        (myAction != null && myAction.isNotEmpty) ||
        (theirAction != null && theirAction.isNotEmpty) ||
        item.isMatched ||
        (item.chatId != null && item.chatId!.isNotEmpty);

    bool hasAny(String? value, List<String> candidates) {
      if (value == null || value.isEmpty) return false;
      return candidates.contains(value);
    }

    if (item.isMatched || (item.chatId != null && item.chatId!.isNotEmpty)) {
      return ProfileActionState.matched;
    }
    if (relationshipState == 'matched') {
      return ProfileActionState.matched;
    }
    if (hasAny(relationshipState, const [
      'incoming_interested',
      'incoming-interest',
      'incoming interested',
      'liked_you',
      'incoming',
      'received_interest',
    ])) {
      return ProfileActionState.incomingInterested;
    }
    if (hasAny(relationshipState, const [
      'outgoing_interested',
      'outgoing-interest',
      'outgoing interested',
      'waiting_response',
      'waiting-response',
      'waiting response',
      'pending',
      'requested',
    ])) {
      return ProfileActionState.waitingResponse;
    }
    if (hasAny(relationshipState, const [
      'outgoing_pass',
      'outgoing-pass',
      'outgoing pass',
    ])) {
      return ProfileActionState.proactivePass;
    }
    if (hasAny(relationshipState, const [
      'incoming_pass',
      'incoming-pass',
      'incoming pass',
    ])) {
      return ProfileActionState.showActions;
    }
    if (hasAny(theirAction, const [
      'interested',
      'liked_you',
      'incoming_interested',
      'received_interest',
    ])) {
      if (hasAny(myAction, const ['interested'])) {
        return ProfileActionState.matched;
      }
      return ProfileActionState.incomingInterested;
    }
    if (hasAny(myAction, const [
      'interested',
      'outgoing_interested',
      'requested',
      'pending',
    ])) {
      return ProfileActionState.waitingResponse;
    }
    if (hasAny(myAction, const ['pass', 'rejected'])) {
      return ProfileActionState.proactivePass;
    }

    // Legacy fallbacks: only use if backend relationship hints are absent.
    if (hasBackendRelationshipSignals) return null;

    if (_incomingInterestedUserIds.contains(item.id)) {
      return ProfileActionState.incomingInterested;
    }
    if (_pendingInterestedUserIds.contains(item.id)) {
      return ProfileActionState.waitingResponse;
    }
    final cached = ProfilePreviewPage.peekCachedActionState(item.id);
    if (cached != null && cached != ProfileActionState.showActions) {
      return cached;
    }
    return null;
  }

  void _openProfile(UsernameSearchItem item) {
    final active = item.activeCheckin;
    final actionHint = _inferActionStateHint(item);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: active?.id,
          venueId: active?.venueId,
          hintVenueId: active?.venueId,
          hintVenueName: active?.venueName,
          hintVenueType: active?.venueType,
          hintVenuePhoto: active?.venuePhoto,
          userId: item.id,
          userName: item.fullName ?? '@${item.username}',
          userUsername: item.username,
          userPhoto: item.photo,
          isMatchedHint: item.isMatched,
          chatIdHint: item.chatId,
          actionStateHint: actionHint,
          fallbackBio: item.bio,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgTop = isDark
        ? const Color(0xFF121A2B)
        : theme.scaffoldBackgroundColor;
    final bgBottom = isDark
        ? const Color(0xFF0B0F17)
        : theme.scaffoldBackgroundColor;
    final cardColor = isDark
        ? const Color(0xFF161C28)
        : theme.colorScheme.surface;
    final borderColor = isDark
        ? const Color(0xFF252D3D)
        : theme.colorScheme.outline.withValues(alpha: 0.25);
    final hasQuery = _queryCtrl.text.trim().length >= 2;

    return Scaffold(
      backgroundColor: bgBottom,
      appBar: AppBar(
        leading: const AppLogo(),
        title: Text(
          'Find Friends',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurface,
          ),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
          child: Column(
            children: [
              Container(
                color: theme.appBarTheme.backgroundColor,
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _queryCtrl,
                    onChanged: (_) => _onChanged(),
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: 'Search by username...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white38 : Colors.grey[500],
                        fontSize: 15,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: isDark
                            ? Colors.white54
                            : const Color(0xFF64748B),
                        size: 22,
                      ),
                      suffixIcon: _queryCtrl.text.trim().isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                _debounce?.cancel();
                                _queryCtrl.clear();
                                _onChanged();
                              },
                            ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              Expanded(
                child: !hasQuery
                    ? const Center(child: Text('Search friends by username'))
                    : _loading
                    ? Center(
                        child: CircularProgressIndicator(
                          color: theme.colorScheme.primary,
                        ),
                      )
                    : _items.isEmpty
                    ? const Center(child: Text('No users found'))
                    : ListView.separated(
                        itemCount: _items.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(18),
                              onTap: () => _openProfile(item),
                              child: Ink(
                                decoration: BoxDecoration(
                                  color: cardColor,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: borderColor),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 6,
                                  ),
                                  leading: CircleAvatar(
                                    backgroundColor: theme.colorScheme.primary
                                        .withValues(alpha: 0.18),
                                    child: Icon(
                                      Icons.person_outline,
                                      color: theme.colorScheme.primary,
                                    ),
                                  ),
                                  title: Text(
                                    '@${item.username}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    item.fullName?.trim().isNotEmpty == true
                                        ? item.fullName!
                                        : 'No name yet',
                                  ),
                                  trailing: const SizedBox.shrink(),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
