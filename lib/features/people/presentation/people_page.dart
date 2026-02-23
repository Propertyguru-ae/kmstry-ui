import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/people/data/blocked_user_model.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

enum PeopleListTab { friends, blocked }

class PeoplePage extends StatefulWidget {
  const PeoplePage({super.key});

  @override
  State<PeoplePage> createState() => _PeoplePageState();
}

class _PeoplePageState extends State<PeoplePage> {
  final MatchRepository _repo = MatchRepository();
  final TextEditingController _searchController = TextEditingController();
  List<MatchItem> _allMatches = [];
  List<MatchItem> _matches = [];
  List<BlockedUser> _blockedUsers = [];
  bool _loading = true;
  bool _unblocking = false;
  String? _error;
  PeopleListTab _selectedTab = PeopleListTab.friends;

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
        _allMatches = list;
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

  List<BlockedUser> get _filteredBlockedUsers {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _blockedUsers;
    return _blockedUsers
        .where((u) => u.fullName.toLowerCase().contains(query))
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

  void _openBlockedProfile(BlockedUser user) {
    MatchItem? matched;
    for (final m in _allMatches) {
      if (m.userId == user.userId) {
        matched = m;
        break;
      }
    }

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          userId: user.userId,
          userName: user.fullName,
          // Blocked listten acilan profilde unblock sonrasi direkt Message akisi hedeflenir.
          isMatchedHint: true,
          chatIdHint: matched?.chatId,
        ),
      ),
    )
        .then((_) => _loadData());
  }

  Future<void> _unblockUser(BlockedUser user) async {
    if (_unblocking) return;
    setState(() => _unblocking = true);
    try {
      await _repo.unblockUser(user.userId);
      if (!mounted) return;
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not unblock user.')),
      );
    } finally {
      if (mounted) setState(() => _unblocking = false);
    }
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text(
          'Friends',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.w900,
            fontSize: 22,
            letterSpacing: -0.8,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: Colors.grey[200], height: 1),
        ),
      ),
      body: _loading && _matches.isEmpty && _blockedUsers.isEmpty
          ? const Center(
              child: CircularProgressIndicator(
                color: Colors.blueAccent,
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
                      style: TextStyle(color: Colors.grey[700]),
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
                _buildSearchBar(),
                _buildTabHeader(),
                Expanded(child: _buildPeopleList()),
              ],
            ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
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
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: 'Search by name...',
            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 15),
            prefixIcon: const Icon(
              Icons.search_rounded,
              color: Color(0xFF64748B),
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

  Widget _buildPeopleList() {
    final friends = _filteredMatches;
    final blocked = _filteredBlockedUsers;
    if (friends.isEmpty && blocked.isEmpty) {
      return const Center(
        child: Text(
          'No friends yet',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 15),
        ),
      );
    }

    final activeFriends = _selectedTab == PeopleListTab.friends;
    final activeItems = activeFriends ? friends : blocked;

    if (activeItems.isEmpty) {
      return Center(
        child: Text(
          activeFriends ? 'No friends yet' : 'No blocked users',
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
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
        children: activeFriends
            ? friends.map(_buildFriendTile).toList()
            : blocked.map(_buildBlockedTile).toList(),
      ),
    );
  }

  Widget _buildTabHeader() {
    final friendsCount = _matches.length;
    final blockedCount = _blockedUsers.length;
    //debugPrint('FRIENDS COUNT :  $friendsCount');
    debugPrint('BLOCKED COUNT :  $blockedCount');
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          _buildTabButton(
            label: 'Friends ($friendsCount)',
            selected: _selectedTab == PeopleListTab.friends,
            onTap: () => setState(() => _selectedTab = PeopleListTab.friends),
          ),
          const SizedBox(width: 10),
          _buildTabButton(
            label: 'Blocked ($blockedCount)',
            selected: _selectedTab == PeopleListTab.blocked,
            onTap: () => setState(() => _selectedTab = PeopleListTab.blocked),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF0F172A) : const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF334155),
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildFriendTile(MatchItem match) {
    final name = match.fullName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
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
                color: Colors.blueAccent.withValues(alpha: 0.2),
                width: 2,
              ),
              color: const Color(0xFFEFF6FF),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: const Color(0xFFEFF6FF),
              child: Text(
                initial,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 22,
                  color: Color(0xFF1E293B),
                ),
              ),
            ),
          ),
          title: Text(
            name,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: Color(0xFF0F172A),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildActionButton(Icons.call_rounded, () {}),
              const SizedBox(width: 8),
              _buildActionButton(
                Icons.chat_bubble_rounded,
                () => _openMessage(match),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlockedTile(BlockedUser user) {
    final name = user.fullName;
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onTap: () => _openBlockedProfile(user),
        leading: CircleAvatar(
          radius: 28,
          backgroundColor: const Color(0xFFF1F5F9),
          child: Text(
            initial,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 22,
              color: Color(0xFF334155),
            ),
          ),
        ),
        title: Text(
          name,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: Color(0xFF0F172A),
          ),
        ),
        trailing: TextButton(
          onPressed: _unblocking ? null : () => _unblockUser(user),
          child: const Text('Unblock'),
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, VoidCallback onTap) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        visualDensity: VisualDensity.compact,
        icon: Icon(icon, color: Colors.blueAccent, size: 20),
        onPressed: onTap,
      ),
    );
  }
}
