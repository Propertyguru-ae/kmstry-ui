import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/presentation/find_friends_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';
import 'package:kmstry_frontend/features/stories/data/story_model.dart';
import 'package:kmstry_frontend/features/stories/data/story_repository.dart';
import 'package:kmstry_frontend/features/stories/data/story_viewed_cache.dart';
import 'package:kmstry_frontend/features/stories/presentation/story_viewer_page.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> with SingleTickerProviderStateMixin {
  static const int _pageSize = 20;
  late final TabController _tabController;
  final MatchRepository _repo = MatchRepository();
  final _storyRepo = StoryRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  List<MatchItem> _matches = [];
  List<BlockedUser> _blockedUsers = [];
  List<StoryGroup> _friendStoryGroups = [];
  Set<String> _viewedStoryIds = {};
  bool _storiesLoading = true;
  String _searchQuery = '';
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loading = true;
  String? _error;
  int _requestId = 0;
  final Set<String> _deletingMatchIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _loadStories();
    _scrollController.addListener(_onScroll);
  }

  Future<void> _loadStories() async {
    try {
      final results = await Future.wait([
        _storyRepo.getFriendsStories(),
        StoryViewedCache.loadAll(),
      ]);
      if (!mounted) return;
      setState(() {
        _friendStoryGroups = results[0] as List<StoryGroup>;
        _viewedStoryIds = results[1] as Set<String>;
        _storiesLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _storiesLoading = false);
    }
  }

  Future<void> _refreshViewedCache() async {
    final ids = await StoryViewedCache.loadAll();
    if (!mounted) return;
    setState(() => _viewedStoryIds = ids);
  }

  int _firstUnseenIndex(List<StoryItem> stories) {
    for (int i = 0; i < stories.length; i++) {
      if (!_viewedStoryIds.contains(stories[i].id)) return i;
    }
    return 0;
  }

  void _openFriendStory(int groupIndex) {
    final group = _friendStoryGroups[groupIndex];
    final startIndex = _firstUnseenIndex(group.stories);
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StoryViewerPage(
          groups: _friendStoryGroups,
          initialGroupIndex: groupIndex,
          initialStoryIndex: startIndex,
        ),
      ),
    ).then((_) => _refreshViewedCache());
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (!_hasMore || _isLoadingMore || _loading) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 220) {
      _loadData(reset: false);
    }
  }

  Future<void> _loadData({bool reset = true}) async {
    final requestId = ++_requestId;
    final query = _searchQuery.trim();
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_isLoadingMore || !_hasMore) return;
      setState(() {
        _isLoadingMore = true;
      });
    }
    try {
      List<BlockedUser> blocked = _blockedUsers;
      if (reset) {
        try {
          blocked = await _repo.getBlockedUsers();
        } catch (e) {
          debugPrint('[PeoplePage] getBlockedUsers failed, continue: $e');
          blocked = _blockedUsers;
        }
      }
      final result = await _repo.getMatchesPage(
        query: query.isEmpty ? null : query,
        limit: _pageSize,
        cursor: reset ? null : _nextCursor,
      );
      final blockedIds = blocked.map((b) => b.userId).toSet();
      final pageItems =
          result.items.where((m) => !blockedIds.contains(m.userId)).toList();
      for (final m in pageItems.take(8)) {
        debugPrint(
          '[PeoplePage] match userId=${m.userId} username=${m.username} bio="${m.bio ?? ''}"',
        );
      }
      if (!mounted || requestId != _requestId) return;
      setState(() {
        if (reset) {
          _matches = pageItems;
        } else {
          final existingMatchIds = _matches.map((m) => m.matchId).toSet();
          final appendable = pageItems
              .where((m) => !existingMatchIds.contains(m.matchId))
              .toList();
          _matches = [..._matches, ...appendable];
        }
        _blockedUsers = blocked;
        _nextCursor = result.nextCursor;
        _hasMore = result.hasMore;
        _loading = false;
        _isLoadingMore = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('[PeoplePage] _loadData failed: $e');
      if (!mounted || requestId != _requestId) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _isLoadingMore = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() => _searchQuery = value);
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      _loadData(reset: true);
    });
  }

  void _openMessage(MatchItem match) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => MessageDetailPage(
          chatId: match.chatId,
          otherUserId: match.userId,
          otherName: match.fullName,
          otherPhotoUrl: '',
        ),
      ),
    );
  }

  Future<bool> _confirmDeleteFriendDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete friend'),
          content: const Text(
            'You will return to the non-matched state with this user.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            Row(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: AppTheme.brandPrimary,
                  ),
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: colors.error),
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            ),
          ],
        );
      },
    );
    return result == true;
  }

  Future<void> _deleteFriend(MatchItem match) async {
    final key = match.matchId;
    if (key.isEmpty || _deletingMatchIds.contains(key)) return;

    final confirmed = await _confirmDeleteFriendDialog();
    if (!confirmed || !mounted) return;

    final previousMatches = List<MatchItem>.from(_matches);
    setState(() {
      _deletingMatchIds.add(key);
      _matches = _matches.where((m) => m.matchId != key).toList();
    });

    try {
      await _repo.deleteMatch(key);
      if (!mounted) return;
      setState(() {
        _deletingMatchIds.remove(key);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingMatchIds.remove(key);
        _matches = previousMatches;
      });
      await showPremiumErrorDialog(
        context,
        message:
            'Friend could not be deleted: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    }
  }

  Future<void> _openProfile(MatchItem match) async {
    String? resolvedBio = match.bio?.trim();
    debugPrint(
      '[PeoplePage] openProfile initial bio for userId=${match.userId}: "${resolvedBio ?? ''}"',
    );
    if ((resolvedBio == null || resolvedBio.isEmpty) &&
        match.username != null &&
        match.username!.trim().isNotEmpty) {
      try {
        final candidates = await _repo.findByUsername(match.username!.trim());
        final byId = candidates.where((c) => c.id == match.userId).toList();
        final byUsername = candidates
            .where(
              (c) =>
                  c.username.toLowerCase() ==
                  match.username!.trim().toLowerCase(),
            )
            .toList();
        final exact = byId.isNotEmpty
            ? byId.first
            : (byUsername.isNotEmpty ? byUsername.first : null);
        if (exact != null) {
          resolvedBio = exact.bio?.trim();
          debugPrint(
            '[PeoplePage] resolved bio via username search for userId=${match.userId}: "${resolvedBio ?? ''}"',
          );
        } else {
          debugPrint(
            '[PeoplePage] username search returned no exact user for userId=${match.userId}',
          );
        }
      } catch (e) {
        debugPrint('[PeoplePage] bio fallback fetch failed: $e');
      }
    }
    if (!mounted) return;
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: match.checkinId,
          venueId: match.venueId,
          userId: match.userId,
          userName: match.fullName,
          userUsername: match.username,
          isMatchedHint: true,
          chatIdHint: match.chatId,
          fallbackBio: (resolvedBio != null && resolvedBio.isNotEmpty)
              ? resolvedBio
              : null,
        ),
      ),
    )
        .then((_) => _loadData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        leading: const AppLogo(),
        title: Text(
          'Connections',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Find new friends',
            icon: const Icon(Icons.person_add_alt_1_rounded),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const FindFriendsPage()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Friends'),
            Tab(text: 'Following'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFriendsTab(isDark, theme),
          _buildFollowingTab(isDark, theme),
        ],
      ),
    );
  }

  Widget _buildFriendsTab(bool isDark, ThemeData theme) {
    if (_loading && _matches.isEmpty && _blockedUsers.isEmpty) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
          strokeWidth: 3,
        ),
      );
    }
    if (_error != null && _matches.isEmpty && _blockedUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Could not load matches',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      children: [
        if (_storiesLoading || _friendStoryGroups.isNotEmpty)
          _buildFriendStoryTray(isDark, theme),
        _buildSearchBar(isDark, theme),
        Expanded(child: _buildPeopleList(isDark, theme)),
      ],
    );
  }

  Widget _buildFriendStoryTray(bool isDark, ThemeData theme) {
    if (_storiesLoading) {
      return SizedBox(
        height: 96,
        child: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.primary,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(
            'Stories',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              letterSpacing: 0.5,
            ),
          ),
        ),
        SizedBox(
          height: 90,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _friendStoryGroups.length,
            itemBuilder: (context, index) {
              final group = _friendStoryGroups[index];
              final ids = group.stories.map((s) => s.id).toList();
              final allSeen = StoryViewedCache.allViewedSync(ids, _viewedStoryIds);
              return _FriendStoryBubble(
                group: group,
                allSeen: allSeen,
                onTap: () => _openFriendStory(index),
              );
            },
          ),
        ),
        Divider(
          height: 1,
          thickness: 1,
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200],
        ),
      ],
    );
  }

  Widget _buildFollowingTab(bool isDark, ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_city_rounded,
            size: 52,
            color: isDark ? Colors.white24 : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'No followed venues yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Follow venues to see their stories\nand stay updated.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(bool isDark, ThemeData theme) {
    return Container(
      color: theme.appBarTheme.backgroundColor,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFF1F5F9),
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
          controller: _searchController,
          onChanged: _onSearchChanged,
          style: theme.textTheme.bodyLarge,
          decoration: InputDecoration(
            hintText: 'Search by name...',
            hintStyle: TextStyle(
              color: isDark ? Colors.white38 : Colors.grey[500],
              fontSize: 15,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: isDark ? Colors.white54 : const Color(0xFF64748B),
              size: 22,
            ),
            suffixIcon: _searchQuery.trim().isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchDebounce?.cancel();
                      _searchController.clear();
                      _onSearchChanged('');
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
    );
  }

  Widget _buildPeopleList(bool isDark, ThemeData theme) {
    if (_matches.isEmpty) {
      final query = _searchQuery.trim();
      return Center(
        child: Text(
          query.isEmpty ? 'No friends yet' : 'No results for "$query"',
          style: TextStyle(
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
            fontSize: 15,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(reset: true),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        itemCount: _matches.length + (_isLoadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (_isLoadingMore && index == _matches.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          final match = _matches[index];
          return _buildFriendTile(match, isDark, theme);
        },
      ),
    );
  }

  Widget _buildFriendTile(MatchItem match, bool isDark, ThemeData theme) {
    final name = match.fullName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Slidable(
        key: ValueKey(match.matchId),
        enabled: !_deletingMatchIds.contains(match.matchId),
        startActionPane: ActionPane(
          motion: const DrawerMotion(),
          extentRatio: 0.28,
          children: [
            SlidableAction(
              onPressed: (_) => _deleteFriend(match),
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
          ],
        ),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : const Color(0xFFE2E8F0),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: ListTile(
              contentPadding: const EdgeInsets.all(12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              onTap: () => _openProfile(match),
              leading: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    width: 2,
                  ),
                  color: isDark
                      ? theme.colorScheme.primary.withValues(alpha: 0.1)
                      : const Color(0xFFEFF6FF),
                ),
                child: CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.transparent,
                  child: Text(
                    initial,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 22,
                      color: isDark
                          ? theme.colorScheme.primary
                          : const Color(0xFF1E293B),
                    ),
                  ),
                ),
              ),
              title: Text(
                name,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildActionButton(
                    Icons.chat_bubble_rounded,
                    () => _openMessage(match),
                    isDark,
                    theme,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(
          icon,
          color: isDark ? theme.colorScheme.primary : AppTheme.brandPrimary,
          size: 20,
        ),
        onPressed: onTap,
      ),
    );
  }
}

class _FriendStoryBubble extends StatelessWidget {
  final StoryGroup group;
  final bool allSeen;
  final VoidCallback onTap;

  const _FriendStoryBubble({
    required this.group,
    required this.onTap,
    this.allSeen = false,
  });

  @override
  Widget build(BuildContext context) {
    final imageUrl = group.bubbleImageUrl;
    final name = group.user.displayName;

    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(right: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: allSeen
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFFf09433), Color(0xFFbc2a8d)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: allSeen ? Colors.grey.shade400 : null,
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Theme.of(context).scaffoldBackgroundColor,
                ),
                child: CircleAvatar(
                  radius: 27,
                  backgroundImage: imageUrl != null && imageUrl.isNotEmpty
                      ? NetworkImage(imageUrl)
                      : null,
                  backgroundColor: Colors.grey.shade300,
                  child: imageUrl == null || imageUrl.isEmpty
                      ? Text(
                          name.isNotEmpty ? name[0].toUpperCase() : '?',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 5),
            SizedBox(
              width: 64,
              child: Text(
                name,
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
