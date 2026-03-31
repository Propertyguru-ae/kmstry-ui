import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/data/nearby_venue_user_item_model.dart';
import 'package:kmstry_frontend/features/people/data/username_search_item_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

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
  bool _loadingNearby = false;
  String? _error;
  List<UsernameSearchItem> _items = const [];
  List<NearbyVenueUserItem> _nearbyItems = const [];
  Set<String> _incomingInterestedUserIds = const {};
  Set<String> _pendingInterestedUserIds = const {};

  @override
  void initState() {
    super.initState();
    _warmRelationshipHints();
    _loadPendingInterestedHints();
    _loadNearbyVenueUsers();
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

  Future<void> _loadNearbyVenueUsers() async {
    setState(() => _loadingNearby = true);
    try {
      final items = await _repo.listNearbyVenueUsers();
      if (!mounted) return;
      setState(() {
        _loadingNearby = false;
        _nearbyItems = items;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingNearby = false;
        _nearbyItems = const [];
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
          userId: item.id,
          userName: item.fullName ?? '@${item.username}',
          userUsername: item.username,
          isMatchedHint: item.isMatched,
          chatIdHint: item.chatId,
          actionStateHint: actionHint,
          fallbackBio: item.bio,
        ),
      ),
    );
  }

  void _openNearbyProfile(NearbyVenueUserItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: item.checkinId,
          venueId: item.venueId,
          userId: item.userId,
          userName: (item.fullName != null && item.fullName!.trim().isNotEmpty)
              ? item.fullName!.trim()
              : 'User',
          hintVenueId: item.venueId,
          hintVenueName: item.venueName,
          hintVenueType: item.venueType,
          hintVenuePhoto: item.venuePhoto,
          fallbackBio: null,
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
    final showUsernameSearch = _queryCtrl.text.trim().length >= 2;

    return Scaffold(
      backgroundColor: bgBottom,
      appBar: AppBar(
        title: const Text('Find friends'),
        backgroundColor: Colors.transparent,
        elevation: 0,
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
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Container(
                color: theme.appBarTheme.backgroundColor,
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? theme.colorScheme.primary.withValues(alpha: 0.12)
                      : theme.colorScheme.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? theme.colorScheme.primary.withValues(alpha: 0.35)
                        : theme.colorScheme.primary.withValues(alpha: 0.22),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(
                        alpha: isDark ? 0.18 : 0.08,
                      ),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.explore_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        "Explore who’s nearby, across surrounding venues",
                        style: TextStyle(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.88,
                          ),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.1,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              const SizedBox(height: 8),
              Expanded(
                child: showUsernameSearch
                    ? (_loading
                          ? Center(
                              child: CircularProgressIndicator(
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : _items.isEmpty
                          ? const Center(
                              child: Text('Search friends by username'),
                            )
                          : ListView.separated(
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final item = _items[index];
                                final hasActiveCheckin =
                                    item.activeCheckin != null;
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
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 14,
                                              vertical: 6,
                                            ),
                                        leading: CircleAvatar(
                                          backgroundColor: theme
                                              .colorScheme
                                              .primary
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
                                          item.fullName?.trim().isNotEmpty ==
                                                  true
                                              ? item.fullName!
                                              : 'No name yet',
                                        ),
                                        trailing: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: hasActiveCheckin
                                                ? Colors.green.withValues(
                                                    alpha: 0.18,
                                                  )
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            border: Border.all(
                                              color: hasActiveCheckin
                                                  ? Colors.green.withValues(
                                                      alpha: 0.35,
                                                    )
                                                  : borderColor,
                                            ),
                                          ),
                                          child: Icon(
                                            hasActiveCheckin
                                                ? Icons.radio_button_checked
                                                : Icons.circle_outlined,
                                            size: 12,
                                            color: hasActiveCheckin
                                                ? Colors.green
                                                : theme
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ))
                    : (_loadingNearby
                          ? Center(
                              child: CircularProgressIndicator(
                                color: theme.colorScheme.primary,
                              ),
                            )
                          : _nearbyItems.isEmpty
                          ? const Center(
                              child: Text('Search friends by username'),
                            )
                          : GridView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: _nearbyItems.length,
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: 2,
                                    mainAxisSpacing: 1.5,
                                    crossAxisSpacing: 1.5,
                                    childAspectRatio: 0.7,
                                  ),
                              itemBuilder: (context, index) {
                                final item = _nearbyItems[index];
                                return _NearbyUserCard(
                                  item: item,
                                  onTap: () => _openNearbyProfile(item),
                                );
                              },
                            )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NearbyUserCard extends StatelessWidget {
  final NearbyVenueUserItem item;
  final VoidCallback onTap;

  const _NearbyUserCard({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final imageUrl = item.displayPhoto;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (imageUrl.isNotEmpty)
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _placeholder(),
            )
          else
            _placeholder(),
          if (item.isFeaturedVideo)
            const Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.72),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: Text(
              item.fullName?.trim().isNotEmpty == true
                  ? item.fullName!
                  : 'Unknown user',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w500,
                fontSize: 11,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.person, color: Colors.white70, size: 32),
    );
  }
}
