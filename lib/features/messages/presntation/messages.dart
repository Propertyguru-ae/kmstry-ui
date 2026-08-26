import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/messages/presntation/message_settings_page.dart';
import 'package:kmstry_frontend/core/ui/app_logo.dart';

const _kKmstryBlue = Color(0xFF1A9FE8);
const _kKmstryTeal = Color(0xFF1FD9A8);

class DmListPage extends StatefulWidget {
  const DmListPage({super.key});

  @override
  State<DmListPage> createState() => DmListPageState();
}

class DmListPageState extends State<DmListPage> with WidgetsBindingObserver {
  final ChatRepository _repo = ChatRepository();
  final ChatRealtimeService _realtime = ChatRealtimeService();
  final TextEditingController _searchController = TextEditingController();
  String _selectedFilter = 'All';
  List<ChatListItem> _chats = [];
  bool _loading = true;
  String? _error;
  String? _currentUserId;
  String _searchQuery = '';
  Timer? _searchDebounce;
  int _requestId = 0;
  DateTime? _lastFetchTime;
  final Set<String> _deletingChatIds = <String>{};
  StreamSubscription<ChatRealtimeEnvelope>? _realtimeEventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _realtimeStateSub;
  Timer? _realtimeRefreshDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('💬 [Messages] Listener baglaniyor');
    _bindRealtimeStreams();
    unawaited(_connectRealtime());
    _loadCurrentUser();
    loadChats();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('💬 [Messages] Listener temizleniyor');
    _realtimeEventsSub?.cancel();
    _realtimeStateSub?.cancel();
    _realtimeRefreshDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_connectRealtime());
    _scheduleRealtimeRefresh();
  }

  void _bindRealtimeStreams() {
    _realtimeStateSub = _realtime.connectionState.listen((state) {
      if (!mounted) return;
      if (state == ChatRealtimeConnectionState.connected) {
        debugPrint('💬 [Messages] Socket connected, liste yenileniyor');
        _scheduleRealtimeRefresh();
      }
      // reconnecting sırasında ağ düşük olabileceği için refresh tetiklenmez
    });

    _realtimeEventsSub = _realtime.events.listen((envelope) {
      if (!mounted) return;
      debugPrint('💬 [Messages] Event yakalandi: ${envelope.event}');
      switch (envelope.event) {
        case 'chat.unread.updated':
          if (!_applyChatRowUpdate(envelope.payload)) {
            debugPrint('💬 [Messages] Local update yok, fallback refresh');
            _scheduleRealtimeRefresh();
          }
          return;
        case 'chat.updated':
          if (!_applyChatRowUpdate(envelope.payload)) {
            debugPrint('💬 [Messages] chat.updated local update yok, refresh');
            _scheduleRealtimeRefresh();
          }
          return;
        case 'message.created':
          if (!_applyChatRowUpdate(envelope.payload)) {
            debugPrint('💬 [Messages] message.created fallback refresh');
            _scheduleRealtimeRefresh();
          }
          return;
        case 'message.updated':
        case 'message.deleted':
        case 'chat.read':
        case 'socket.reconnected':
          debugPrint('💬 [Messages] Liste refresh tetiklendi');
          _scheduleRealtimeRefresh();
          return;
      }
    });
  }

  Future<void> _connectRealtime() async {
    final token = await SecureStorage.getAccessToken();
    if (!mounted || token == null || token.trim().isEmpty) return;
    await _realtime.connectWithToken(token: token);
  }

  void _scheduleRealtimeRefresh() {
    _realtimeRefreshDebounce?.cancel();
    _realtimeRefreshDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      debugPrint('💬 [Messages] GET /chats refresh calisti');
      loadChats(silent: true);
    });
  }

  String? _readStringField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  int? _readIntField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is int) return value;
      if (value == null) continue;
      final parsed = int.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  DateTime? _readDateField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final parsed = DateTime.tryParse(value.toString());
      if (parsed != null) return parsed;
    }
    return null;
  }

  bool _applyChatRowUpdate(Map<String, dynamic> payload) {
    final chatId = _readStringField(payload, const ['chatId', 'chat_id']);
    if (chatId == null) return false;
    final unread = _readIntField(payload, const [
      'unreadCount',
      'unread_count',
    ]);
    final preview = _readStringField(payload, const [
      'lastMessagePreview',
      'last_message_preview',
    ]);
    final lastMessageAt = _readDateField(payload, const [
      'lastMessageAt',
      'last_message_at',
      'createdAt',
      'created_at',
    ]);
    final hasAnyPatchData =
        unread != null || preview != null || lastMessageAt != null;
    if (!hasAnyPatchData) return false;

    final index = _chats.indexWhere((chat) => chat.id == chatId);
    if (index < 0) return false;
    final current = _chats[index];
    final updated = ChatListItem(
      id: current.id,
      lastMessageAt: lastMessageAt ?? current.lastMessageAt,
      unreadCount: unread ?? current.unreadCount,
      lastMessagePreview: preview ?? current.lastMessagePreview,
      otherUser: current.otherUser,
      user1: current.user1,
      user2: current.user2,
    );

    if (!mounted) return true;
    setState(() {
      final next = List<ChatListItem>.from(_chats);
      next[index] = updated;
      next.sort((a, b) {
        final ad = a.lastMessageAt;
        final bd = b.lastMessageAt;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return bd.compareTo(ad);
      });
      _chats = next;
    });
    debugPrint(
      '💬 [Messages] Local row guncellendi: chatId=$chatId unread=${updated.unreadCount}',
    );
    return true;
  }

  Future<void> _loadCurrentUser() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() => _currentUserId = me['id'] as String?);
    } catch (_) {}
  }

  /// Called when returning from MessageDetailPage or when DM tab is selected (DM list refresh rule).
  /// [silent]: true iken yükleme göstergesi ve hata ekranı gösterilmez; mevcut data korunur.
  /// Sohbet listesini getirir; geçici hatalarda (timeout / ağ / 5xx) kısa
  /// backoff ile birkaç kez dener. Böylece cold/slow backend veya anlık ağ
  /// dalgalanmasında kullanıcı gereksiz yere "Could not load chats" görmez.
  /// Gerçek istemci hatalarında (4xx) beklemeden yükseltir.
  Future<List<ChatListItem>> _fetchChatListWithRetry(String activeQuery) async {
    const maxAttempts = 3;
    for (var attempt = 1; ; attempt++) {
      try {
        return activeQuery.isEmpty
            ? await _repo.getChats()
            : await _repo.searchChatsByParticipantName(activeQuery);
      } catch (e) {
        // 429 (rate limit) geçicidir → backoff ile tekrar dene. Diğer 4xx'ler
        // gerçek istemci hatasıdır → beklemeden yükselt. 5xx / ağ / timeout da
        // geçici sayılıp tekrar denenir.
        final isRetriableClientError = e is ApiException && e.statusCode == 429;
        final isNonRetriableClientError =
            e is ApiException &&
            e.statusCode >= 400 &&
            e.statusCode < 500 &&
            !isRetriableClientError;
        if (isNonRetriableClientError || attempt >= maxAttempts) rethrow;
        await Future<void>.delayed(Duration(milliseconds: 400 * attempt));
        if (!mounted) rethrow;
      }
    }
  }

  Future<void> loadChats({bool silent = false}) async {
    final now = DateTime.now();
    if (silent &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(seconds: 3)) {
      return;
    }
    _lastFetchTime = now;
    final activeQuery = _searchQuery.trim();
    final requestId = ++_requestId;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _fetchChatListWithRetry(activeQuery);

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _chats = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      debugPrint('❌ getChats error: $e');
      if (!mounted || requestId != _requestId) return;
      if (silent) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value;
    });
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) return;
      loadChats();
    });
  }

  Color _avatarColor(String seed) {
    final colors = <Color>[
      const Color(0xFF4F46E5), // indigo
      const Color(0xFF0EA5E9), // sky
      const Color(0xFF10B981), // emerald
      const Color(0xFFF59E0B), // amber
      const Color(0xFFEF4444), // red
      const Color(0xFF8B5CF6), // violet
      AppTheme.brandPrimary, // brand blue
    ];

    final index = seed.hashCode.abs() % colors.length;
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final colors = theme.colorScheme;
    final bg = isDark ? const Color(0xFF0B0F17) : theme.scaffoldBackgroundColor;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const AppLogo(),
        title: Text(
          'Messages',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colors.onSurface),
            tooltip: 'Message settings',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MessageSettingsPage()),
            ),
          ),
          const SizedBox(width: 4),
        ],
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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodyLarge,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.48)
                      : Colors.black.withValues(alpha: 0.46),
                  fontWeight: FontWeight.w600,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: _kKmstryBlue.withValues(alpha: 0.90),
                ),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.70)
                              : Colors.black.withValues(alpha: 0.58),
                        ),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          _searchQuery = '';
                          loadChats();
                        },
                      ),
                filled: true,
                fillColor: isDark
                    ? const Color(0xFF101A2A)
                    : const Color(0xFFF7FAFD),
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: isDark
                        ? _kKmstryBlue.withValues(alpha: 0.22)
                        : _kKmstryBlue.withValues(alpha: 0.14),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: isDark
                        ? _kKmstryBlue.withValues(alpha: 0.22)
                        : _kKmstryBlue.withValues(alpha: 0.14),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide(
                    color: _kKmstryBlue.withValues(alpha: 0.70),
                    width: 1.2,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                _buildFilterChip('All', isDark, theme),
                const SizedBox(width: 8),
                _buildFilterChip('Unread', isDark, theme),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(child: _buildListContent(isDark, theme)),
        ],
      ),
    );
  }

  Widget _buildListContent(bool isDark, ThemeData theme) {
    if (_loading && _chats.isEmpty) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }
    if (_error != null && _chats.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('Could not load chats', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              TextButton(onPressed: loadChats, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final list = _buildFilteredChats();
    if (list.isEmpty) {
      final query = _searchQuery.trim();
      return _MessagesEmptyState(isDark: isDark, query: query);
    }
    return RefreshIndicator(
      onRefresh: loadChats,
      child: ListView.builder(
        itemCount: list.length,
        itemBuilder: (context, index) {
          final chat = list[index];
          return _buildChatTile(chat, isDark, theme);
        },
      ),
    );
  }

  List<ChatListItem> _buildFilteredChats() {
    if (_selectedFilter == 'Unread') {
      return _chats.where((c) => c.unreadCount > 0).toList();
    }
    return _chats;
  }

  Future<bool> _confirmDeleteDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete conversation'),

          content: const Text('This conversation will be permanently removed.'),
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

  Future<void> _deleteChat(ChatListItem chat) async {
    if (_deletingChatIds.contains(chat.id)) return;
    final confirmed = await _confirmDeleteDialog();
    if (!confirmed || !mounted) return;

    final previousChats = List<ChatListItem>.from(_chats);
    setState(() {
      _deletingChatIds.add(chat.id);
      _chats = _chats.where((c) => c.id != chat.id).toList();
    });

    try {
      await _repo.deleteChat(chat.id);
      if (!mounted) return;
      setState(() {
        _deletingChatIds.remove(chat.id);
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat deleted')));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingChatIds.remove(chat.id);
        _chats = previousChats;
      });
      await showPremiumErrorDialog(
        context,
        message:
            'Chat could not be deleted: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
      );
    }
  }

  Widget _buildFilterChip(String label, bool isDark, ThemeData theme) {
    final isSelected = _selectedFilter == label;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedFilter = label;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: isSelected
              ? (isDark
                    ? const Color(0xFF0A1422).withValues(alpha: 0.94)
                    : _kKmstryBlue)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.07)
                    : const Color(0xFFF4F7FB)),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? _kKmstryBlue.withValues(alpha: 0.76)
                : (isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.05)),
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    blurRadius: 16,
                    offset: const Offset(0, 5),
                    color: _kKmstryBlue.withValues(alpha: 0.22),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSelected) ...[
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _kKmstryTeal,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark
                          ? Colors.white.withValues(alpha: 0.72)
                          : Colors.black.withValues(alpha: 0.58)),
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Sohbet listesi avatarı: fotoğrafı varsa fotoğraf, yoksa renkli baş harf.
  Widget _buildChatAvatar(
    String? photo,
    String name,
    Color avatarColor,
    bool isDark,
  ) {
    final hasPhoto = photo != null && photo.trim().isNotEmpty;
    Widget initial() => Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark
            ? avatarColor.withValues(alpha: 0.2)
            : avatarColor.withValues(alpha: 0.15),
      ),
      alignment: Alignment.center,
      child: Text(
        name.isNotEmpty ? name[0].toUpperCase() : '?',
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: isDark ? avatarColor.withValues(alpha: 0.9) : avatarColor,
        ),
      ),
    );
    if (!hasPhoto) return initial();
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedImage(
        photo,
        width: 55,
        height: 55,
        fit: BoxFit.cover,
        errorWidget: (_) => initial(),
      ),
    );
  }

  Widget _buildChatTile(ChatListItem chat, bool isDark, ThemeData theme) {
    final other = chat.getDisplayUser(_currentUserId);
    final name = other?.fullName ?? 'Unknown';
    final avatarColor = _avatarColor(name);
    final preview = chat.lastMessagePreview ?? '';
    final time = _formatTime(chat.lastMessageAt);
    final unread = chat.unreadCount;

    return Column(
      children: [
        Slidable(
          key: ValueKey(chat.id),
          enabled: !_deletingChatIds.contains(chat.id),
          startActionPane: ActionPane(
            motion: const DrawerMotion(),
            extentRatio: 0.28,
            children: [
              SlidableAction(
                onPressed: (_) => _deleteChat(chat),
                backgroundColor: theme.colorScheme.error,
                foregroundColor: theme.colorScheme.onError,
                icon: Icons.delete_outline,
                label: 'Delete',
              ),
            ],
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            leading: _buildChatAvatar(other?.photo, name, avatarColor, isDark),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  name,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  time,
                  style: TextStyle(
                    color: isDark ? Colors.white38 : Colors.grey,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if (unread > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : unread.toString(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            onTap: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => MessageDetailPage(
                    chatId: chat.id,
                    otherUserId: other?.id ?? '',
                    otherName: name,
                    otherPhotoUrl: other?.photo ?? '',
                  ),
                ),
              );
              if (!mounted) return;
              loadChats(silent: true);
            },
          ),
        ),
        Divider(
          height: 1,
          indent: 85,
          endIndent: 16,
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : const Color(0xFFEEEEEE),
        ),
      ],
    );
  }

  String _formatTime(DateTime? date) {
    if (date == null) return '';
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hour ago';
    if (diff.inDays < 2) return '1 day ago';
    return '${diff.inDays} days ago';
  }
}

