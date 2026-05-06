import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/people/presentation/find_friends_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  static const int _pageSize = 20;
  final MatchRepository _repo = MatchRepository();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  Timer? _searchDebounce;
  List<MatchItem> _matches = [];
  List<BlockedUser> _blockedUsers = [];
  String _searchQuery = '';
  String? _nextCursor;
  bool _hasMore = false;
  bool _isLoadingMore = false;
  bool _loading = true;
  String? _error;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _scrollController.addListener(_onScroll);
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
      final blocked = reset ? await _repo.getBlockedUsers() : _blockedUsers;
      final result = await _repo.getMatchesPage(
        query: query.isEmpty ? null : query,
        limit: _pageSize,
        cursor: reset ? null : _nextCursor,
      );
      final blockedIds = blocked.map((b) => b.userId).toSet();
      final pageItems =
          result.items.where((m) => !blockedIds.contains(m.userId)).toList();
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

  void _openProfile(MatchItem match) {
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
        ),
      ),
    )
        .then((_) => _loadData());
  }

  @override
  void dispose() {
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
        leading: IconButton(
          tooltip: 'Find new friends',
          icon: const Icon(Icons.person_add_alt_1_rounded),
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FindFriendsPage()),
            );
          },
        ),
        title: Text(
          'Friends',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -0.8,
          ),
        ),
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey[200], 
            height: 1,
          ),
        ),
      ),
      body: _loading && _matches.isEmpty && _blockedUsers.isEmpty
          ? Center(
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
                strokeWidth: 3,
              ),
            )
          : _error != null && _matches.isEmpty && _blockedUsers.isEmpty
          ? Center(
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
            )
          : Column(
              children: [
                _buildSearchBar(isDark, theme),
                Expanded(child: _buildPeopleList(isDark, theme)),
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
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
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
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.surface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE2E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
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
                color: theme.colorScheme.primary.withOpacity(0.2),
                width: 2,
              ),
              color: isDark ? theme.colorScheme.primary.withOpacity(0.1) : const Color(0xFFEFF6FF),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: Colors.transparent,
              child: Text(
                initial,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: isDark ? theme.colorScheme.primary : const Color(0xFF1E293B),
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
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap, bool isDark, ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFEFF6FF),
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
