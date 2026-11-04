import 'dart:async';
import '../data/friendship_changes.dart';
import 'block_user_dialog.dart';
import 'find_friends_page.dart';
import 'remove_friend_dialog.dart';
import 'user_actions_sheet.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/checkin/data/checkin_repository.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/core/ui/app_sheet.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/empty_state_message.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

/// Profildeki "Friends" istatistiğine basınca açılan liste.
/// Kullanıcının eşleştiği (match) kişileri listeler + isimle arama.
class FriendsListPage extends StatefulWidget {
  const FriendsListPage({super.key, this.repository, this.checkinRepository});
  final MatchRepository? repository;
  final CheckinRepository? checkinRepository;

  @override
  State<FriendsListPage> createState() => _FriendsListPageState();
}

class _FriendsListPageState extends State<FriendsListPage>
    with WidgetsBindingObserver {
  late final MatchRepository _repo = widget.repository ?? MatchRepository();
  late final CheckinRepository _checkinRepo =
      widget.checkinRepository ?? CheckinRepository();
  final _busy = <String>{};
  final _submitting = <String>{};
  int _loadVersion = 0;
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
    WidgetsBinding.instance.addObserver(this);
    FriendshipChanges.changes.addListener(_onFriendshipChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FriendshipChanges.changes.removeListener(_onFriendshipChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    final version = ++_loadVersion;
    setState(() {
      if (!silent) _loading = true;
      _error = null;
    });
    try {
      final matches = await _repo.getMatches();
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _all = matches;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || version != _loadVersion) return;
      setState(() {
        _error = 'Could not load friends.';
        _loading = false;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_load(silent: true));
  }

  void _onFriendshipChanged() {
    if (!mounted) return;
    final change = FriendshipChanges.changes.value;
    if (change != null && !change.active) {
      setState(() => _all.removeWhere((m) => m.userId == change.userId));
    }
    unawaited(_load(silent: true));
  }

  Future<void> _openFriendActions(MatchItem friend) {
    final username = friend.username ?? '';
    return showUserActionsSheet(
      context,
      title: friend.fullName,
      subtitle: username.isEmpty ? null : '@$username',
      onRemoveFriend: () => unawaited(_removeFriend(friend)),
      onReport: () => unawaited(_reportFriend(friend)),
      onToggleBlock: () => unawaited(_blockFriend(friend)),
    );
  }

  /// Aynı kişi için işlem bitmeden yenisi başlamaz; üç nokta o sürede pasiftir.
  Future<void> _runFriendAction(
    MatchItem friend,
    Future<void> Function() action,
  ) async {
    if (!_busy.add(friend.userId)) return;
    setState(() {});
    try {
      await action();
    } finally {
      _busy.remove(friend.userId);
      _submitting.remove(friend.userId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _removeFriend(MatchItem friend) =>
      _runFriendAction(friend, () async {
        try {
          final confirmed = await confirmRemoveFriend(context, friend.fullName);
          if (!confirmed || !mounted) return;
          setState(() => _submitting.add(friend.userId));
          await _repo.removeFriend(friend);
          if (!mounted) return;
          setState(() => _all.removeWhere((m) => m.userId == friend.userId));
          showFriendRemovedNotice(context);
        } catch (_) {
          if (!mounted) return;
          showRemoveFriendFailedNotice(context);
        }
      });

  Future<void> _blockFriend(MatchItem friend) => _runFriendAction(
    friend,
    () => confirmAndBlockUser(
      context,
      repository: _checkinRepo,
      targetUserId: friend.userId,
      onConfirmed: () => setState(() => _submitting.add(friend.userId)),
    ),
  );

  /// Hesap şikayeti kişiyi de engeller; liste bu değişiklikle kendini günceller.
  Future<void> _reportFriend(MatchItem friend) => _runFriendAction(
    friend,
    () => showReportUserSheet(
      context,
      targetUserId: friend.userId,
      repository: _checkinRepo,
    ),
  );

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
    final sort = await showAppSortSheet<String>(
      context,
      selected: _sort,
      options: const [
        AppSortOption(
          value: 'latest',
          label: 'Latest',
          subtitle: 'Newest friends first',
          icon: Icons.update_rounded,
        ),
        AppSortOption(
          value: 'earliest',
          label: 'Earliest',
          subtitle: 'Oldest friends first',
          icon: Icons.history_rounded,
        ),
      ],
    );
    if (sort != null && mounted) setState(() => _sort = sort);
  }

  Future<void> _openFindFriends() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const FindFriendsPage()));
    if (mounted) unawaited(_load(silent: true));
  }

  void _openMessage(MatchItem match) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: match.chatId,
          otherUserId: match.userId,
          otherName: match.fullName,
          otherPhotoUrl: match.userPhotoUrl ?? '',
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
          hintVenueId: match.venueId,
          hintVenueName: match.venueName,
          hintVenueType: match.venueType,
          hintVenuePhoto: match.venuePhoto,
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
          // Liste boşken arama ve sıralamanın işlevi yok; CTA öne çıkar.
          if (_all.isNotEmpty) ...[
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
          ],
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

    if (_all.isEmpty) {
      return SingleChildScrollView(
        padding: const EdgeInsets.only(top: 150, bottom: 32),
        child: EmptyStateMessage(
          icon: Icons.group_rounded,
          title: 'No friends yet',
          subtitle:
              'Find people by username. When you both choose Interested, they’ll appear here.',
          action: PrimaryButton(
            label: 'Find friends',
            onPressed: () => unawaited(_openFindFriends()),
          ),
        ),
      );
    }

    final items = _filtered;
    if (items.isEmpty) {
      return Center(
        child: Text(
          'No friends match "$_query".',
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
        // Yalnızca galeriden yüklenen profil avatarı; yoksa baş harf gösterilir.
        final avatarUrl = match.userPhotoUrl;
        final hasAvatar = avatarUrl != null && avatarUrl.isNotEmpty;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          onTap: () => _openProfile(match),
          leading: CircleAvatar(
            radius: 24,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: hasAvatar
                ? ClipOval(
                    child: CachedImage(
                      avatarUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      mediaReference: match.userPhotoReference,
                    ),
                  )
                : Text(
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
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  Icons.chat_bubble_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                tooltip: 'Message',
                onPressed: _busy.contains(match.userId)
                    ? null
                    : () => _openMessage(match),
              ),
              if (_submitting.contains(match.userId))
                const SizedBox(
                  width: 48,
                  child: Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Friend options',
                  icon: const Icon(Icons.more_horiz),
                  color: onSurface.withValues(alpha: 0.7),
                  onPressed: _busy.contains(match.userId)
                      ? null
                      : () => unawaited(_openFriendActions(match)),
                ),
            ],
          ),
        );
      },
    );
  }
}