class _MessagesEmptyState extends StatelessWidget {
  const _MessagesEmptyState({required this.isDark, required this.query});

  final bool isDark;
  final String query;

  @override
  Widget build(BuildContext context) {
    final hasQuery = query.isNotEmpty;
    final title = hasQuery ? 'No results found' : 'No chats yet';
    final message = hasQuery
        ? 'Try a different name or message.'
        : 'Check in, meet people nearby, and start the conversation.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 340),
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 22),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF101A2A) : const Color(0xFFF8FBFD),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? _kKmstryBlue.withValues(alpha: 0.16)
                  : _kKmstryBlue.withValues(alpha: 0.10),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 26,
                offset: const Offset(0, 14),
                color: isDark
                    ? _kKmstryBlue.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.05),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    colors: [
                      _kKmstryBlue.withValues(alpha: 0.22),
                      _kKmstryTeal.withValues(alpha: 0.18),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: _kKmstryBlue.withValues(alpha: 0.20),
                  ),
                ),
                child: Icon(
                  hasQuery
                      ? Icons.search_off_rounded
                      : Icons.chat_bubble_outline_rounded,
                  color: _kKmstryBlue,
                  size: 30,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.62)
                      : Colors.black.withValues(alpha: 0.55),
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              if (!hasQuery) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: const LinearGradient(
                      colors: [_kKmstryBlue, _kKmstryTeal],
                    ),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                        color: _kKmstryBlue.withValues(alpha: 0.24),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.add_location_alt_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 7),
                      Text(
                        'Start with a check-in',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
