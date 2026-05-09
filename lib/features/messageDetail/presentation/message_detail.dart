import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';

class MessageDetailPage extends StatefulWidget {
  /// When null, this is a new conversation; first send will create the chat.
  final String? chatId;
  final String otherUserId;
  final String otherName;
  final String otherPhotoUrl;

  const MessageDetailPage({
    super.key,
    this.chatId,
    required this.otherUserId,
    required this.otherName,
    required this.otherPhotoUrl,
  });

  @override
  State<MessageDetailPage> createState() => _MessageDetailPageState();
}

class _MessageDetailPageState extends State<MessageDetailPage>
    with WidgetsBindingObserver {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatRealtimeService _realtime = ChatRealtimeService();

  ChatDetail? _chat;

  /// Effective chat id: widget.chatId or set after createChat on first send.
  String? _chatId;
  bool _loading = true;
  String? _error;
  String? _currentUserId;
  bool _sending = false;
  bool _loadingMore = false;
  bool _hasReachedEndOfMessages = false;
  final Set<String> _deletingMessageIds = <String>{};
  StreamSubscription<ChatRealtimeEnvelope>? _realtimeEventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _realtimeStateSub;
  Timer? _typingStartDebounce;
  Timer? _typingStopDebounce;
  Timer? _remoteTypingTimeout;
  DateTime? _lastCursor;
  DateTime? _otherUserReadAt;
  bool _typingStartSent = false;
  bool _isOtherTyping = false;
  bool _isOtherOnline = true;
  bool _isSocketConnected = false;
  bool _isSocketReconnecting = false;
  int _localMessageCounter = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    debugPrint('💬 [Detail] Listener baglaniyor');
    _chatId = _normalizeChatId(widget.chatId);
    _bindRealtimeStreams();
    _loadCurrentUser();
    if (_chatId != null) {
      _loadChat();
    } else {
      setState(() => _loading = false);
    }
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    debugPrint('💬 [Detail] Listener temizleniyor');
    final cid = _chatId;
    if (cid != null && cid.isNotEmpty) {
      debugPrint('💬 [Detail] chat.leave => $cid');
      _realtime.leaveChat(cid);
    }
    _typingStartDebounce?.cancel();
    _typingStopDebounce?.cancel();
    _remoteTypingTimeout?.cancel();
    _realtimeEventsSub?.cancel();
    _realtimeStateSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_connectRealtimeIfPossible());
    unawaited(_catchUpMessages());
  }

  void _bindRealtimeStreams() {
    _realtimeEventsSub = _realtime.events.listen(_handleRealtimeEvent);
    _realtimeStateSub = _realtime.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _isSocketConnected = state == ChatRealtimeConnectionState.connected;
        _isSocketReconnecting = state == ChatRealtimeConnectionState.reconnecting;
      });
    });
  }

  void _onScroll() {
    if (_loadingMore || _loading || _chat == null || _hasReachedEndOfMessages) {
      return;
    }
    if (_scrollController.offset <= 100 && _scrollController.hasClients) {
      _loadMoreMessages();
    }
  }

  void _scrollToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Future<void> _loadCurrentUser() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _currentUserId = me['id'] as String?;
      });
      unawaited(_connectRealtimeIfPossible());
    } catch (_) {}
  }

  /// Boş string veya sadece boşluk gelen chatId'yi yok say.
  String? _normalizeChatId(String? id) {
    if (id == null) return null;
    final t = id.trim();
    return t.isEmpty ? null : t;
  }

  String _nextClientMessageId() {
    _localMessageCounter += 1;
    final random = Random.secure();
    String hex(int length) {
      const chars = '0123456789abcdef';
      return List<String>.generate(
        length,
        (_) => chars[random.nextInt(chars.length)],
      ).join();
    }

    final timePart = DateTime.now().microsecondsSinceEpoch
        .toRadixString(16)
        .padLeft(12, '0');
    final counterPart = _localMessageCounter.toRadixString(16).padLeft(4, '0');
    // UUID-benzeri format: 8-4-4-4-12
    return '${hex(8)}-${hex(4)}-4${hex(3)}-${hex(4)}-$timePart$counterPart';
  }

  DateTime? _parseIsoDateTime(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String? _readStringField(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      final text = value?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
    return null;
  }

  void _touchCursor(DateTime? ts) {
    if (ts == null) return;
    if (_lastCursor == null || ts.isAfter(_lastCursor!)) {
      _lastCursor = ts;
    }
  }

  void _refreshCursorFromMessages(List<ChatMessage> messages) {
    for (final message in messages) {
      _touchCursor(message.createdAt);
    }
  }

  Future<void> _connectRealtimeIfPossible() async {
    final cid = _chatId;
    if (cid == null || cid.isEmpty) return;
    final token = await SecureStorage.getAccessToken();
    if (token == null || token.isEmpty) return;
    await _realtime.connectWithToken(token: token);
    debugPrint('💬 [Detail] chat.join => $cid');
    _realtime.joinChat(cid);
    try {
      await _repo.markChatRead(cid);
    } catch (_) {}
  }

  Future<void> _catchUpMessages() async {
    final cid = _chatId;
    if (cid == null || cid.isEmpty) return;

    try {
      String? cursor = _lastCursor?.toUtc().toIso8601String();
      var loops = 0;
      while (loops < 6) {
        loops += 1;
        final page = await _repo.getMessagesSince(
          cid,
          cursor: cursor,
          limit: 100,
        );
        if (page.items.isEmpty) break;
        if (!mounted) return;
        for (final message in page.items) {
          _mergeOrInsertMessage(message, shouldScroll: false);
        }
        if (page.nextCursor == null || page.nextCursor!.isEmpty) break;
        cursor = page.nextCursor;
        _touchCursor(_parseIsoDateTime(page.nextCursor));
      }
    } catch (_) {}
  }

  void _handleRealtimeEvent(ChatRealtimeEnvelope envelope) {
    if (!mounted) return;
    final payload = envelope.payload;
    final eventChatId = _readStringField(payload, const ['chatId', 'chat_id']);
    final activeChatId = _chatId;
    final isChatEvent = envelope.event.startsWith('message.') ||
        envelope.event == 'chat.updated' ||
        envelope.event == 'chat.read' ||
        envelope.event.startsWith('typing.');

    if (isChatEvent &&
        activeChatId != null &&
        eventChatId != null &&
        eventChatId != activeChatId) {
      return;
    }

    _touchCursor(
      _parseIsoDateTime(payload['serverTimestamp'] ?? payload['server_timestamp']),
    );

    switch (envelope.event) {
      case 'socket.reconnected':
        unawaited(_catchUpMessages());
        return;
      case 'message.created':
      case 'message.updated':
        final rawMessage = payload['message'];
        if (rawMessage is! Map) return;
        final message = ChatMessage.fromJson(Map<String, dynamic>.from(rawMessage));
        _mergeOrInsertMessage(message);
        return;
      case 'message.deleted':
        final messageId = _readStringField(payload, const ['messageId', 'message_id']);
        if (messageId == null || messageId.isEmpty) return;
        _removeMessageById(messageId);
        return;
      case 'chat.updated':
        _touchCursor(
          _parseIsoDateTime(payload['lastMessageAt'] ?? payload['last_message_at']),
        );
        return;
      case 'chat.read':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != widget.otherUserId) return;
        final readAt = _parseIsoDateTime(payload['readAt'] ?? payload['read_at']);
        if (readAt == null) return;
        if (!mounted) return;
        setState(() {
          if (_otherUserReadAt == null || readAt.isAfter(_otherUserReadAt!)) {
            _otherUserReadAt = readAt;
          }
        });
        return;
      case 'presence.online':
      case 'presence.offline':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != widget.otherUserId) return;
        if (!mounted) return;
        setState(() {
          _isOtherOnline = envelope.event == 'presence.online';
        });
        return;
      case 'typing.start':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != widget.otherUserId) return;
        _remoteTypingTimeout?.cancel();
        setState(() => _isOtherTyping = true);
        _remoteTypingTimeout = Timer(const Duration(seconds: 4), () {
          if (!mounted) return;
          setState(() => _isOtherTyping = false);
        });
        return;
      case 'typing.stop':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != widget.otherUserId) return;
        _remoteTypingTimeout?.cancel();
        setState(() => _isOtherTyping = false);
        return;
      default:
        return;
    }
  }

  void _removeMessageById(String messageId) {
    if (messageId.isEmpty || _chat == null) return;
    final next = _chat!.messages.where((m) => m.id != messageId).toList();
    setState(() {
      _chat = ChatDetail(
        id: _chat!.id,
        messages: next,
        otherUser: _chat!.otherUser,
        participants: _chat!.participants,
      );
    });
  }

  void _mergeOrInsertMessage(
    ChatMessage incoming, {
    bool shouldScroll = true,
  }) {
    final current = _chat;
    if (current == null) {
      setState(() {
        _chat = ChatDetail(
          id: _chatId ?? '',
          messages: [incoming],
          otherUser: ChatListItemUser(
            id: widget.otherUserId,
            fullName: widget.otherName,
            photo: widget.otherPhotoUrl,
          ),
          participants: null,
        );
      });
      _touchCursor(incoming.createdAt);
      if (shouldScroll) _scrollToBottom(animated: true);
      return;
    }

    final messages = List<ChatMessage>.from(current.messages);
    var replaced = false;
    for (var i = 0; i < messages.length; i++) {
      if (messages[i].id == incoming.id && incoming.id.isNotEmpty) {
        messages[i] = incoming;
        replaced = true;
        break;
      }
    }
    if (!replaced &&
        incoming.clientMessageId != null &&
        incoming.clientMessageId!.isNotEmpty) {
      for (var i = 0; i < messages.length; i++) {
        if (messages[i].clientMessageId == incoming.clientMessageId) {
          messages[i] = incoming;
          replaced = true;
          break;
        }
      }
    }
    if (!replaced) {
      messages.add(incoming);
    }

    setState(() {
      _chat = ChatDetail(
        id: current.id,
        messages: messages,
        otherUser: current.otherUser,
        participants: current.participants,
      );
    });
    _touchCursor(incoming.createdAt);
    if (shouldScroll) _scrollToBottom(animated: true);
  }

  void _emitTypingStopIfNeeded() {
    final cid = _chatId;
    if (!_typingStartSent || cid == null || cid.isEmpty) return;
    _typingStartSent = false;
    _realtime.sendTypingStop(chatId: cid);
  }

  void _onMessageTextChanged(String raw) {
    final cid = _chatId;
    if (cid == null || cid.isEmpty) return;

    final hasText = raw.trim().isNotEmpty;
    if (!hasText) {
      _typingStartDebounce?.cancel();
      _typingStopDebounce?.cancel();
      _emitTypingStopIfNeeded();
      return;
    }

    if (!_typingStartSent) {
      _typingStartDebounce?.cancel();
      _typingStartDebounce = Timer(const Duration(milliseconds: 250), () {
        if (!mounted) return;
        if (_messageController.text.trim().isEmpty) return;
        _typingStartSent = true;
        _realtime.sendTypingStart(chatId: cid);
      });
    }

    _typingStopDebounce?.cancel();
    _typingStopDebounce = Timer(const Duration(milliseconds: 1400), () {
      _emitTypingStopIfNeeded();
    });
  }

  Future<void> _loadChat() async {
    final cid = _chatId;
    if (cid == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await _repo.getChat(cid, markRead: true);
      if (!mounted) return;
      setState(() {
        _chat = detail;
        _loading = false;
      });
      _refreshCursorFromMessages(detail.messages);
      unawaited(_connectRealtimeIfPossible());
      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ getChat error: $e');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Pagination: load older messages when user scrolls to top using before_id.
  Future<void> _loadMoreMessages() async {
    final cid = _chatId;
    if (cid == null ||
        _loadingMore ||
        _chat == null ||
        _hasReachedEndOfMessages) {
      return;
    }
    final messages = _chat!.messages;
    if (messages.isEmpty) {
      _hasReachedEndOfMessages = true;
      return;
    }
    final ordered = List<ChatMessage>.from(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final oldestId = ordered.first.id;

    setState(() => _loadingMore = true);
    try {
      final detail = await _repo.getChat(
        cid,
        markRead: false,
        beforeId: oldestId,
        take: 30,
      );
      if (!mounted) return;
      final existingIds = messages.map((m) => m.id).toSet();
      final older = detail.messages
          .where((m) => !existingIds.contains(m.id))
          .toList();
      if (older.isEmpty) {
        if (mounted) {
          setState(() {
            _hasReachedEndOfMessages = true;
            _loadingMore = false;
          });
        }
        return;
      }
      final merged = [...older, ..._chat!.messages];
      if (mounted) {
        setState(() {
          _chat = ChatDetail(
            id: _chat!.id,
            messages: merged,
            otherUser: _chat!.otherUser,
            participants: _chat!.participants,
          );
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _sending) return;
    final cid = _normalizeChatId(_chatId);
    if (cid == null) {
      await showPremiumErrorDialog(
        context,
        message:
            'Bu sohbet henuz aktif degil. Mesaj gonderebilmek icin eslesmeden gelen sohbete girin.',
      );
      return;
    }
    if (widget.otherUserId.trim().isEmpty) {
      await showPremiumErrorDialog(
        context,
        message: 'Kullanıcı bilgisi eksik, mesaj gönderilemez.',
      );
      return;
    }

    setState(() => _sending = true);
    _messageController.clear();
    _emitTypingStopIfNeeded();
    String? optimisticTempId;

    try {
      final clientMessageId = _nextClientMessageId();
      optimisticTempId = 'temp-$clientMessageId';
      final optimistic = ChatMessage(
        id: optimisticTempId,
        messageType: 'text',
        text: text,
        imageUrl: null,
        createdAt: DateTime.now(),
        senderId: _currentUserId,
        isMe: true,
        clientMessageId: clientMessageId,
      );
      _mergeOrInsertMessage(optimistic);

      final sentMessage = await _repo.sendMessage(
        cid,
        messageType: 'text',
        text: text,
        clientMessageId: clientMessageId,
      );
      if (!mounted) return;

      _removeMessageById(optimisticTempId);
      _mergeOrInsertMessage(sentMessage);
      if (mounted) setState(() => _sending = false);
    } catch (e) {
      debugPrint('❌ sendMessage error: $e');
      if (!mounted) return;
      if (optimisticTempId != null) {
        _removeMessageById(optimisticTempId);
      }
      _messageController.text = text;
      setState(() => _sending = false);
      await showPremiumErrorDialog(
        context,
        message:
            'Mesaj gönderilemedi: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
      );
    }
  }

  Future<void> _deleteMessage(ChatMessage message) async {
    final cid = _chatId;
    if (cid == null || _chat == null) return;
    if (_deletingMessageIds.contains(message.id)) return;

    final previous = _chat!;
    final reducedMessages = previous.messages
        .where((m) => m.id != message.id)
        .toList();
    setState(() {
      _deletingMessageIds.add(message.id);
      _chat = ChatDetail(
        id: previous.id,
        messages: reducedMessages,
        otherUser: previous.otherUser,
        participants: previous.participants,
      );
    });

    try {
      await _repo.deleteMessage(cid, message.id);
      if (!mounted) return;
      setState(() {
        _deletingMessageIds.remove(message.id);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _deletingMessageIds.remove(message.id);
        _chat = previous;
      });
      await showPremiumErrorDialog(
        context,
        message:
            'Mesaj silinemedi: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
      );
    }
  }

  Future<bool> _confirmDeleteMessage() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete message'),
          content: const Text('This message will be permanently removed.'),
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

  Future<void> _showMessageActions(ChatMessage message, bool isMe) async {
    final colors = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMe)
                ListTile(
                  leading: Icon(Icons.delete_outline, color: colors.error),
                  title: const Text('Delete'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await _confirmDeleteMessage();
                    if (!confirmed) return;
                    await _deleteMessage(message);
                  },
                ),

              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Edit'),
                onTap: () => Navigator.pop(sheetContext),
              ),
              const SizedBox(height: 6),
            ],
          ),
        );
      },
    );
  }

  Color _avatarColor(String seed) {
    final colors = <Color>[
      AppTheme.brandPrimary,
      const Color(0xFF0EA5E9),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      AppTheme.brandPrimary,
      AppTheme.brandPrimary,
    ];

    final index = seed.hashCode.abs() % colors.length;
    return colors[index];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _chat?.displayOtherUser?.fullName ?? widget.otherName;
    final photoUrl = _chat?.displayOtherUser?.photo ?? widget.otherPhotoUrl;
    final avatarSeed = name.isNotEmpty ? name : widget.otherUserId;
    final avatarColor = _avatarColor(avatarSeed);
    final hasPhoto = photoUrl.isNotEmpty;
    final statusText = _isOtherTyping
        ? 'Typing...'
        : _isSocketReconnecting
        ? 'Reconnecting...'
        : (_isSocketConnected
              ? (_isOtherOnline ? 'Online' : 'Offline')
              : 'Connecting...');
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0.5,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: colors.onSurface, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: avatarColor.withValues(alpha: 0.15),
              backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
              child: !hasPhoto
                  ? Text(
                      avatarSeed[0].toUpperCase(),
                      style: TextStyle(
                        color: avatarColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    )
                  : null,
            ),

            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  statusText,
                  style: TextStyle(color: colors.primary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: const [],
      ),
      body: Column(
        children: [
          Expanded(child: _buildMessageList()),
          _buildMessageInput(),
        ],
      ),
    );
  }

  Widget _buildMessageList() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    if (_loading && _chat == null && _chatId != null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _chat == null && _chatId != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Could not load chat',
                style: TextStyle(
                  color: colors.onSurface.withValues(alpha: 0.75),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: _loadChat, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final messages = _chat?.messages ?? [];
    if (_chatId == null && messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Start the conversation.',
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.onSurface.withValues(alpha: 0.7)),
          ),
        ),
      );
    }
    final ordered = List<ChatMessage>.from(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: ordered.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (_loadingMore && index == 0) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final msgIndex = _loadingMore ? index - 1 : index;
        final msg = ordered[msgIndex];
        final isMe = msg.isSentByMe(_currentUserId);
        final time = _formatTime(msg.createdAt);
        final isSeenByOther =
            isMe &&
            _otherUserReadAt != null &&
            !msg.createdAt.isAfter(_otherUserReadAt!);
        final content = msg.messageType == 'image' && msg.imageUrl != null
            ? msg.imageUrl!
            : (msg.text ?? '');
        if (msg.messageType == 'image' && msg.imageUrl != null) {
          return GestureDetector(
            onLongPress: () => _showMessageActions(msg, isMe),
            child: _buildImageBubble(msg.imageUrl!, isMe, time, isSeenByOther),
          );
        }
        return GestureDetector(
          onLongPress: () => _showMessageActions(msg, isMe),
          child: _buildMessageBubble(
            message: content,
            isMe: isMe,
            time: time,
            isSeenByOther: isSeenByOther,
          ),
        );
      },
    );
  }

  Widget _buildMessageBubble({
    required String message,
    required bool isMe,
    required String time,
    required bool isSeenByOther,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomingBubble = theme.brightness == Brightness.dark
        ? colors.surface
        : const Color(0xFFF8FBFD);

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe ? colors.secondary : incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isMe ? 16 : 0),
            bottomRight: Radius.circular(isMe ? 0 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message,
              style: TextStyle(
                color: isMe ? colors.onSecondary : colors.onSurface,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSeenByOther ? 'Seen • $time' : time,
              style: TextStyle(
                color: isMe
                    ? colors.onSecondary.withValues(alpha: 0.75)
                    : colors.onSurface.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageBubble(
    String imageUrl,
    bool isMe,
    String time,
    bool isSeenByOther,
  ) {
    final colors = Theme.of(context).colorScheme;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.broken_image, size: 48),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              isSeenByOther ? 'Seen • $time' : time,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.55),
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final hour = date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: colors.onSurface.withValues(alpha: 0.08),
            spreadRadius: 1,
            blurRadius: 10,
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _messageController,
                onChanged: _onMessageTextChanged,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Say something...',
                  hintStyle: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.6),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.brightness == Brightness.dark
                      ? colors.surface.withValues(alpha: 0.75)
                      : colors.surface.withValues(alpha: 0.95),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            CircleAvatar(
              backgroundColor: colors.secondary,
              child: IconButton(
                icon: _sending
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.send, color: Colors.white, size: 20),
                onPressed: _sending ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
