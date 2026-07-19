import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

/// Profildeki "Friends" istatistiğine basınca açılan liste.
/// Kullanıcının eşleştiği (match) kişileri listeler + isimle arama.
class FriendsListPage extends StatefulWidget {
  const FriendsListPage({super.key});

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage> {
  final MatchRepository _repo = MatchRepository();
  final TextEditingController _searchController = TextEditingController();

  List<MatchItem> _all = [];
  bool _loading = true;
  String? _error;
  String _query = '';

  /// 'latest' | 'earliest'.
  /// Backend zaten en yeni eşleşmeyi önce döndürür (created_at DESC), o yüzden
  /// latest liste sırasını korur; earliest listeyi ters çevirir.
  String _sort = 'latest';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final matches = await _repo.getMatches();
      if (!mounted) return;
      setState(() {
        _all = matches;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load friends.';
        _loading = false;
      });
    }
  }

  List<MatchItem> get _filtered {
    final q = _query.trim().toLowerCase();
    var list = q.isEmpty
        ? List<MatchItem>.from(_all)
        : _all
              .where(
                (m) =>
                    m.fullName.toLowerCase().contains(q) ||
                    (m.username ?? '').toLowerCase().contains(q),
              )
              .toList();
    if (_sort == 'earliest') list = list.reversed.toList();
    return list;
  }

  String get _sortLabel => _sort == 'earliest' ? 'Earliest' : 'Latest';

  Future<void> _openSortSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark
          ? const Color(0xFF161C28)
          : theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget option(String key, String label) {
          final selected = _sort == key;
          return ListTile(
            title: Text(label),
            trailing: selected
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
            onTap: () {
              setState(() => _sort = key);
              Navigator.pop(ctx);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort by',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              option('latest', 'Latest'),
              option('earliest', 'Earliest'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _openMessage(MatchItem match) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: match.chatId,
          otherUserId: match.userId,
          otherName: match.fullName,
          otherPhotoUrl: '',
        ),
      ),
    );
  }

  void _openProfile(MatchItem match) {
    final bio = match.bio?.trim();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          checkinId: match.checkinId,
          venueId: match.venueId,
          userId: match.userId,
          userName: match.fullName,
          userUsername: match.username,
          isMatchedHint: true,
          chatIdHint: match.chatId,
          fallbackBio: (bio != null && bio.isNotEmpty) ? bio : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Friends',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          // ── Search by name ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: onSurface),
              decoration: InputDecoration(
                hintText: 'Search by name',
                prefixIcon: const Icon(Icons.search_rounded),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.06)
                    : const Color(0xFFF1F3F5),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
              ),
            ),
          ),
          // ── Sort by ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(
              children: [
                Text(
                  'Sort by: ',
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.6),
                    fontSize: 13.5,
                  ),
                ),
                Text(
                  _sortLabel,
                  style: TextStyle(
                    color: onSurface,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Sort',
                  icon: Icon(Icons.swap_vert_rounded, color: onSurface),
                  onPressed: _openSortSheet,
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(theme, isDark, onSurface)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, bool isDark, Color onSurface) {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: TextStyle(color: onSurface)),
            const SizedBox(height: 12),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          _query.isEmpty ? 'No friends yet.' : 'No friends match "$_query".',
          style: TextStyle(color: onSurface.withValues(alpha: 0.6)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: onSurface.withValues(alpha: 0.06)),
      itemBuilder: (context, index) {
        final match = items[index];
        final name = match.fullName;
        final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          onTap: () => _openProfile(match),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              initial,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          title: Text(
            name,
            style: TextStyle(
              color: onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
          subtitle: (match.username ?? '').isNotEmpty
              ? Text(
                  '@${match.username}',
                  style: TextStyle(color: onSurface.withValues(alpha: 0.5)),
                )
              : null,
          trailing: IconButton(
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            tooltip: 'Message',
            onPressed: () => _openMessage(match),
          ),
        );
      },
    );
  }
}
