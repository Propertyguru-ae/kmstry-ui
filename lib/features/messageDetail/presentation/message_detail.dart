import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_detail_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_message_model.dart';
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

class _MessageDetailPageState extends State<MessageDetailPage> {
  final ChatRepository _repo = ChatRepository();
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

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

  @override
  void initState() {
    super.initState();
    _chatId = _normalizeChatId(widget.chatId);
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
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
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
    } catch (_) {}
  }

  /// Boş string veya sadece boşluk gelen chatId'yi yok say (ilk mesajda createChat çalışsın).
  String? _normalizeChatId(String? id) {
    if (id == null) return null;
    final t = id.trim();
    return t.isEmpty ? null : t;
  }

  bool _isChatNotActiveError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('not active') || s.contains('chat is not active');
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
    final otherId = widget.otherUserId.trim();
    if (otherId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kullanıcı bilgisi eksik, mesaj gönderilemez.'),
        ),
      );
      return;
    }

    setState(() => _sending = true);
    _messageController.clear();

    try {
      String? cid = _normalizeChatId(_chatId);
      if (cid == null) {
        cid = await _repo.createChat(otherId);
        if (!mounted) return;
        setState(() => _chatId = cid);
      }

      ChatMessage? sent;
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          sent = await _repo.sendMessage(cid!, messageType: 'text', text: text);
          break;
        } catch (e) {
          if (attempt == 0 && _isChatNotActiveError(e)) {
            debugPrint(
              '⚠️ sendMessage: sohbet aktif değil, createChat ile yenileniyor...',
            );
            final newId = await _repo.createChat(otherId);
            if (!mounted) return;
            cid = newId;
            setState(() => _chatId = cid);
            continue;
          }
          rethrow;
        }
      }

      if (!mounted || sent == null) return;
      final sentMessage = sent;

      if (_chat != null) {
        setState(() {
          _chat = ChatDetail(
            id: _chat!.id,
            messages: [..._chat!.messages, sentMessage],
            otherUser: _chat!.otherUser,
            participants: _chat!.participants,
          );
          _sending = false;
        });
        _scrollToBottom(animated: true);
      } else {
        await _loadChat();
        if (mounted) setState(() => _sending = false);
      }
    } catch (e) {
      debugPrint('❌ sendMessage error: $e');
      if (!mounted) return;
      _messageController.text = text;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mesaj gönderilemedi: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
          ),
        ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Mesaj silinemedi: ${e.toString().replaceAll(RegExp(r'^Exception:?\s*'), '')}',
          ),
        ),
      );
    }
  }

  Future<bool> _confirmDeleteMessage() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colors = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('Are you sure you want to delete this message?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: colors.error,
                foregroundColor: colors.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete'),
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
                leading: const Icon(Icons.push_pin_outlined),
                title: const Text('Pin'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pin will be available soon')),
                  );
                },
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
      const Color(0xFF4F46E5),
      const Color(0xFF0EA5E9),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF5D8CFF),
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
                  'Online',
                  style: TextStyle(color: colors.primary, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.videocam_outlined, color: colors.onSurface),
            onPressed: () {},
          ),
          IconButton(
            icon: Icon(Icons.call_outlined, color: colors.onSurface),
            onPressed: () {},
          ),
        ],
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
            'Henüz chat açılmadı / eşleşme yok.\nİlk mesajı göndererek başlayabilirsin.',
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
        final content = msg.messageType == 'image' && msg.imageUrl != null
            ? msg.imageUrl!
            : (msg.text ?? '');
        if (msg.messageType == 'image' && msg.imageUrl != null) {
          return GestureDetector(
            onLongPress: () => _showMessageActions(msg, isMe),
            child: _buildImageBubble(msg.imageUrl!, isMe, time),
          );
        }
        return GestureDetector(
          onLongPress: () => _showMessageActions(msg, isMe),
          child: _buildMessageBubble(message: content, isMe: isMe, time: time),
        );
      },
    );
  }

  Widget _buildMessageBubble({
    required String message,
    required bool isMe,
    required String time,
  }) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final incomingBubble = theme.brightness == Brightness.dark
        ? colors.surface.withValues(alpha: 0.8)
        : colors.surface.withValues(alpha: 0.95);

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
              time,
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

  Widget _buildImageBubble(String imageUrl, bool isMe, String time) {
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
              time,
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
            IconButton(
              icon: Icon(Icons.add_circle_outline, color: colors.primary),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                minLines: 1,
                maxLines: 5,
                decoration: InputDecoration(
                  hintText: 'Type a message...',
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
