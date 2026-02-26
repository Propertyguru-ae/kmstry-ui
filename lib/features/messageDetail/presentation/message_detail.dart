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

  @override
  void initState() {
    super.initState();
    _chatId = widget.chatId;
    _loadCurrentUser();
    if (widget.chatId != null) {
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

  Future<void> _loadCurrentUser() async {
    try {
      final me = await AuthRepository().getMe();
      if (!mounted) return;
      setState(() {
        _currentUserId = me['id'] as String?;
      });
    } catch (_) {}
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
    // 🔐 Chat yoksa mesaj atılamaz
    if (_chatId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Chat is not ready yet')));
      return;
    }
    setState(() => _sending = true);
    _messageController.clear();

    try {
      final sent = await _repo.sendMessage(
        _chatId!,
        messageType: 'text',
        text: text,
      );
      if (!mounted) return;
      if (_chat != null) {
        setState(() {
          _chat = ChatDetail(
            id: _chat!.id,
            messages: [..._chat!.messages, sent],
            otherUser: _chat!.otherUser,
            participants: _chat!.participants,
          );
          _sending = false;
        });
      } else {
        await _loadChat();
        if (mounted) setState(() => _sending = false);
      }
    } catch (e) {
      debugPrint('❌ sendMessage error: $e');
      if (!mounted) return;
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

  Color _avatarColor(String seed) {
    final colors = <Color>[
      const Color(0xFF4F46E5),
      const Color(0xFF0EA5E9),
      const Color(0xFF10B981),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF8B5CF6),
      const Color(0xFF14B8A6),
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
          icon: Icon(
            Icons.arrow_back_ios,
            color: colors.onSurface,
            size: 20,
          ),
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
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 12,
                  ),
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
          return _buildImageBubble(msg.imageUrl!, isMe, time);
        }
        return _buildMessageBubble(message: content, isMe: isMe, time: time);
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
                onSubmitted: (_) => _sendMessage(),
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
