import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final NotificationRepository _repo = NotificationRepository();
  List<NotificationModel> _list = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _repo.getNotifications(limit: 50);
      if (!mounted) return;
      try {
        await _repo.markAllAsRead();
      } catch (_) {}
      if (!mounted) return;
      NotificationUnreadScope.of(context)?.updateUnreadCount(0);
      final asRead = list.map((n) => NotificationModel(
        id: n.id,
        type: n.type,
        title: n.title,
        body: n.body,
        data: n.data,
        isRead: true,
        createdAt: n.createdAt,
        dedupeKey: n.dedupeKey,
      )).toList();
      setState(() {
        _list = asRead;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _onNotificationTap(NotificationModel n) {
    if (n.type == 'new_message' && n.data != null) {
      final chatId = n.data!['chatId'] as String?;
      final senderId = n.data!['senderId'] as String?;
      if (chatId != null && chatId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => MessageDetailPage(
              chatId: chatId,
              otherUserId: senderId ?? '',
              otherName: n.title,
              otherPhotoUrl: '',
            ),
          ),
        );
      }
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 2) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'match_created':
        return Icons.favorite;
      case 'new_message':
        return Icons.chat_bubble_outline;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Notifications',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading && _list.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _list.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Could not load notifications',
                style: TextStyle(color: Colors.grey[700]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: _loadNotifications,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_list.isEmpty) {
      return const Center(
        child: Text(
          'No notifications',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadNotifications,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        itemCount: _list.length,
        itemBuilder: (context, index) {
          final n = _list[index];
          return _buildNotificationItem(n);
        },
      ),
    );
  }

  Widget _buildNotificationItem(NotificationModel n) {
    final time = _formatTime(n.createdAt);
    final icon = _iconForType(n.type);
    return InkWell(
      onTap: () => _onNotificationTap(n),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: Colors.grey[600]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    n.title,
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    n.body,
                    style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(color: Colors.grey[400], fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
