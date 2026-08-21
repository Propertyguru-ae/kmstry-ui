import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';

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
  bool _loadingMore = false;
  bool _hasReachedEndOfMessages = false;
  final Set<String> _deletingMessageIds = <String>{};
  StreamSubscription<ChatRealtimeEnvelope>? _realtimeEventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _realtimeStateSub;
  Timer? _typingStartDebounce;
  Timer? _typingStopDebounce;
  Timer? _remoteTypingTimeout;
  Timer? _readReceiptDebounce;
  Timer? _activeChatRefreshTimer;
  Timer? _floatingDateHideTimer;
  DateTime? _lastCursor;
  bool _typingStartSent = false;
  bool _isOtherTyping = false;
  bool _isOtherOnline = false;
  bool _isSocketConnected = false;
  bool _isSocketReconnecting = false;
  int _localMessageCounter = 0;
  static const Duration _messageEditWindow = Duration(minutes: 15);
  static const String _recentReactionEmojisKey = 'recent_reaction_emojis';

  // Mesaj balonlarının ekrandaki gerçek pozisyonunu yakalamak için
  // (uzun basma overlay'inde "aynı yerde" vurgulama yapabilmek amacıyla).
  final Map<String, GlobalKey> _bubbleKeys = {};
  GlobalKey _keyFor(String id) =>
      _bubbleKeys.putIfAbsent(id, () => GlobalKey());
  final Map<String, GlobalKey> _messageItemKeys = {};
  GlobalKey _itemKeyFor(String id) =>
      _messageItemKeys.putIfAbsent(id, () => GlobalKey());
  String? _floatingDateText;
  bool _showFloatingDate = false;

  // Client-side "quote" reply: gerçek reply_to_id backend'de yok, gönderirken
  // metnin başına referans satırı eklenir (basit ama işlevsel WhatsApp benzeri UX).
  ChatMessage? _replyingTo;
  bool _forwardSelectionMode = false;
  final Set<String> _forwardSelectedMessageIds = <String>{};

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
      unawaited(_connectRealtimeIfPossible());
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
      PushManager.instance.markChatHidden(cid);
      debugPrint('💬 [Detail] chat.leave => $cid');
      _realtime.leaveChat(cid);
    }
    _typingStartDebounce?.cancel();
    _typingStopDebounce?.cancel();
    _remoteTypingTimeout?.cancel();
    _readReceiptDebounce?.cancel();
    _activeChatRefreshTimer?.cancel();
    _floatingDateHideTimer?.cancel();
    _realtimeEventsSub?.cancel();
    _realtimeStateSub?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cid = _chatId;
    if (state == AppLifecycleState.resumed) {
      if (cid != null && cid.isNotEmpty) {
        PushManager.instance.markChatVisible(cid);
      }
      unawaited(_connectRealtimeIfPossible());
      unawaited(_catchUpMessages());
      return;
    }
    final shouldClearActiveChat =
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden;
    if (shouldClearActiveChat && cid != null && cid.isNotEmpty) {
      PushManager.instance.markChatHidden(cid);
      _realtime.leaveChat(cid);
      _activeChatRefreshTimer?.cancel();
      _activeChatRefreshTimer = null;
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    _scrollToBottom(animated: true);
  }

  /// widget.otherUserId bildirimden boş gelirse yüklenen chat'ten kullan.
  /// Başlıktaki isme/avatara dokununca karşı kullanıcının profilini açar.
  Future<void> _openOtherProfile() async {
    final userId = _effectiveOtherUserId;
    if (userId.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfilePreviewPage(
          userId: userId,
          userName: widget.otherName,
          userPhoto: widget.otherPhotoUrl.isNotEmpty
              ? widget.otherPhotoUrl
              : null,
          chatIdHint: _chatId,
          isMatchedHint: true,
          hideVenueInfo: true,
        ),
      ),
    );
    // Profilde block/unblock yapılmış olabilir — dönünce sohbet durumunu
    // (canSendMessages / isBlocked) tazele ki input doğru kilitlensin.
    if (mounted) unawaited(_loadChat());
  }

  String get _effectiveOtherUserId => widget.otherUserId.isNotEmpty
      ? widget.otherUserId
      : (_chat?.displayOtherUser?.id ?? '');

  void _bindRealtimeStreams() {
    _realtimeEventsSub = _realtime.events.listen(_handleRealtimeEvent);
    _realtimeStateSub = _realtime.connectionState.listen((state) {
      if (!mounted) return;
      setState(() {
        _isSocketConnected = state == ChatRealtimeConnectionState.connected;
        _isSocketReconnecting =
            state == ChatRealtimeConnectionState.reconnecting;
      });
    });
  }

  void _onScroll() {
    _updateFloatingDateForScroll();
    if (_loadingMore || _loading || _chat == null || _hasReachedEndOfMessages) {
      return;
    }
    if (_scrollController.offset <= 100 && _scrollController.hasClients) {
      _loadMoreMessages();
    }
  }

  void _updateFloatingDateForScroll() {
    if (!_scrollController.hasClients || _chat == null) return;
    final messages = List<ChatMessage>.from(_chat!.messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (messages.isEmpty) return;

    final threshold = MediaQuery.of(context).padding.top + kToolbarHeight + 28;
    ChatMessage? visibleMessage;
    for (final message in messages) {
      final itemContext = _messageItemKeys[message.id]?.currentContext;
      if (itemContext == null) continue;
      final box = itemContext.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final position = box.localToGlobal(Offset.zero);
      if (position.dy + box.size.height >= threshold) {
        visibleMessage = message;
        break;
      }
    }
    visibleMessage ??= messages.last;

    final nextText = _formatDateSeparator(visibleMessage.createdAt);
    if (_floatingDateText != nextText || !_showFloatingDate) {
      setState(() {
        _floatingDateText = nextText;
        _showFloatingDate = true;
      });
    }

    _floatingDateHideTimer?.cancel();
    _floatingDateHideTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      if (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        return;
      }
      setState(() => _showFloatingDate = false);
    });
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

  // Composer (input/banner) Column'da liste ile KARDEŞ; listeyi örtmüyor.
  // Bu yüzden listeye composer yüksekliği kadar alt boşluk EKLENMEZ — aksi
  // halde klavye açıkken son mesaj ile klavye arasında büyük boşluk oluşur.
  // Klavye zaten resizeToAvoidBottomInset ile ele alınıyor; sadece küçük bir
  // nefes payı yeterli.
  double _messageListBottomPadding() => 12;

  Future<void> _loadCurrentUser() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _currentUserId = me['id'] as String?;
      });
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
    PushManager.instance.markChatVisible(cid);
    _realtime.joinChat(cid);
    _startActiveChatRefresh(cid);
    try {
      await _repo.markChatRead(cid);
    } catch (_) {}
  }

  void _startActiveChatRefresh(String cid) {
    _activeChatRefreshTimer?.cancel();
    _activeChatRefreshTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      PushManager.instance.markChatVisible(cid);
      _realtime.joinChat(cid);
    });
  }

  Future<void> _catchUpMessages() async {
    final cid = _chatId;
    if (cid == null || cid.isEmpty) return;

    try {
      // Kaydırmadan önce kullanıcı en altta (son mesajları okurken) mıydı?
      // Öyleyse resume'da yeni mesajları görünür kılmak için alta kaydırırız;
      // yukarıda geçmişi okuyorsa görünümü zıplatmayız (WhatsApp davranışı).
      final wasAtBottom = _isNearBottom();
      var insertedAny = false;

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
          final before = _chat?.messages.length ?? 0;
          _mergeOrInsertMessage(message, shouldScroll: false);
          if ((_chat?.messages.length ?? 0) > before) insertedAny = true;
        }
        if (page.nextCursor == null || page.nextCursor!.isEmpty) break;
        cursor = page.nextCursor;
        _touchCursor(_parseIsoDateTime(page.nextCursor));
      }

      // Yeni mesaj geldiyse ve kullanıcı zaten en alttaysa → alta kaydır ki
      // resume sonrası yeni mesajlar ekranda görünsün.
      if (insertedAny && wasAtBottom && mounted) {
        _scrollToBottom(animated: true);
      }
    } catch (_) {}
  }

  /// Liste en alta yakın mı (son mesajlar görünüyor mu)?
  bool _isNearBottom() {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return (pos.maxScrollExtent - pos.pixels) < 200;
  }

  void _handleRealtimeEvent(ChatRealtimeEnvelope envelope) {
    if (!mounted) return;
    final payload = envelope.payload;
    final eventChatId = _readStringField(payload, const ['chatId', 'chat_id']);
    final activeChatId = _chatId;
    final isChatEvent =
        envelope.event.startsWith('message.') ||
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
      _parseIsoDateTime(
        payload['serverTimestamp'] ?? payload['server_timestamp'],
      ),
    );

    switch (envelope.event) {
      case 'socket.reconnected':
        unawaited(_catchUpMessages());
        return;
      case 'message.created':
        final rawMessage = payload['message'];
        if (rawMessage is! Map) return;
        final message = ChatMessage.fromJson(
          Map<String, dynamic>.from(rawMessage),
        );
        _mergeOrInsertMessage(message);
        if (!message.isSentByMe(_currentUserId)) {
          _scheduleReadReceipt();
        }
        return;
      case 'message.updated':
        final rawUpdated = payload['message'];
        if (rawUpdated is! Map) return;
        // Sunucu edit eventinde kısmi alan gönderir (id/text/edited_at) —
        // mevcut mesajın üzerine merge et, komple değiştirme.
        final updatedMap = Map<String, dynamic>.from(rawUpdated);
        final updatedId = (updatedMap['id'] ?? '').toString();
        if (updatedId.isEmpty || _chat == null) return;
        final nextMessages = _chat!.messages.map((m) {
          if (m.id != updatedId) return m;
          return m.copyWith(
            text: updatedMap['text'] as String? ?? m.text,
            imageUrl: updatedMap['image_url'] as String? ?? m.imageUrl,
            editedAt: _parseIsoDateTime(updatedMap['edited_at']) ?? m.editedAt,
          );
        }).toList();
        setState(() => _chat = _chat!.copyWith(messages: nextMessages));
        return;
      case 'message.reaction':
        final messageId = _readStringField(payload, const [
          'messageId',
          'message_id',
        ]);
        final rawReactions = payload['reactions'];
        if (messageId == null || rawReactions is! List) return;
        _applyReactions(
          messageId,
          rawReactions
              .whereType<Map>()
              .map(
                (e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((r) => r.emoji.isNotEmpty)
              .toList(),
        );
        return;
      case 'message.deleted':
        final messageId = _readStringField(payload, const [
          'messageId',
          'message_id',
        ]);
        if (messageId == null || messageId.isEmpty) return;
        _removeMessageById(messageId);
        return;
      case 'chat.updated':
        _touchCursor(
          _parseIsoDateTime(
            payload['lastMessageAt'] ?? payload['last_message_at'],
          ),
        );
        return;
      case 'chat.read':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != _effectiveOtherUserId) return;
        final readAt = _parseIsoDateTime(
          payload['readAt'] ?? payload['read_at'],
        );
        if (readAt == null) return;
        final idsRaw = payload['messageIds'] ?? payload['message_ids'];
        final readIds = idsRaw is List
            ? idsRaw.map((e) => e.toString()).toSet()
            : <String>{};
        if (readIds.isEmpty) return;
        _markMessagesRead(readIds, readAt);
        return;
      case 'presence.online':
      case 'presence.offline':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != _effectiveOtherUserId) return;
        if (!mounted) return;
        setState(() {
          _isOtherOnline = envelope.event == 'presence.online';
        });
        return;
      case 'typing.start':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != _effectiveOtherUserId) return;
        _remoteTypingTimeout?.cancel();
        setState(() => _isOtherTyping = true);
        _remoteTypingTimeout = Timer(const Duration(seconds: 4), () {
          if (!mounted) return;
          setState(() => _isOtherTyping = false);
        });
        return;
      case 'typing.stop':
        final userId = _readStringField(payload, const ['userId', 'user_id']);
        if (userId == null || userId != _effectiveOtherUserId) return;
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
      _chat = _chat!.copyWith(messages: next);
    });
  }

  /// Stamp the given messages as read (per-message "Seen"), keeping the earliest
  /// read time already present. Called on a realtime chat.read event.
  void _markMessagesRead(Set<String> ids, DateTime readAt) {
    if (_chat == null || ids.isEmpty || !mounted) return;
    var changed = false;
    final next = _chat!.messages.map((m) {
      if (ids.contains(m.id) && m.readAt == null) {
        changed = true;
        return m.copyWith(readAt: readAt);
      }
      return m;
    }).toList();
    if (!changed) return;
    setState(() {
      _chat = _chat!.copyWith(messages: next);
    });
  }

  /// Mesajın reaction listesini yenile (realtime event ya da toggle sonucu).
  void _applyReactions(String messageId, List<MessageReaction> reactions) {
    if (_chat == null || messageId.isEmpty || !mounted) return;
    final next = _chat!.messages.map((m) {
      if (m.id != messageId) return m;
      return m.copyWith(reactions: reactions);
    }).toList();
    setState(() => _chat = _chat!.copyWith(messages: next));
  }

  void _mergeOrInsertMessage(ChatMessage incoming, {bool shouldScroll = true}) {
    final current = _chat;
    if (current == null) {
      setState(() {
        _chat = ChatDetail(
          id: _chatId ?? '',
          messages: [incoming],
          otherUser: ChatListItemUser(
            id: _effectiveOtherUserId,
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
      _chat = current.copyWith(messages: messages);
    });
    _touchCursor(incoming.createdAt);
    if (shouldScroll) _scrollToBottom(animated: true);
  }

  /// Okundu bilgisini socket ile işaretle (kısa debounce ile ardışık mesajları
  /// birleştirir). Ekran mounted → kullanıcı mesajı görüyor demektir → anlık seen.
  void _scheduleReadReceipt() {
    final cid = _chatId;
    if (cid == null || cid.isEmpty) return;
    _readReceiptDebounce?.cancel();
    _readReceiptDebounce = Timer(const Duration(milliseconds: 250), () {
      if (!mounted) return;
      final id = _chatId;
      if (id == null || id.isEmpty) return;
      _realtime.sendChatRead(chatId: id);
    });
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
        // Per-message read_at is carried on each message, so "Seen" persists
        // across reopens with no extra hydration.
        _chat = detail;
        _loading = false;
        // Sunucudan gelen gerçek presence — sayfa yeni açıldığında henüz bir
        // realtime presence eventi gelmemiş olabilir, varsayılan "true" yanlış
        // gösterirdi.
        _isOtherOnline = detail.otherUser?.isOnline ?? false;
      });
      _refreshCursorFromMessages(detail.messages);
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
          _chat = _chat!.copyWith(messages: merged);
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  /// Instant send: the optimistic bubble is placed and the input is cleared
  /// synchronously, then the network round-trip runs in the background. The
  /// send button is never gated on the request — chat must feel immediate.
  void _sendMessage() {
    if (_chat?.canSendMessages == false) return;
    final rawText = _messageController.text.trim();
    if (rawText.isEmpty) return;
    final cid = _normalizeChatId(_chatId);
    if (cid == null) {
      unawaited(
        showPremiumErrorDialog(
          context,
          message:
              'This chat is not ready yet. Open the active conversation to send a message.',
        ),
      );
      return;
    }

    final replyTarget = _replyingTo;
    final text = replyTarget == null
        ? rawText
        : '${_replyQuoteLine(replyTarget)}\n$rawText';

    _messageController.clear();
    if (replyTarget != null) setState(() => _replyingTo = null);
    _emitTypingStopIfNeeded();

    final clientMessageId = _nextClientMessageId();
    final optimisticTempId = 'temp-$clientMessageId';
    _mergeOrInsertMessage(
      ChatMessage(
        id: optimisticTempId,
        messageType: 'text',
        text: text,
        imageUrl: null,
        createdAt: DateTime.now(),
        senderId: _currentUserId,
        isMe: true,
        clientMessageId: clientMessageId,
      ),
    );

    unawaited(_deliverMessage(cid, text, clientMessageId, optimisticTempId));
  }

  Future<void> _deliverMessage(
    String cid,
    String text,
    String clientMessageId,
    String optimisticTempId,
  ) async {
    try {
      final sentMessage = await _repo.sendMessage(
        cid,
        messageType: 'text',
        text: text,
        clientMessageId: clientMessageId,
      );
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      _mergeOrInsertMessage(sentMessage);
    } catch (e) {
      debugPrint('❌ sendMessage error: $e');
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      _messageController.text = text;
      // Karşı taraf bloklandıysa / sohbet artık aktif değilse: sohbeti tazele
      // (input kilitlensin) ve generic hata yerine anlaşılır mesaj göster.
      if (_isBlockedOrInactiveError(e)) {
        unawaited(_loadChat());
        await showPremiumErrorDialog(
          context,
          title: 'Messaging paused',
          message:
              'You can\'t message this user right now. This happens when one of you has blocked the other.',
        );
        return;
      }
      if (_isTooManyRequestsError(e)) {
        return;
      }
      await showPremiumErrorDialog(
        context,
        message:
            'Message could not be sent: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    }
  }

  /// Backend, block/inaktif sohbette 403 "cannot send messages while blocked"
  /// veya "Chat is not active" döndürür — bunları generic hatadan ayırır.
  bool _isBlockedOrInactiveError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('block') ||
        s.contains('not active') ||
        s.contains('403') ||
        s.contains('forbidden');
  }

  bool _isTooManyRequestsError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('too many requests') ||
        s.contains('throttlerexception') ||
        s.contains('429');
  }

  void _setReplyTarget(ChatMessage message) {
    if (!mounted) return;
    setState(() => _replyingTo = message);
  }

  void _cancelReply() {
    if (!mounted) return;
    setState(() => _replyingTo = null);
  }

  /// Basit client-side quote satırı (gerçek reply_to_id yok — backend'e
  /// düz metin olarak gider, karşı tarafta da normal metin gibi görünür).
  String _replyQuoteLine(ChatMessage target) {
    final senderLabel = target.isSentByMe(_currentUserId)
        ? 'You'
        : widget.otherName.split(' ').first;
    final snippet = target.messageType == 'image'
        ? '[Photo]'
        : target.messageType == 'file'
        ? '[Document]'
        : (target.text ?? '').trim();
    final compact = snippet.replaceAll(RegExp(r'\s+'), ' ');
    final trimmed = compact.length > 80
        ? '${compact.substring(0, 80)}...'
        : compact;
    return '↩️ $senderLabel: $trimmed';
  }

  /// WhatsApp tarzı mesaj seçme moduna gir: kullanıcı isterse ek mesajları da
  /// seçip alttaki forward barından hedef sohbetleri seçer.
  Future<void> _forwardMessage(ChatMessage message) {
    _enterForwardSelection(message);
    return Future.value();
  }

  void _enterForwardSelection(ChatMessage message) {
    HapticFeedback.selectionClick();
    setState(() {
      _forwardSelectionMode = true;
      _forwardSelectedMessageIds
        ..clear()
        ..add(message.id);
    });
  }

  void _exitForwardSelection() {
    setState(() {
      _forwardSelectionMode = false;
      _forwardSelectedMessageIds.clear();
    });
  }

  void _toggleForwardSelection(ChatMessage message) {
    setState(() {
      if (!_forwardSelectedMessageIds.add(message.id)) {
        _forwardSelectedMessageIds.remove(message.id);
      }
      if (_forwardSelectedMessageIds.isEmpty) {
        _forwardSelectionMode = false;
      }
    });
  }

  List<ChatMessage> _selectedForwardMessages() {
    final messages = _chat?.messages ?? const <ChatMessage>[];
    final selected =
        messages
            .where((m) => _forwardSelectedMessageIds.contains(m.id))
            .toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return selected;
  }

  Future<void> _forwardSelectedMessages() async {
    final messages = _selectedForwardMessages();
    if (messages.isEmpty) return;
    final forwardedTarget = await _openForwardRecipientSheet(messages);
    if (!mounted) return;
    _exitForwardSelection();
    if (forwardedTarget != null) {
      _openForwardedChat(forwardedTarget);
    }
  }

  /// Başka sohbete ilet: hedef sohbetleri seçtirir, aynı içerikleri gönderir.
  Future<ChatListItem?> _openForwardRecipientSheet(
    List<ChatMessage> messages,
  ) async {
    // Sheet'i beklemeden hemen aç, sohbet listesi arka planda gelsin — önceden
    // burada `await`, ağ isteği bitene kadar sheet'in hiç açılmamasına (yani
    // "yavaş" hissine) yol açıyordu.
    final chatsFuture = _repo.getChats();

    final noteController = TextEditingController();
    final searchController = TextEditingController();
    final selectedIds = <String>{};
    var query = '';

    final targets = await showModalBottomSheet<List<ChatListItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _composerBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return FutureBuilder<List<ChatListItem>>(
          future: chatsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return SizedBox(
                height: 260,
                child: Center(
                  child: CircularProgressIndicator(
                    color: AppTheme.brandPrimary,
                  ),
                ),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'Could not load chats.',
                    style: TextStyle(color: _mutedTextColor),
                  ),
                ),
              );
            }
            final chats = (snapshot.data ?? const <ChatListItem>[])
                .where((c) => c.id != _chatId)
                .toList();
            if (chats.isEmpty) {
              return SizedBox(
                height: 200,
                child: Center(
                  child: Text(
                    'No other chats to forward to.',
                    style: TextStyle(color: _mutedTextColor),
                  ),
                ),
              );
            }
            return StatefulBuilder(
              builder: (context, setSheetState) {
                final filteredChats = chats.where((chat) {
                  final name = _forwardChatName(chat).toLowerCase();
                  final preview = (chat.lastMessagePreview ?? '').toLowerCase();
                  final q = query.trim().toLowerCase();
                  return q.isEmpty || name.contains(q) || preview.contains(q);
                }).toList();
                final selectedChats = chats
                    .where((chat) => selectedIds.contains(chat.id))
                    .toList();

                void toggle(ChatListItem chat) {
                  setSheetState(() {
                    if (!selectedIds.add(chat.id)) {
                      selectedIds.remove(chat.id);
                    }
                  });
                }

                return FractionallySizedBox(
                  heightFactor: 0.94,
                  child: SafeArea(
                    child: Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 10),
                          child: Row(
                            children: [
                              _buildForwardCircleButton(
                                icon: Icons.close_rounded,
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                              const Spacer(),
                              Text(
                                'Send to',
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const Spacer(),
                              Opacity(
                                opacity: 0.38,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: _isDarkMode
                                          ? Colors.white.withValues(alpha: 0.08)
                                          : const Color(0xFFF0F4F8),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(color: _dividerColor),
                                    ),
                                    child: Text(
                                      'New group',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                          child: TextField(
                            controller: searchController,
                            onChanged: (value) =>
                                setSheetState(() => query = value),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 16,
                            ),
                            decoration: InputDecoration(
                              hintText: 'Search',
                              hintStyle: TextStyle(color: _mutedTextColor),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: _mutedTextColor,
                              ),
                              filled: true,
                              fillColor: _isDarkMode
                                  ? Colors.white.withValues(alpha: 0.1)
                                  : const Color(0xFFF0F4F8),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: BorderSide(color: _dividerColor),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: BorderSide(color: _dividerColor),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: BorderSide(
                                  color: AppTheme.brandPrimary.withValues(
                                    alpha: 0.75,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                            children: [
                              _buildForwardSectionTitle('Recent chats'),
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _isDarkMode
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: _dividerColor),
                                ),
                                child: Column(
                                  children: [
                                    for (
                                      var i = 0;
                                      i < filteredChats.length;
                                      i++
                                    )
                                      _buildForwardChatTile(
                                        filteredChats[i],
                                        selected: selectedIds.contains(
                                          filteredChats[i].id,
                                        ),
                                        showDivider:
                                            i != filteredChats.length - 1,
                                        onTap: () => toggle(filteredChats[i]),
                                      ),
                                    if (filteredChats.isEmpty)
                                      Padding(
                                        padding: const EdgeInsets.all(22),
                                        child: Text(
                                          'Sohbet bulunamadi.',
                                          style: TextStyle(
                                            color: _mutedTextColor,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: EdgeInsets.fromLTRB(
                            18,
                            selectedChats.isEmpty ? 0 : 12,
                            18,
                            selectedChats.isEmpty ? 0 : 14,
                          ),
                          decoration: BoxDecoration(
                            color: _composerBackground,
                            border: selectedChats.isEmpty
                                ? null
                                : Border(top: BorderSide(color: _dividerColor)),
                          ),
                          child: selectedChats.isEmpty
                              ? const SizedBox.shrink()
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextField(
                                      controller: noteController,
                                      minLines: 1,
                                      maxLines: 3,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                                        fontSize: 15.5,
                                      ),
                                      decoration: InputDecoration(
                                        hintText: 'Add a message...',
                                        hintStyle: TextStyle(
                                          color: _mutedTextColor,
                                        ),
                                        filled: true,
                                        fillColor: _isDarkMode
                                            ? Colors.white.withValues(
                                                alpha: 0.08,
                                              )
                                            : const Color(0xFFF0F4F8),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            22,
                                          ),
                                          borderSide: BorderSide.none,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12,
                                            ),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _forwardSelectionLabel(
                                              selectedChats,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurface,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () => Navigator.pop(
                                            sheetContext,
                                            selectedChats,
                                          ),
                                          child: const Text(
                                            'Forward',
                                            style: TextStyle(
                                              color: Color(0xFF22C55E),
                                              fontSize: 17,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
    searchController.dispose();
    final note = noteController.text.trim();
    noteController.dispose();
    if (targets == null || targets.isEmpty || !mounted) return null;

    // Sheet kapanır kapanmaz görünür geri bildirim: kullanıcı gönderim
    // tamamlanana kadar donmuş hissetmemeli (asıl "yavaş" algısının kaynağı
    // buradaki sessiz bekleyişti).
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 20),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _isDarkMode ? const Color(0xFF111827) : Colors.black,
        content: const Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
            SizedBox(width: 12),
            Text('Sending...'),
          ],
        ),
      ),
    );

    try {
      // Hem hedef sohbetler ARASINDA hem de aynı hedefteki mesajlar ARASINDA
      // paralel gönderim: N sohbet × M mesaj artık N*M ardışık round-trip
      // yerine tek bir round-trip süresi kadar sürüyor.
      await Future.wait(
        targets.map((target) async {
          await Future.wait(
            messages.map(
              (message) => _sendForwardedMessage(target.id, message),
            ),
          );
          if (note.isNotEmpty) {
            await _repo.sendMessage(target.id, messageType: 'text', text: note);
          }
        }),
      );
      if (!mounted) return null;
      messenger.hideCurrentSnackBar();
      return targets.length == 1 ? targets.first : null;
    } catch (_) {
      if (!mounted) return null;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(const SnackBar(content: Text('İletilemedi.')));
      return null;
    }
  }

  void _openForwardedChat(ChatListItem target) {
    final user = target.getDisplayUser(_currentUserId);
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: target.id,
          otherUserId: user?.id ?? '',
          otherName: _forwardChatName(target),
          otherPhotoUrl: user?.photo ?? '',
        ),
      ),
    );
  }

  Future<void> _sendForwardedMessage(String targetChatId, ChatMessage message) {
    if (message.messageType == 'image' && message.imageUrl != null) {
      return _repo.sendMessage(
        targetChatId,
        messageType: 'image',
        imageUrl: message.imageUrl,
      );
    }
    if (message.messageType == 'file' && message.fileUrl != null) {
      return _repo.sendMessage(
        targetChatId,
        messageType: 'file',
        fileUrl: message.fileUrl,
        fileName: message.fileName,
      );
    }
    return _repo.sendMessage(
      targetChatId,
      messageType: 'text',
      text: message.text ?? '',
    );
  }

  String _forwardChatName(ChatListItem chat) {
    final user = chat.getDisplayUser(_currentUserId);
    final name = user?.fullName?.trim();
    return name != null && name.isNotEmpty ? name : 'Unknown';
  }

  String _forwardSelectionLabel(List<ChatListItem> selectedChats) {
    if (selectedChats.isEmpty) return '';
    if (selectedChats.length == 1) return _forwardChatName(selectedChats.first);
    final first = _forwardChatName(selectedChats.first);
    return '$first +${selectedChats.length - 1}';
  }

  Widget _buildForwardSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Text(
        title,
        style: TextStyle(
          color: _mutedTextColor,
          fontSize: 16,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildForwardCircleButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: 48,
      height: 48,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _isDarkMode
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFF0F4F8),
          border: Border.all(color: _dividerColor),
        ),
        child: IconButton(
          icon: Icon(icon, color: Theme.of(context).colorScheme.onSurface),
          onPressed: onPressed,
        ),
      ),
    );
  }

  Widget _buildForwardChatTile(
    ChatListItem chat, {
    required bool selected,
    required bool showDivider,
    required VoidCallback onTap,
  }) {
    final user = chat.getDisplayUser(_currentUserId);
    final name = _forwardChatName(chat);
    final photo = user?.photo ?? '';
    final preview = chat.lastMessagePreview?.trim();
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(
          children: [
            _buildForwardAvatar(name: name, photoUrl: photo),
            const SizedBox(width: 14),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  border: showDivider
                      ? Border(bottom: BorderSide(color: _dividerColor))
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.onSurface,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            preview != null && preview.isNotEmpty
                                ? preview
                                : 'Recent chat',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _mutedTextColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 28,
                      height: 28,
                      margin: const EdgeInsets.only(right: 14),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: selected
                            ? const Color(0xFF22C55E)
                            : Colors.transparent,
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF22C55E)
                              : _mutedTextColor.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: selected
                          ? const Icon(
                              Icons.check_rounded,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForwardAvatar({required String name, required String photoUrl}) {
    final hasPhoto = photoUrl.trim().isNotEmpty;
    final avatarColor = _avatarColor(name);
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    return CircleAvatar(
      radius: 25,
      backgroundColor: avatarColor.withValues(alpha: 0.18),
      backgroundImage: hasPhoto ? NetworkImage(photoUrl) : null,
      child: hasPhoto
          ? null
          : Text(
              initial,
              style: TextStyle(
                color: avatarColor,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
    );
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
      _chat = previous.copyWith(messages: reducedMessages);
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
            'Message could not be deleted: ${e.toString().replaceAll(RegExp(r'^Exception:?\\s*'), '')}',
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

  static const List<String> _reactionEmojis = [
    '👍',
    '❤️',
    '😂',
    '😮',
    '😢',
    '🙏',
  ];

  /// WhatsApp tarzı uzun-basma overlay'i: arka plan blur+karartılır, seçilen
  /// balon kendi ekran konumunda net kalır, üstünde reaction barı, konuma göre
  /// üstte/altta aksiyon menüsü açılır. Geri tuşu/dışına dokunma kapatır.
  Future<void> _openMessageOverlay(ChatMessage message, bool isMe) async {
    final renderObject = _bubbleKeys[message.id]?.currentContext
        ?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final origin = renderObject.localToGlobal(Offset.zero);
    final size = renderObject.size;

    FocusManager.instance.primaryFocus?.unfocus();
    HapticFeedback.mediumImpact();

    final canEdit = _canEditMessage(message, isMe);
    final canCopy =
        message.messageType == 'text' && (message.text?.isNotEmpty ?? false);

    await showGeneralDialog<void>(
      context: context,
      barrierLabel: 'message-actions',
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _MessageActionOverlay(
          animation: animation,
          bubbleOrigin: origin,
          bubbleSize: size,
          isMe: isMe,
          bubbleChild: _buildBubbleClone(message, isMe),
          reactionEmojis: _reactionEmojis,
          myReaction: _myReactionOf(message)?.emoji,
          onReaction: (emoji) {
            Navigator.of(dialogContext).pop();
            unawaited(_toggleReaction(message, emoji));
          },
          onMoreReactions: () {
            Navigator.of(dialogContext).pop();
            unawaited(_showMoreReactionsPicker(message));
          },
          onReply: () {
            Navigator.of(dialogContext).pop();
            _setReplyTarget(message);
          },
          onForward: () {
            Navigator.of(dialogContext).pop();
            unawaited(_forwardMessage(message));
          },
          canCopy: canCopy,
          onCopy: () async {
            Navigator.of(dialogContext).pop();
            await Clipboard.setData(ClipboardData(text: message.text ?? ''));
          },
          canEdit: canEdit,
          onEdit: () {
            Navigator.of(dialogContext).pop();
            unawaited(_startEditMessage(message));
          },
          canDelete: isMe,
          onDelete: () async {
            Navigator.of(dialogContext).pop();
            final confirmed = await _confirmDeleteMessage();
            if (!confirmed) return;
            await _deleteMessage(message);
          },
          canReport: !isMe,
          onReport: () {
            Navigator.of(dialogContext).pop();
            unawaited(_openReportMessageSheet());
          },
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) => child,
    );
  }

  Future<void> _openReportMessageSheet() async {
    final targetUserId = _effectiveOtherUserId;
    if (targetUserId.isEmpty) return;
    await showReportUserSheet(context, targetUserId: targetUserId);
  }

  bool _canEditMessage(ChatMessage message, bool isMe) {
    if (!isMe) return false;
    if (message.messageType != 'text') return false;
    if ((message.text ?? '').trim().isEmpty) return false;
    if (message.id.startsWith('temp-')) return false;
    final sentAt = message.createdAt.toLocal();
    final age = DateTime.now().difference(sentAt);
    return !age.isNegative && age <= _messageEditWindow;
  }

  /// Overlay'de gösterilecek balonun görsel kopyası (aynı builder'lar, key yok
  /// — orijinal balonla GlobalKey çakışmasını önlemek için).
  Widget _buildBubbleClone(ChatMessage message, bool isMe) {
    final time = _formatTime(message.createdAt);
    final isSeenByOther = isMe && message.readAt != null;
    if (message.messageType == 'image' && message.imageUrl != null) {
      return _buildImageBubble(message.imageUrl!, isMe, time, isSeenByOther);
    }
    if (message.messageType == 'file' && message.fileUrl != null) {
      return _buildFileBubble(
        fileUrl: message.fileUrl!,
        fileName: message.fileName ?? 'Document',
        isMe: isMe,
        time: time,
        isSeenByOther: isSeenByOther,
      );
    }
    return _buildMessageBubble(
      message: message.text ?? '',
      isMe: isMe,
      time: time,
      isSeenByOther: isSeenByOther,
      edited: message.editedAt != null,
    );
  }

  Future<List<String>> _loadRecentReactionEmojis() async {
    final raw = await SecureStorage.read(_recentReactionEmojisKey);
    if (raw == null || raw.trim().isEmpty) return const <String>[];
    return raw
        .split(',')
        .map((emoji) => emoji.trim())
        .where((emoji) => emoji.isNotEmpty)
        .toList();
  }

  Future<void> _rememberReactionEmoji(String emoji) async {
    final recent = await _loadRecentReactionEmojis();
    final next = <String>[
      emoji,
      ...recent.where((item) => item != emoji),
    ].take(14).toList();
    await SecureStorage.write(_recentReactionEmojisKey, next.join(','));
  }

  /// Genişletilmiş emoji seçici ("+" reaction butonu).
  Future<void> _showMoreReactionsPicker(ChatMessage message) async {
    final recent = await _loadRecentReactionEmojis();
    const fallbackRecent = ['💜', '😁', '😀', '😂', '😍', '😙', '😣'];
    const smileys = [
      '😀',
      '😃',
      '😁',
      '😄',
      '😆',
      '🥹',
      '😅',
      '😂',
      '🤣',
      '🥲',
      '☺️',
      '😊',
      '🙂',
      '🙃',
      '😉',
      '😌',
      '😍',
      '🥰',
      '😘',
      '😗',
      '😙',
      '😚',
      '😋',
      '😛',
      '😜',
      '🤪',
      '😝',
      '🤗',
      '🤭',
      '🫢',
      '🤫',
      '🤔',
      '🫡',
      '🤐',
      '😐',
      '😑',
      '😶',
      '😏',
      '😒',
      '🙄',
      '😬',
      '😮‍💨',
      '🤥',
      '😌',
      '😔',
      '😪',
      '🤤',
      '😴',
      '😷',
      '🤒',
      '🤕',
      '🤢',
      '🤮',
      '🥵',
      '🥶',
      '🥴',
      '😵',
      '🤯',
      '🥳',
      '😎',
      '🤓',
      '🧐',
      '😕',
      '🫤',
      '😟',
      '🙁',
      '☹️',
      '😮',
      '😯',
      '😲',
      '😳',
      '🥺',
      '😦',
      '😧',
      '😨',
      '😰',
      '😥',
      '😢',
      '😭',
      '😱',
      '😖',
      '😣',
      '😞',
      '😓',
      '😩',
      '😫',
      '😤',
      '😡',
      '😠',
      '🤬',
      '👍',
      '👎',
      '👏',
      '🙌',
      '🙏',
      '👌',
      '💯',
      '🎉',
      '✨',
    ];
    const animals = [
      '🐶',
      '🐱',
      '🐭',
      '🐹',
      '🐰',
      '🦊',
      '🐻',
      '🐼',
      '🐨',
      '🐯',
      '🦁',
      '🐮',
      '🐷',
      '🐸',
      '🐵',
      '🐔',
      '🐧',
      '🐦',
      '🐤',
      '🦆',
      '🦅',
      '🦉',
      '🦋',
      '🐌',
      '🐞',
      '🐢',
      '🐍',
      '🐙',
      '🐠',
      '🐳',
      '🦕',
    ];
    const food = [
      '🍏',
      '🍎',
      '🍐',
      '🍊',
      '🍋',
      '🍌',
      '🍉',
      '🍇',
      '🍓',
      '🫐',
      '🍒',
      '🍑',
      '🥝',
      '🍅',
      '🥑',
      '🍕',
      '🍔',
      '🍟',
      '🌮',
      '🍣',
      '🍰',
      '🍫',
      '☕',
      '🍻',
    ];
    const activities = [
      '⚽',
      '🏀',
      '🏈',
      '⚾',
      '🎾',
      '🏐',
      '🎱',
      '🏓',
      '🏆',
      '🎮',
      '🎲',
      '🎯',
      '🎤',
      '🎧',
      '🎬',
      '🎨',
      '🎭',
      '🎪',
      '🎉',
      '🎁',
    ];
    const travel = [
      '🚗',
      '🚕',
      '🚌',
      '🏎️',
      '🚓',
      '🚑',
      '🚒',
      '🚲',
      '✈️',
      '🚀',
      '⛵',
      '🚢',
      '🏝️',
      '🏔️',
      '🌆',
      '🌃',
      '🗺️',
      '🧳',
    ];
    const objects = [
      '💡',
      '📱',
      '💻',
      '⌚',
      '📷',
      '🎥',
      '🔋',
      '🔌',
      '💎',
      '🔑',
      '🎈',
      '🧸',
      '🛍️',
      '📌',
      '📎',
      '✏️',
      '📚',
      '💰',
    ];
    const symbols = [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🖤',
      '🤍',
      '💔',
      '❣️',
      '💕',
      '💞',
      '✨',
      '🔥',
      '💯',
      '✅',
      '❌',
      '⭐',
      '⚡',
      '☀️',
    ];
    final categories = <_EmojiCategory>[
      _EmojiCategory(
        title: 'Recently used',
        icon: Icons.access_time_rounded,
        emojis: recent.isEmpty ? fallbackRecent : recent,
      ),
      const _EmojiCategory(
        title: 'Smileys & people',
        icon: Icons.sentiment_satisfied_alt_rounded,
        emojis: smileys,
      ),
      const _EmojiCategory(
        title: 'Animals & nature',
        icon: Icons.pets_rounded,
        emojis: animals,
      ),
      const _EmojiCategory(
        title: 'Food & drink',
        icon: Icons.local_cafe_rounded,
        emojis: food,
      ),
      const _EmojiCategory(
        title: 'Activities',
        icon: Icons.sports_soccer_rounded,
        emojis: activities,
      ),
      const _EmojiCategory(
        title: 'Travel & places',
        icon: Icons.directions_car_rounded,
        emojis: travel,
      ),
      const _EmojiCategory(
        title: 'Objects',
        icon: Icons.lightbulb_outline_rounded,
        emojis: objects,
      ),
      const _EmojiCategory(
        title: 'Symbols',
        icon: Icons.tag_rounded,
        emojis: symbols,
      ),
    ];

    if (!mounted) return;
    final emojiScrollController = ScrollController();
    final sectionKeys = List<GlobalKey>.generate(
      categories.length,
      (_) => GlobalKey(),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _composerBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        var selectedCategory = 0;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void updateCategoryFromScroll() {
              var activeIndex = selectedCategory;
              var lastVisibleTop = -double.infinity;
              var firstFutureIndex = -1;
              var firstFutureTop = double.infinity;
              final panelTop = MediaQuery.of(context).size.height * 0.48 + 28;
              for (var i = 0; i < sectionKeys.length; i++) {
                final currentContext = sectionKeys[i].currentContext;
                if (currentContext == null) continue;
                final renderObject = currentContext.findRenderObject();
                if (renderObject is! RenderBox || !renderObject.attached) {
                  continue;
                }
                final dy = renderObject.localToGlobal(Offset.zero).dy;
                if (dy <= panelTop && dy > lastVisibleTop) {
                  lastVisibleTop = dy;
                  activeIndex = i;
                } else if (dy > panelTop && dy < firstFutureTop) {
                  firstFutureTop = dy;
                  firstFutureIndex = i;
                }
              }
              if (lastVisibleTop == -double.infinity &&
                  firstFutureIndex != -1) {
                activeIndex = firstFutureIndex;
              }
              if (activeIndex != selectedCategory) {
                setSheetState(() => selectedCategory = activeIndex);
              }
            }

            void scrollToCategory(int index) {
              setSheetState(() => selectedCategory = index);
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final targetContext = sectionKeys[index].currentContext;
                if (targetContext == null) return;
                Scrollable.ensureVisible(
                  targetContext,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  alignment: 0.02,
                );
              });
            }

            return FractionallySizedBox(
              heightFactor: 0.52,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 48,
                      height: 5,
                      decoration: BoxDecoration(
                        color: _mutedTextColor.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) {
                          if (notification is ScrollUpdateNotification ||
                              notification is UserScrollNotification ||
                              notification is ScrollEndNotification) {
                            updateCategoryFromScroll();
                          }
                          return false;
                        },
                        child: ListView(
                          controller: emojiScrollController,
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                          children: [
                            for (var i = 0; i < categories.length; i++) ...[
                              KeyedSubtree(
                                key: sectionKeys[i],
                                child: _buildEmojiPickerTitle(
                                  categories[i].title,
                                ),
                              ),
                              _buildEmojiGrid(categories[i].emojis, message),
                              if (i != categories.length - 1)
                                const SizedBox(height: 18),
                            ],
                          ],
                        ),
                      ),
                    ),
                    _buildEmojiCategoryBar(
                      categories: categories,
                      selectedIndex: selectedCategory,
                      onSelected: scrollToCategory,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    emojiScrollController.dispose();
  }

  Widget _buildEmojiPickerTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
      child: Text(
        title,
        style: TextStyle(
          color: _mutedTextColor,
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildEmojiGrid(List<String> emojis, ChatMessage message) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisSpacing: 9,
        crossAxisSpacing: 4,
        childAspectRatio: 1,
      ),
      itemCount: emojis.length,
      itemBuilder: (context, index) {
        final emoji = emojis[index];
        return InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () {
            Navigator.of(context).pop();
            unawaited(_rememberReactionEmoji(emoji));
            unawaited(_toggleReaction(message, emoji));
          },
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 28)),
          ),
        );
      },
    );
  }

  Widget _buildEmojiCategoryBar({
    required List<_EmojiCategory> categories,
    required int selectedIndex,
    required ValueChanged<int> onSelected,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _dividerColor)),
      ),
      child: SizedBox(
        height: 56,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          itemBuilder: (context, index) {
            final active = index == selectedIndex;
            return InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: () => onSelected(index),
              child: Container(
                width: 42,
                height: 42,
                margin: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active
                      ? _mutedTextColor.withValues(alpha: 0.18)
                      : Colors.transparent,
                ),
                child: Icon(
                  categories[index].icon,
                  color: active
                      ? Theme.of(context).colorScheme.onSurface
                      : _mutedTextColor,
                  size: 23,
                ),
              ),
            );
          },
          separatorBuilder: (_, index) => const SizedBox(width: 8),
          itemCount: categories.length,
        ),
      ),
    );
  }

  /// Kullanıcının bu mesaja bıraktığı reaction (yoksa null).
  MessageReaction? _myReactionOf(ChatMessage message) {
    final me = _currentUserId;
    if (me == null) return null;
    for (final r in message.reactions) {
      if (r.userId == me) return r;
    }
    return null;
  }

  /// Reaction toggle — optimistic: UI anında güncellenir, hatada geri alınır.
  Future<void> _toggleReaction(ChatMessage message, String emoji) async {
    final cid = _normalizeChatId(_chatId);
    final me = _currentUserId;
    if (cid == null || me == null || message.id.startsWith('temp-')) return;

    final previous = message.reactions;
    final mine = _myReactionOf(message);
    final List<MessageReaction> optimistic;
    if (mine != null && mine.emoji == emoji) {
      optimistic = previous.where((r) => r.userId != me).toList();
    } else {
      optimistic = [
        ...previous.where((r) => r.userId != me),
        MessageReaction(userId: me, emoji: emoji),
      ];
    }
    _applyReactions(message.id, optimistic);

    try {
      final serverReactions = await _repo.toggleReaction(
        cid,
        message.id,
        emoji,
      );
      if (!mounted) return;
      _applyReactions(message.id, serverReactions);
    } catch (e) {
      debugPrint('❌ toggleReaction error: $e');
      if (!mounted) return;
      _applyReactions(message.id, previous);
    }
  }

  /// Kendi text mesajını düzenle: WhatsApp tarzı inline edit composer →
  /// optimistic güncelle → PATCH.
  Future<void> _startEditMessage(ChatMessage message) async {
    final cid = _normalizeChatId(_chatId);
    if (cid == null || message.id.startsWith('temp-')) return;

    final newText = await showGeneralDialog<String>(
      context: context,
      barrierLabel: 'edit-message',
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return _EditMessageComposerOverlay(
          animation: animation,
          initialText: message.text ?? '',
          bubblePreview: _buildBubbleClone(message, true),
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) => child,
    );
    if (newText == null || newText.isEmpty || newText == message.text) return;
    if (!mounted) return;

    final previousText = message.text;
    final previousEditedAt = message.editedAt;
    _mergeOrInsertMessage(
      message.copyWith(text: newText, editedAt: DateTime.now()),
      shouldScroll: false,
    );

    try {
      await _repo.editMessage(cid, message.id, text: newText);
    } catch (e) {
      debugPrint('❌ editMessage error: $e');
      if (!mounted) return;
      _mergeOrInsertMessage(
        message.copyWith(text: previousText, editedAt: previousEditedAt),
        shouldScroll: false,
      );
      await showPremiumErrorDialog(
        context,
        message:
            'Message could not be edited: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    }
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

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  Color get _chatBackground =>
      _isDarkMode ? AppColors.darkBg : const Color(0xFFF4F7FB);

  Color get _headerBackground =>
      _isDarkMode ? const Color(0xFF080F17) : Colors.white;

  Color get _composerBackground =>
      _isDarkMode ? const Color(0xFF080F17) : Colors.white;

  Color get _incomingBubbleColor =>
      _isDarkMode ? const Color(0xFF121B25) : Colors.white;

  Color get _incomingTextColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.94)
      : const Color(0xFF142033);

  Color get _mutedTextColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.56)
      : const Color(0xFF65758B);

  Color get _outgoingTextColor =>
      _isDarkMode ? Colors.white : const Color(0xFF0F2A4A);

  Color get _dividerColor => _isDarkMode
      ? Colors.white.withValues(alpha: 0.08)
      : const Color(0xFFE3EAF3);

  String _statusText(String name) {
    if (_isOtherTyping) return '${name.split(' ').first} is typing...';
    if (_isSocketReconnecting) return 'Baglaniyor...';
    if (_isSocketConnected && _isOtherOnline) return 'Online';
    if (_isOtherOnline) return 'Online';
    return 'Offline';
  }

  Color _statusColor() {
    if (_isOtherTyping) return AppTheme.brandPrimary;
    if (_isOtherOnline) return const Color(0xFF22C55E);
    return _mutedTextColor;
  }

  Widget _buildHeaderAvatar({
    required String avatarSeed,
    required Color avatarColor,
    required bool hasPhoto,
    required String photoUrl,
  }) {
    final initial = avatarSeed.trim().isNotEmpty
        ? avatarSeed.trim()[0].toUpperCase()
        : '?';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 44,
          height: 44,
          clipBehavior: Clip.antiAlias,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatarColor.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(13),
          ),
          child: hasPhoto
              ? CachedImage(
                  photoUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  errorWidget: (_) => Text(
                    initial,
                    style: TextStyle(
                      color: avatarColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                    ),
                  ),
                )
              : Text(
                  initial,
                  style: TextStyle(
                    color: avatarColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
        ),
        Positioned(
          right: -2,
          bottom: -2,
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: _isOtherOnline
                  ? const Color(0xFF22C55E)
                  : const Color(0xFF94A3B8),
              shape: BoxShape.circle,
              border: Border.all(color: _headerBackground, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final name = _chat?.displayOtherUser?.fullName ?? widget.otherName;
    final photoUrl = _chat?.displayOtherUser?.photo ?? widget.otherPhotoUrl;
    final avatarSeed = name.isNotEmpty ? name : _effectiveOtherUserId;
    final avatarColor = _avatarColor(avatarSeed);
    final hasPhoto = photoUrl.isNotEmpty;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: _chatBackground,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: _headerBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: IconThemeData(color: colors.onSurface),
        titleSpacing: 8,
        toolbarHeight: 72,
        shape: Border(bottom: BorderSide(color: _dividerColor, width: 1)),
        title: Row(
          children: [
            if (!_forwardSelectionMode) ...[
              const AppBackButton(),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: GestureDetector(
                onTap: _forwardSelectionMode ? null : _openOtherProfile,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      _buildHeaderAvatar(
                        avatarSeed: avatarSeed,
                        avatarColor: avatarColor,
                        hasPhoto: hasPhoto,
                        photoUrl: photoUrl,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 5),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 150),
                              transitionBuilder: (child, animation) =>
                                  FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                              child: Text(
                                _statusText(name),
                                key: ValueKey(_statusText(name)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: _statusColor(),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: _forwardSelectionMode
            ? [
                IconButton(
                  tooltip: 'Kapat',
                  icon: const Icon(Icons.close_rounded, size: 30),
                  onPressed: _exitForwardSelection,
                ),
                const SizedBox(width: 8),
              ]
            : const [],
      ),
      body: DecoratedBox(
        decoration: BoxDecoration(color: _chatBackground),
        child: Column(
          children: [
            Expanded(
              // Mesaj listesine dokununca klavye kapansın (WhatsApp davranışı).
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
                child: _buildMessageList(),
              ),
            ),
            _forwardSelectionMode
                ? _buildForwardSelectionBar()
                : _chat?.canSendMessages == false
                ? _buildInactiveBanner()
                : _buildMessageInput(),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageList() {
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
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.75),
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
            style: TextStyle(color: _mutedTextColor),
          ),
        ),
      );
    }
    final ordered = List<ChatMessage>.from(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    return Stack(
      children: [
        ListView.builder(
          controller: _scrollController,
          // Listede kaydırma başlayınca klavyeyi kapat (WhatsApp davranışı).
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(14, 14, 14, _messageListBottomPadding()),
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
            // Per-message read receipt: each of my messages shows "Seen" only when
            // the recipient actually read *that* message (read_at set). No shared
            // pointer, so reads made with receipts off never leak.
            final isSeenByOther = isMe && msg.readAt != null;
            final content = msg.messageType == 'image' && msg.imageUrl != null
                ? msg.imageUrl!
                : (msg.text ?? '');
            final showDate =
                msgIndex == 0 ||
                !_isSameDay(ordered[msgIndex - 1].createdAt, msg.createdAt);
            final bubbleKey = _keyFor(msg.id);
            final bubble = msg.messageType == 'image' && msg.imageUrl != null
                ? GestureDetector(
                    onLongPress: _forwardSelectionMode
                        ? null
                        : () => _openMessageOverlay(msg, isMe),
                    onTap: _forwardSelectionMode
                        ? null
                        : () => _openFullscreenImage(
                            msg.imageUrl!,
                            heroTag: 'chat-media-${msg.id}',
                          ),
                    child: _buildImageBubble(
                      msg.imageUrl!,
                      isMe,
                      time,
                      isSeenByOther,
                      bubbleKey: bubbleKey,
                      heroTag: 'chat-media-${msg.id}',
                    ),
                  )
                : msg.messageType == 'file' && msg.fileUrl != null
                ? GestureDetector(
                    onLongPress: _forwardSelectionMode
                        ? null
                        : () => _openMessageOverlay(msg, isMe),
                    onTap: _forwardSelectionMode
                        ? null
                        : () => unawaited(_openFileUrl(msg.fileUrl!)),
                    child: _buildFileBubble(
                      fileUrl: msg.fileUrl!,
                      fileName: msg.fileName ?? 'Document',
                      isMe: isMe,
                      time: time,
                      isSeenByOther: isSeenByOther,
                      bubbleKey: bubbleKey,
                    ),
                  )
                : GestureDetector(
                    onLongPress: _forwardSelectionMode
                        ? null
                        : () => _openMessageOverlay(msg, isMe),
                    child: _buildMessageBubble(
                      message: content,
                      isMe: isMe,
                      time: time,
                      isSeenByOther: isSeenByOther,
                      edited: msg.editedAt != null,
                      bubbleKey: bubbleKey,
                    ),
                  );
            // Reaction chip'leri balonun altına hafif bindirilmiş gösterilir.
            final bubbleWithReactions = msg.reactions.isEmpty
                ? bubble
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: isMe
                        ? CrossAxisAlignment.end
                        : CrossAxisAlignment.start,
                    children: [
                      bubble,
                      Transform.translate(
                        offset: const Offset(0, -14),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: _buildReactionChips(msg),
                        ),
                      ),
                    ],
                  );
            final selectableBubble = _forwardSelectionMode
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _toggleForwardSelection(msg),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 10, right: 8),
                          child: _buildForwardMessageSelector(
                            selected: _forwardSelectedMessageIds.contains(
                              msg.id,
                            ),
                          ),
                        ),
                        Expanded(child: bubbleWithReactions),
                      ],
                    ),
                  )
                : bubbleWithReactions;
            final item = showDate
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDateSeparator(msg.createdAt),
                      selectableBubble,
                    ],
                  )
                : selectableBubble;
            return KeyedSubtree(key: _itemKeyFor(msg.id), child: item);
          },
        ),
        if (_floatingDateText != null)
          Positioned(
            top: 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _showFloatingDate ? 1 : 0,
                duration: const Duration(milliseconds: 140),
                child: Center(
                  child: _buildFloatingDateChip(_floatingDateText!),
                ),
              ),
            ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Widget _buildDateSeparator(DateTime date) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _isDarkMode
              ? const Color(0xFF111B25).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _dividerColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          child: Text(
            _formatDateSeparator(date),
            style: TextStyle(
              color: _mutedTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFloatingDateChip(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _isDarkMode
            ? Colors.black.withValues(alpha: 0.74)
            : const Color(0xFF111827).withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.26 : 0.16),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
      ),
    );
  }

  Widget _buildForwardMessageSelector({required bool selected}) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? const Color(0xFFE85D55) : Colors.transparent,
        border: Border.all(
          color: selected
              ? const Color(0xFFE85D55)
              : Colors.white.withValues(alpha: _isDarkMode ? 0.32 : 0.65),
          width: 2,
        ),
      ),
      child: selected
          ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
          : null,
    );
  }

  Widget _buildForwardSelectionBar() {
    final count = _forwardSelectedMessageIds.length;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
      decoration: BoxDecoration(
        color: _composerBackground.withValues(alpha: _isDarkMode ? 0.88 : 0.96),
        border: Border(top: BorderSide(color: _dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.26 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            _buildForwardCircleButton(
              icon: Icons.forward_rounded,
              onPressed: _forwardSelectedMessages,
            ),
            Expanded(
              child: Text(
                '$count Selected',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 48, height: 48),
          ],
        ),
      ),
    );
  }

  /// Emoji bazında gruplanmış reaction chip'leri (örn. "❤️ 2").
  Widget _buildReactionChips(ChatMessage msg) {
    final grouped = <String, int>{};
    for (final r in msg.reactions) {
      grouped[r.emoji] = (grouped[r.emoji] ?? 0) + 1;
    }
    return Wrap(
      spacing: 4,
      children: [
        for (final entry in grouped.entries)
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => unawaited(_toggleReaction(msg, entry.key)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _composerBackground,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: _isDarkMode ? 0.24 : 0.08,
                    ),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                entry.value > 1 ? '${entry.key} ${entry.value}' : entry.key,
                style: TextStyle(
                  fontSize: 14,
                  color: _mutedTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMessageBubble({
    required String message,
    required bool isMe,
    required String time,
    required bool isSeenByOther,
    bool edited = false,
    Key? bubbleKey,
  }) {
    final textColor = isMe ? _outgoingTextColor : _incomingTextColor;
    final reply = _parseReplyMessage(message);
    final displayMessage = reply?.body ?? message;
    final isEmojiOnly = reply == null && _isEmojiOnlyMessage(displayMessage);
    final emojiCount = isEmojiOnly ? _emojiMessageCount(displayMessage) : 0;
    final messageFontSize = isEmojiOnly
        ? (emojiCount <= 3 ? 34.0 : 28.0)
        : 15.0;
    final screenWidth = MediaQuery.of(context).size.width;
    final bubbleRadius = _messageBubbleRadius(isMe);
    final bubbleChild = Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (reply != null) ...[
          _buildInlineReplyQuote(reply, isMe: isMe),
          const SizedBox(height: 6),
        ],
        Align(
          alignment: Alignment.centerLeft,
          widthFactor: reply == null ? 1 : null,
          child: Text(
            displayMessage,
            textAlign: TextAlign.left,
            style: TextStyle(
              color: textColor,
              fontSize: messageFontSize,
              height: isEmojiOnly ? 1.14 : 1.26,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        SizedBox(height: isEmojiOnly ? 2 : 3),
        _buildMessageMeta(
          time: time,
          isMe: isMe,
          isSeenByOther: isSeenByOther,
          textColor: textColor,
          edited: edited,
        ),
      ],
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: _buildStyledBubbleContainer(
        key: bubbleKey,
        isMe: isMe,
        borderRadius: bubbleRadius,
        constraints: BoxConstraints(
          minWidth: reply == null ? 0 : min(screenWidth * 0.42, 180),
          maxWidth: screenWidth * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(12, 8, 9, 5),
        child: bubbleChild,
      ),
    );
  }

  BorderRadius _messageBubbleRadius(bool isMe) {
    return BorderRadius.only(
      topLeft: const Radius.circular(15),
      topRight: const Radius.circular(15),
      bottomLeft: Radius.circular(isMe ? 15 : 4),
      bottomRight: Radius.circular(isMe ? 4 : 15),
    );
  }

  Widget _buildStyledBubbleContainer({
    required bool isMe,
    required BorderRadius borderRadius,
    required Widget child,
    Key? key,
    BoxConstraints? constraints,
    EdgeInsetsGeometry? padding,
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: isMe
            ? ImageFilter.blur(sigmaX: 14, sigmaY: 14)
            : ImageFilter.blur(sigmaX: 0, sigmaY: 0),
        child: Container(
          key: key,
          margin: const EdgeInsets.only(bottom: 7),
          constraints: constraints,
          padding: padding,
          decoration: BoxDecoration(
            color: isMe ? null : _incomingBubbleColor,
            gradient: isMe
                ? LinearGradient(
                    colors: _isDarkMode
                        ? [
                            Colors.white.withValues(alpha: 0.18),
                            AppColors.blueDark.withValues(alpha: 0.20),
                            AppColors.magentaDark.withValues(alpha: 0.13),
                          ]
                        : [
                            Colors.white.withValues(alpha: 0.74),
                            AppColors.blue.withValues(alpha: 0.18),
                            AppColors.magenta.withValues(alpha: 0.10),
                          ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            borderRadius: borderRadius,
            border: Border.all(
              color: isMe
                  ? Colors.white.withValues(alpha: _isDarkMode ? 0.24 : 0.62)
                  : _dividerColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(
                  alpha: isMe
                      ? (_isDarkMode ? 0.18 : 0.07)
                      : (_isDarkMode ? 0.12 : 0.035),
                ),
                blurRadius: isMe ? 12 : 7,
                offset: Offset(0, isMe ? 5 : 3),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  bool _isEmojiOnlyMessage(String message) {
    final compact = message.replaceAll(RegExp(r'\s+'), '');
    if (compact.isEmpty) return false;

    for (final rune in compact.runes) {
      if (_isEmojiRune(rune) || _isEmojiModifierRune(rune)) continue;
      return false;
    }
    return true;
  }

  int _emojiMessageCount(String message) {
    final compact = message.replaceAll(RegExp(r'\s+'), '');
    var count = 0;
    for (final rune in compact.runes) {
      if (_isEmojiRune(rune)) count++;
    }
    return max(1, count);
  }

  bool _isEmojiRune(int rune) {
    return (rune >= 0x1F000 && rune <= 0x1FAFF) ||
        (rune >= 0x2600 && rune <= 0x27BF) ||
        (rune >= 0x2300 && rune <= 0x23FF) ||
        (rune >= 0x1F1E6 && rune <= 0x1F1FF);
  }

  bool _isEmojiModifierRune(int rune) {
    return rune == 0x200D ||
        rune == 0xFE0F ||
        rune == 0xFE0E ||
        (rune >= 0x1F3FB && rune <= 0x1F3FF) ||
        (rune >= 0xE0020 && rune <= 0xE007F);
  }

  _ParsedReplyMessage? _parseReplyMessage(String message) {
    final lines = message.split('\n');
    if (lines.length < 2) return null;

    final firstLine = lines.first.trim();
    final match = RegExp(r'^↩(?:️)?\s*(.*)$').firstMatch(firstLine);
    if (match == null) return null;

    final payload = (match.group(1) ?? '').trim();
    final separatorIndex = payload.indexOf(':');
    if (separatorIndex < 0 || separatorIndex == payload.length - 1) {
      return null;
    }

    final rawSender = payload.substring(0, separatorIndex).trim();
    final quote = payload.substring(separatorIndex + 1).trim();
    final body = lines.skip(1).join('\n').trim();
    if (quote.isEmpty || body.isEmpty) return null;
    final sender = rawSender.isEmpty ? 'Reply' : rawSender;
    return _ParsedReplyMessage(sender: sender, quote: quote, body: body);
  }

  Widget _buildInlineReplyQuote(
    _ParsedReplyMessage reply, {
    required bool isMe,
  }) {
    final quoteBackground = isMe
        ? Colors.black.withValues(alpha: _isDarkMode ? 0.18 : 0.08)
        : AppTheme.brandPrimary.withValues(alpha: _isDarkMode ? 0.16 : 0.08);
    final quoteTextColor = isMe ? _outgoingTextColor : _incomingTextColor;
    final accentColor = isMe
        ? Colors.white.withValues(alpha: _isDarkMode ? 0.9 : 0.7)
        : AppTheme.brandPrimary;

    return SizedBox(
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: quoteBackground,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 2.5,
                  decoration: BoxDecoration(
                    color: accentColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        reply.sender,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: quoteTextColor,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        reply.quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: quoteTextColor.withValues(alpha: 0.78),
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageMeta({
    required String time,
    required bool isMe,
    required bool isSeenByOther,
    required Color textColor,
    bool edited = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (edited) ...[
          Text(
            'edited',
            style: TextStyle(
              color: textColor.withValues(alpha: 0.5),
              fontSize: 10,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(width: 4),
        ],
        Text(
          time,
          style: TextStyle(
            color: textColor.withValues(alpha: 0.58),
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        if (isMe) ...[
          const SizedBox(width: 4),
          _buildReadReceiptIcon(
            isSeenByOther: isSeenByOther,
            fallbackColor: textColor.withValues(alpha: 0.54),
          ),
        ],
      ],
    );
  }

  Widget _buildReadReceiptIcon({
    required bool isSeenByOther,
    required Color fallbackColor,
  }) {
    // WhatsApp tarzı: her zaman çift tik göster.
    // Okunmadıysa gri (fallbackColor), okununca mavi.
    return Icon(
      Icons.done_all_rounded,
      size: 16,
      color: isSeenByOther ? const Color(0xFF1A9FE8) : fallbackColor,
    );
  }

  /// Medyaya dokununca tam ekran (pinch-zoom destekli) görüntüleyici açar.
  /// Hem yüklenmiş (http) görselleri hem de henüz yüklenmekte olan optimistic
  /// lokal dosyaları destekler.
  void _openFullscreenImage(String imageUrl, {String? heroTag}) {
    if (imageUrl.isEmpty) return;
    Navigator.of(context).push(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.black,
        // Hero uçuşuyla çakışmaması için geçişi kısa tut.
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            _FullscreenImageViewer(imageUrl: imageUrl, heroTag: heroTag),
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  /// Verilen [tag] varsa [child]'ı Hero ile sarar; yoksa aynen döndürür.
  Widget _wrapHero(String? tag, Widget child) {
    if (tag == null) return child;
    return Hero(tag: tag, child: child);
  }

  Widget _buildImageBubble(
    String imageUrl,
    bool isMe,
    String time,
    bool isSeenByOther, {
    Key? bubbleKey,
    String? heroTag,
  }) {
    final textColor = isMe ? _outgoingTextColor : _incomingTextColor;
    final bubbleRadius = _messageBubbleRadius(isMe);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: _buildStyledBubbleContainer(
        key: bubbleKey,
        isMe: isMe,
        borderRadius: bubbleRadius,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.68,
        ),
        padding: const EdgeInsets.all(3),
        child: Stack(
          alignment: Alignment.bottomRight,
          children: [
            _wrapHero(
              heroTag,
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                // http olmayan url = henüz yüklenmemiş lokal dosya (optimistic).
                child: imageUrl.startsWith('http')
                    ? CachedImage(
                        imageUrl,
                        width: min(
                          MediaQuery.of(context).size.width * 0.62,
                          238,
                        ),
                        height: min(
                          MediaQuery.of(context).size.width * 0.62,
                          238,
                        ),
                        fit: BoxFit.cover,
                        errorWidget: (context) =>
                            const Icon(Icons.broken_image, size: 48),
                      )
                    : Stack(
                        alignment: Alignment.center,
                        children: [
                          Image.file(
                            File(imageUrl),
                            width: min(
                              MediaQuery.of(context).size.width * 0.62,
                              238,
                            ),
                            height: min(
                              MediaQuery.of(context).size.width * 0.62,
                              238,
                            ),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(Icons.broken_image, size: 48),
                          ),
                          const SizedBox(
                            width: 34,
                            height: 34,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.38),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  child: _buildMessageMeta(
                    time: time,
                    isMe: isMe,
                    isSeenByOther: isSeenByOther,
                    textColor: isMe ? Colors.white : textColor,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Belge balonu: ikon + dosya adı; http olmayan url = yükleniyor (spinner).
  Widget _buildFileBubble({
    required String fileUrl,
    required String fileName,
    required bool isMe,
    required String time,
    required bool isSeenByOther,
    Key? bubbleKey,
  }) {
    final textColor = isMe ? _outgoingTextColor : _incomingTextColor;
    final isUploading = !fileUrl.startsWith('http');
    final bubbleRadius = _messageBubbleRadius(isMe);
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: _buildStyledBubbleContainer(
        key: bubbleKey,
        isMe: isMe,
        borderRadius: bubbleRadius,
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.fromLTRB(10, 9, 9, 5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: textColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: isUploading
                      ? Padding(
                          padding: const EdgeInsets.all(9),
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: textColor,
                          ),
                        )
                      : Icon(
                          Icons.description_rounded,
                          color: textColor.withValues(alpha: 0.85),
                          size: 21,
                        ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            _buildMessageMeta(
              time: time,
              isMe: isMe,
              isSeenByOther: isSeenByOther,
              textColor: textColor,
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime date) {
    final local = date.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  String _formatDateSeparator(DateTime date) {
    final local = date.toLocal();
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(local.year, local.month, local.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    final dd = local.day.toString().padLeft(2, '0');
    final mm = local.month.toString().padLeft(2, '0');
    return '$dd.$mm.${local.year}';
  }

  Widget _buildInactiveBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: _composerBackground,
        border: Border(top: BorderSide(color: _dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.18 : 0.05),
            blurRadius: 8,
          ),
        ],
      ),
      child: SafeArea(
        child: Text(
          _chat?.isBlocked == true
              ? 'Messaging is paused because one of you blocked the other. You can still view your chat history.'
              : 'This chat is no longer active. You can still view your chat history.',
          textAlign: TextAlign.center,
          style: TextStyle(color: _mutedTextColor, fontSize: 13),
        ),
      ),
    );
  }

  Widget _buildMessageInput() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    const composerBlue = Color(0xFF1A9FE8);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: _composerBackground,
        border: Border(top: BorderSide(color: _dividerColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _isDarkMode ? 0.16 : 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_replyingTo != null) _buildReplyPreview(_replyingTo!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildComposerIconButton(
                  icon: Icons.add_rounded,
                  onPressed: _openAttachmentSheet,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 42),
                    decoration: BoxDecoration(
                      color: _isDarkMode
                          ? const Color(0xFF101927)
                          : const Color(0xFFF4F7FB),
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: _isDarkMode
                            ? composerBlue.withValues(alpha: 0.18)
                            : const Color(0xFFDDE7F1),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const SizedBox(width: 14),
                        Expanded(
                          child: TextField(
                            controller: _messageController,
                            onChanged: _onMessageTextChanged,
                            keyboardType: TextInputType.multiline,
                            textInputAction: TextInputAction.newline,
                            minLines: 1,
                            maxLines: 5,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 15.5,
                              height: 1.25,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              hintText: '',
                              hintStyle: TextStyle(color: _mutedTextColor),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 44,
                  height: 44,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: composerBlue,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: composerBlue.withValues(alpha: 0.30),
                          blurRadius: 12,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: IconButton(
                      tooltip: 'Gonder',
                      icon: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                      onPressed: _sendMessage,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// WhatsApp tarzı reply preview: composer'ın üstünde, kapatılabilir quote şeridi.
  Widget _buildReplyPreview(ChatMessage target) {
    final snippet = target.messageType == 'image'
        ? '📷 Photo'
        : target.messageType == 'file'
        ? '📄 ${target.fileName ?? 'Document'}'
        : (target.text ?? '').trim();
    final senderLabel = target.isSentByMe(_currentUserId)
        ? 'You'
        : widget.otherName.split(' ').first;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _isDarkMode ? const Color(0xFF131D29) : const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(14),
        border: Border(
          left: BorderSide(color: AppTheme.brandPrimary, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  style: TextStyle(
                    color: AppTheme.brandPrimary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _mutedTextColor, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close_rounded, color: _mutedTextColor, size: 20),
            onPressed: _cancelReply,
          ),
        ],
      ),
    );
  }

  Widget _buildComposerIconButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    const composerBlue = Color(0xFF1A9FE8);
    return SizedBox(
      width: 42,
      height: 42,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: composerBlue.withValues(alpha: 0.38)),
          color: _isDarkMode
              ? composerBlue.withValues(alpha: 0.10)
              : composerBlue.withValues(alpha: 0.08),
        ),
        child: IconButton(
          padding: EdgeInsets.zero,
          icon: Icon(icon, color: composerBlue, size: 25),
          onPressed: onPressed,
        ),
      ),
    );
  }

  /// WhatsApp tarzı ek menüsü: + butonuna basınca çıkan seçenekler.
  void _openAttachmentSheet() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _composerBackground,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        Widget option({
          required IconData icon,
          required String label,
          required Color color,
          VoidCallback? onTap,
        }) {
          final enabled = onTap != null;
          final effectiveColor = enabled
              ? color
              : _mutedTextColor.withValues(alpha: 0.45);
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: enabled
                ? () {
                    Navigator.of(ctx).pop();
                    onTap();
                  }
                : null,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 58,
                  height: 58,
                  decoration: BoxDecoration(
                    color: effectiveColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: effectiveColor, size: 27),
                ),
                const SizedBox(height: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled
                        ? _mutedTextColor
                        : _mutedTextColor.withValues(alpha: 0.45),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
            child: Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 22,
              spacing: 26,
              children: [
                option(
                  icon: Icons.photo_camera_rounded,
                  label: 'Camera',
                  color: const Color(0xFFE0457B),
                  onTap: () => _pickAndSendImage(ImageSource.camera),
                ),
                option(
                  icon: Icons.photo_library_rounded,
                  label: 'Photos',
                  color: const Color(0xFF7C5CFF),
                  onTap: () => _pickAndSendImage(ImageSource.gallery),
                ),
                // Location ve Event henüz hazır değil — pasif (basılamaz).
                option(
                  icon: Icons.location_on_rounded,
                  label: 'Location',
                  color: const Color(0xFF1FA855),
                ),
                option(
                  icon: Icons.description_rounded,
                  label: 'Document',
                  color: const Color(0xFF4A7DFF),
                  onTap: _pickAndSendFile,
                ),
                option(
                  icon: Icons.event_rounded,
                  label: 'Event',
                  color: const Color(0xFFE8A13A),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Belge seç → optimistic lokal bubble → Spaces'e yükle → file mesajı gönder.
  Future<void> _pickAndSendFile() async {
    if (_chat?.canSendMessages == false) return;
    final cid = _normalizeChatId(_chatId);
    if (cid == null) {
      unawaited(
        showPremiumErrorDialog(
          context,
          message:
              'This chat is not ready yet. Open the active conversation to send a message.',
        ),
      );
      return;
    }

    final FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const [
          'pdf',
          'doc',
          'docx',
          'xls',
          'xlsx',
          'ppt',
          'pptx',
          'txt',
          'csv',
        ],
      );
    } catch (e) {
      debugPrint('❌ file pick error: $e');
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not access the file. Please try again.',
      );
      return;
    }
    final pickedPath = result?.files.single.path;
    if (pickedPath == null || !mounted) return;
    final pickedName = result!.files.single.name;

    final clientMessageId = _nextClientMessageId();
    final optimisticTempId = 'temp-$clientMessageId';
    _mergeOrInsertMessage(
      ChatMessage(
        id: optimisticTempId,
        messageType: 'file',
        text: null,
        fileUrl: pickedPath,
        fileName: pickedName,
        createdAt: DateTime.now(),
        senderId: _currentUserId,
        isMe: true,
        clientMessageId: clientMessageId,
      ),
    );

    try {
      final uploaded = await _repo.uploadChatFile(File(pickedPath));
      final sentMessage = await _repo.sendMessage(
        cid,
        messageType: 'file',
        fileUrl: uploaded.url,
        fileName: uploaded.fileName.isNotEmpty ? uploaded.fileName : pickedName,
        clientMessageId: clientMessageId,
      );
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      _mergeOrInsertMessage(sentMessage);
    } catch (e) {
      debugPrint('❌ sendFile error: $e');
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      await showPremiumErrorDialog(
        context,
        message:
            'Document could not be sent: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    }
  }

  Future<void> _openFileUrl(String url) async {
    if (!url.startsWith('http')) return; // henüz yükleniyor
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the document.')),
      );
    }
  }

  /// Galeriden seç ya da kameradan çek → optimistic lokal bubble → Spaces'e
  /// yükle → image mesajı olarak gönder. Hata olursa bubble geri alınır.
  Future<void> _pickAndSendImage(ImageSource source) async {
    if (_chat?.canSendMessages == false) return;
    final cid = _normalizeChatId(_chatId);
    if (cid == null) {
      unawaited(
        showPremiumErrorDialog(
          context,
          message:
              'This chat is not ready yet. Open the active conversation to send a message.',
        ),
      );
      return;
    }

    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 82,
      );
    } catch (e) {
      debugPrint('❌ image pick error: $e');
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: source == ImageSource.camera
            ? 'Could not access the camera. Check camera permission in Settings.'
            : 'Could not access the gallery. Check photo permission in Settings.',
      );
      return;
    }
    if (picked == null || !mounted) return;

    final clientMessageId = _nextClientMessageId();
    final optimisticTempId = 'temp-$clientMessageId';
    // Lokal dosya yolu image_url olarak konur; bubble http olmayanı Image.file
    // ile çizer ve yükleme spinner'ı gösterir.
    _mergeOrInsertMessage(
      ChatMessage(
        id: optimisticTempId,
        messageType: 'image',
        text: null,
        imageUrl: picked.path,
        createdAt: DateTime.now(),
        senderId: _currentUserId,
        isMe: true,
        clientMessageId: clientMessageId,
      ),
    );

    try {
      final url = await _repo.uploadChatImage(File(picked.path));
      final sentMessage = await _repo.sendMessage(
        cid,
        messageType: 'image',
        imageUrl: url,
        clientMessageId: clientMessageId,
      );
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      _mergeOrInsertMessage(sentMessage);
    } catch (e) {
      debugPrint('❌ sendImage error: $e');
      if (!mounted) return;
      _removeMessageById(optimisticTempId);
      await showPremiumErrorDialog(
        context,
        message:
            'Photo could not be sent: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
      );
    }
  }
}

class _ParsedReplyMessage {
  final String sender;
  final String quote;
  final String body;

  const _ParsedReplyMessage({
    required this.sender,
    required this.quote,
    required this.body,
  });
}

class _EmojiCategory {
  final String title;
  final IconData icon;
  final List<String> emojis;

  const _EmojiCategory({
    required this.title,
    required this.icon,
    required this.emojis,
  });
}

/// WhatsApp tarzı mesaj düzenleme overlay'i: arka plan blur'lanır, düzenlenen
/// mesaj preview olarak görünür, input klavyenin hemen üstünde inline durur.
class _EditMessageComposerOverlay extends StatefulWidget {
  final Animation<double> animation;
  final String initialText;
  final Widget bubblePreview;

  const _EditMessageComposerOverlay({
    required this.animation,
    required this.initialText,
    required this.bubblePreview,
  });

  @override
  State<_EditMessageComposerOverlay> createState() =>
      _EditMessageComposerOverlayState();
}

class _EditMessageComposerOverlayState
    extends State<_EditMessageComposerOverlay> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _controller.selection = TextSelection.collapsed(
      offset: widget.initialText.length,
    );
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final next = _controller.text.trim();
    if (next.isEmpty) return;
    Navigator.of(context).pop(next);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = Theme.of(context).colorScheme;
    final fade = CurvedAnimation(
      parent: widget.animation,
      curve: Curves.easeOut,
    );
    final viewInsets = MediaQuery.of(context).viewInsets;
    final bottomPadding = viewInsets.bottom;
    final barColor = isDark
        ? const Color(0xFF141D18).withValues(alpha: 0.94)
        : Colors.white.withValues(alpha: 0.96);
    final inputColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color(0xFFF0F4F2);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE3EAF3);

    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: fade,
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
                  child: Container(
                    color: Colors.black.withValues(alpha: isDark ? 0.44 : 0.28),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: bottomPadding + 72,
              child: Align(
                alignment: Alignment.centerRight,
                child: widget.bubblePreview,
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomPadding,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: barColor,
                  border: Border(top: BorderSide(color: borderColor)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.1),
                      blurRadius: 20,
                      offset: const Offset(0, -8),
                    ),
                  ],
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        SizedBox(
                          width: 40,
                          height: 40,
                          child: IconButton(
                            tooltip: 'Vazgec',
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              Icons.close_rounded,
                              color: colors.onSurface,
                              size: 28,
                            ),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 44),
                            decoration: BoxDecoration(
                              color: inputColor,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(color: borderColor),
                            ),
                            child: TextField(
                              controller: _controller,
                              focusNode: _focusNode,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              minLines: 1,
                              maxLines: 4,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontSize: 16,
                                height: 1.25,
                                fontWeight: FontWeight.w500,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                hintText: 'Edit message',
                                hintStyle: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.45,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xFFE96A5B),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFE96A5B,
                                  ).withValues(alpha: 0.32),
                                  blurRadius: 14,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: IconButton(
                              tooltip: 'Save',
                              icon: const Icon(
                                Icons.check_rounded,
                                color: Colors.black,
                                size: 28,
                              ),
                              onPressed: _submit,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OverlayMenuItemSpec {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _OverlayMenuItemSpec(this.icon, this.label, this.onTap, this.color);
}

/// WhatsApp tarzı uzun-basma overlay içeriği: blur+karartılmış arka plan,
/// orijinal konumunda net kalan balon klonu, konuma göre yerleşen reaction
/// barı ve aksiyon menüsü. Route'un kendi `animation`'ı ile fade+scale yapılır
/// (ayrı bir AnimationController gerekmez), böylece açılış/kapanış otomatik
/// senkron kalır ve geri tuşu/dışına dokunma zaten route pop ile çalışır.
class _MessageActionOverlay extends StatelessWidget {
  final Animation<double> animation;
  final Offset bubbleOrigin;
  final Size bubbleSize;
  final bool isMe;
  final Widget bubbleChild;
  final List<String> reactionEmojis;
  final String? myReaction;
  final ValueChanged<String> onReaction;
  final VoidCallback onMoreReactions;
  final VoidCallback onReply;
  final VoidCallback onForward;
  final bool canCopy;
  final VoidCallback onCopy;
  final bool canEdit;
  final VoidCallback onEdit;
  final bool canDelete;
  final VoidCallback onDelete;
  final bool canReport;
  final VoidCallback onReport;

  const _MessageActionOverlay({
    required this.animation,
    required this.bubbleOrigin,
    required this.bubbleSize,
    required this.isMe,
    required this.bubbleChild,
    required this.reactionEmojis,
    required this.myReaction,
    required this.onReaction,
    required this.onMoreReactions,
    required this.onReply,
    required this.onForward,
    required this.canCopy,
    required this.onCopy,
    required this.canEdit,
    required this.onEdit,
    required this.canDelete,
    required this.onDelete,
    required this.canReport,
    required this.onReport,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final barBg = isDark ? const Color(0xFF0E1620) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE3EAF3);
    final shadow = [
      BoxShadow(
        color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.14),
        blurRadius: 20,
        offset: const Offset(0, 8),
      ),
    ];

    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final topSafe = mq.padding.top;
    final bottomSafe = mq.padding.bottom;

    const gap = 10.0;
    const reactionBarHeight = 56.0;
    final reactionBarWidth = (reactionEmojis.length + 1) * 42.0 + 14;

    final items = <_OverlayMenuItemSpec>[
      _OverlayMenuItemSpec(Icons.reply_rounded, 'Reply', onReply, null),
      _OverlayMenuItemSpec(Icons.forward_rounded, 'Forward', onForward, null),
      if (canCopy)
        _OverlayMenuItemSpec(Icons.copy_rounded, 'Copy', onCopy, null),
      if (canEdit)
        _OverlayMenuItemSpec(Icons.edit_outlined, 'Edit', onEdit, null),
      if (canDelete)
        _OverlayMenuItemSpec(
          Icons.delete_outline_rounded,
          'Delete',
          onDelete,
          const Color(0xFFEF4444),
        ),
      if (canReport)
        _OverlayMenuItemSpec(
          Icons.flag_outlined,
          'Report',
          onReport,
          const Color(0xFFEF4444),
        ),
    ];
    const menuItemHeight = 47.0;
    const menuWidth = 210.0;
    final menuHeight = items.length * menuItemHeight + 12;

    // Reaction barı her zaman balonun hemen üstünde durur (WhatsApp davranışı).
    double reactionBarTop = bubbleOrigin.dy - reactionBarHeight - gap;
    final minTop = topSafe + 8;
    if (reactionBarTop < minTop) reactionBarTop = minTop;

    // Menü varsayılan olarak balonun altına gider; sığmıyorsa (mesaj ekranın
    // altına yakınsa) reaction barının üstüne — yani mesajın üstüne — taşınır.
    final spaceBelowBubble =
        screenSize.height - bottomSafe - (bubbleOrigin.dy + bubbleSize.height);
    final fitsBelow = spaceBelowBubble >= (menuHeight + gap + 8);
    double menuTop;
    if (fitsBelow) {
      menuTop = bubbleOrigin.dy + bubbleSize.height + gap;
    } else {
      menuTop = reactionBarTop - menuHeight - gap;
      if (menuTop < minTop) menuTop = minTop;
    }

    double reactionBarLeft =
        bubbleOrigin.dx + bubbleSize.width / 2 - reactionBarWidth / 2;
    reactionBarLeft = reactionBarLeft.clamp(
      12.0,
      max(12.0, screenSize.width - reactionBarWidth - 12.0),
    );

    double menuLeft = isMe
        ? bubbleOrigin.dx + bubbleSize.width - menuWidth
        : bubbleOrigin.dx;
    menuLeft = menuLeft.clamp(
      12.0,
      max(12.0, screenSize.width - menuWidth - 12.0),
    );

    final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
    final bubbleScale = Tween<double>(
      begin: 0.96,
      end: 1.0,
    ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
    final barSlide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(fade);

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // 1) Blur + karartma — dışına dokunma kapatır (route zaten back'i handle eder).
          Positioned.fill(
            child: FadeTransition(
              opacity: fade,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    color: Colors.black.withValues(alpha: isDark ? 0.55 : 0.38),
                  ),
                ),
              ),
            ),
          ),
          // 2) Balon: orijinal konum/boyut korunur, sadece hafif scale-in — blur'un
          // ÜSTÜNDE olduğu için net kalır, arka plandaki her şey blur'lu görünür.
          Positioned(
            left: bubbleOrigin.dx,
            top: bubbleOrigin.dy,
            width: bubbleSize.width,
            height: bubbleSize.height,
            child: GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: ScaleTransition(
                scale: bubbleScale,
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Material(color: Colors.transparent, child: bubbleChild),
              ),
            ),
          ),
          // 3) Reaction barı
          Positioned(
            left: reactionBarLeft,
            top: reactionBarTop,
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: barSlide,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: barBg,
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: borderColor),
                    boxShadow: shadow,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final emoji in reactionEmojis)
                        InkWell(
                          borderRadius: BorderRadius.circular(24),
                          onTap: () => onReaction(emoji),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: myReaction == emoji
                                ? BoxDecoration(
                                    color: AppTheme.brandPrimary.withValues(
                                      alpha: 0.16,
                                    ),
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 25),
                            ),
                          ),
                        ),
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: onMoreReactions,
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            Icons.add_reaction_outlined,
                            size: 22,
                            color: isDark ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // 4) Aksiyon menüsü
          Positioned(
            left: menuLeft,
            top: menuTop,
            width: menuWidth,
            child: FadeTransition(
              opacity: fade,
              child: SlideTransition(
                position: barSlide,
                child: Container(
                  decoration: BoxDecoration(
                    color: barBg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: borderColor),
                    boxShadow: shadow,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        InkWell(
                          onTap: items[i].onTap,
                          borderRadius: BorderRadius.vertical(
                            top: i == 0
                                ? const Radius.circular(16)
                                : Radius.zero,
                            bottom: i == items.length - 1
                                ? const Radius.circular(16)
                                : Radius.zero,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  items[i].icon,
                                  size: 20,
                                  color:
                                      items[i].color ??
                                      (isDark
                                          ? Colors.white.withValues(alpha: 0.85)
                                          : const Color(0xFF142033)),
                                ),
                                const SizedBox(width: 14),
                                Text(
                                  items[i].label,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color:
                                        items[i].color ??
                                        (isDark
                                            ? Colors.white.withValues(
                                                alpha: 0.9,
                                              )
                                            : const Color(0xFF142033)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (i != items.length - 1)
                          Divider(
                            height: 1,
                            color: borderColor,
                            indent: 18,
                            endIndent: 18,
                          ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Sohbetteki bir görsele dokununca açılan tam ekran görüntüleyici.
/// Pinch-zoom + pan (InteractiveViewer) destekler. Hem yüklenmiş (http)
/// görselleri hem de optimistic lokal dosyaları gösterir.
///
/// Güvenli kapanma: boşluğa tek dokunuş yalnızca zoom seviyesi 1x iken kapatır —
/// kullanıcı yakınlaştırıp pan yaparken yanlışlıkla kapanmaz. Kapat butonu ve
/// çift dokunuşla zoom sıfırlama her zaman çalışır.
class _FullscreenImageViewer extends StatefulWidget {
  final String imageUrl;
  final String? heroTag;

  const _FullscreenImageViewer({required this.imageUrl, this.heroTag});

  @override
  State<_FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<_FullscreenImageViewer> {
  final TransformationController _transform = TransformationController();
  TapDownDetails? _doubleTapDetails;

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  bool get _isZoomed => _transform.value.getMaxScaleOnAxis() > 1.05;

  void _handleTap() {
    // Yalnızca zoom yokken tek dokunuş kapatır.
    if (_isZoomed) return;
    Navigator.of(context).maybePop();
  }

  void _handleDoubleTap() {
    if (_isZoomed) {
      _transform.value = Matrix4.identity();
      return;
    }
    // Dokunulan noktaya 2.5x yakınlaş.
    final position = _doubleTapDetails?.localPosition;
    if (position == null) return;
    const scale = 2.5;
    final x = -position.dx * (scale - 1);
    final y = -position.dy * (scale - 1);
    _transform.value = Matrix4.identity()
      ..translateByDouble(x, y, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  Widget _buildImage() {
    final url = widget.imageUrl;
    if (url.startsWith('http')) {
      return CachedImage(
        url,
        fit: BoxFit.contain,
        placeholder: (context) =>
            const Center(child: CircularProgressIndicator(color: Colors.white)),
        errorWidget: (context) => _errorIcon(),
      );
    }
    // Optimistic lokal dosya (henüz yüklenmekte olan).
    return Image.file(
      File(url),
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _errorIcon(),
    );
  }

  Widget _errorIcon() => const Center(
    child: Icon(Icons.broken_image, size: 64, color: Colors.white54),
  );

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage();
    if (widget.heroTag != null) {
      image = Hero(tag: widget.heroTag!, child: image);
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              onTap: _handleTap,
              onDoubleTapDown: (d) => _doubleTapDetails = d,
              onDoubleTap: _handleDoubleTap,
              child: InteractiveViewer(
                transformationController: _transform,
                minScale: 1,
                maxScale: 5,
                child: Center(child: image),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: Material(
              color: Colors.black38,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
