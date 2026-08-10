import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';

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
      if (state == ChatRealtimeConnectionState.reconnecting) {
        debugPrint('💬 [Messages] Socket reconnecting');
        _scheduleRealtimeRefresh();
      }
    });

    _realtimeEventsSub = _realtime.events.listen((envelope) {
      if (!mounted) return;
      debugPrint(
        '💬 [Messages] Event yakalandi: ${envelope.event}, payload=${envelope.payload}',
      );
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
      loadChats();
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
    final unread = _readIntField(payload, const ['unreadCount', 'unread_count']);
    final preview = _readStringField(
      payload,
      const ['lastMessagePreview', 'last_message_preview'],
    );
    final lastMessageAt = _readDateField(
      payload,
      const ['lastMessageAt', 'last_message_at', 'createdAt', 'created_at'],
    );
    final hasAnyPatchData = unread != null || preview != null || lastMessageAt != null;
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
  Future<void> loadChats() async {
    final activeQuery = _searchQuery.trim();
    final requestId = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = activeQuery.isEmpty
          ? await _repo.getChats()
          : await _repo.searchChatsByParticipantName(activeQuery);

      if (!mounted || requestId != _requestId) return;
      setState(() {
        _chats = list;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ getChats error: $e');
      if (!mounted) return;
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

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Messages',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
       
        ],
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
                hintText: 'Search messages',
                hintStyle: TextStyle(
                  color: isDark ? Colors.white38 : Colors.grey,
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: isDark ? Colors.white38 : Colors.grey,
                ),
                suffixIcon: _searchQuery.trim().isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          _searchQuery = '';
                          loadChats();
                        },
                      ),
                filled: true,
                fillColor: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
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
      return Center(
        child: Text(
          query.isEmpty ? 'No messages yet' : 'No results for "$query"',
          style: TextStyle(color: isDark ? Colors.white38 : Colors.grey),
        ),
      );
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.brandPrimary
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[200]),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? const Color(0xFF0D1322)
                : (isDark ? Colors.white70 : Colors.black54),
            fontWeight: FontWeight.w600,
          ),
        ),
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
            leading: Container(
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
            ),
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
                    otherPhotoUrl: '',
                  ),
                ),
              );
              if (!mounted) return;
              loadChats();
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
