import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final MatchRepository _repo = MatchRepository();
  final TextEditingController _searchController = TextEditingController();
  List<MatchItem> _matches = [];
  List<BlockedUser> _blockedUsers = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() => setState(() {});

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _repo.getMatches(),
        _repo.getBlockedUsers(),
      ]);
      final list = results[0] as List<MatchItem>;
      final blocked = results[1] as List<BlockedUser>;
      debugPrint('BLOCKED :  $blocked');
      final blockedIds = blocked.map((b) => b.userId).toSet();
      if (!mounted) return;
      setState(() {
        _matches = list.where((m) => !blockedIds.contains(m.userId)).toList();
        _blockedUsers = blocked;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
    }
  }

  List<MatchItem> get _filteredMatches {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _matches;
    return _matches
        .where((m) => m.fullName.toLowerCase().contains(query))
        .toList();
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
          isMatchedHint: true,
          chatIdHint: match.chatId,
        ),
      ),
    )
        .then((_) => _loadData());
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
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
    final friends = _filteredMatches;
    if (friends.isEmpty) {
      return Center(
        child: Text(
          'No friends yet',
          style: TextStyle(
            color: isDark ? Colors.white54 : const Color(0xFF64748B),
            fontSize: 15,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: friends.map((m) => _buildFriendTile(m, isDark, theme)).toList(),
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
              _buildActionButton(Icons.call_rounded, () {}, isDark, theme),
              const SizedBox(width: 8),
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
          color: isDark ? theme.colorScheme.primary : Colors.blueAccent,
          size: 20,
        ),
        onPressed: onTap,
      ),
    );
  }
}
