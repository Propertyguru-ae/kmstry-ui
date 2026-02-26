import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/people/data/match_item_model.dart';
import 'package:kmstry_frontend/features/people/data/match_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';

class NotificationPage extends StatefulWidget {
  const NotificationPage({super.key});

  @override
  State<NotificationPage> createState() => _NotificationPageState();
}

class _NotificationPageState extends State<NotificationPage> {
  final NotificationRepository _repo = NotificationRepository();
  final MatchRepository _matchRepo = MatchRepository();
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
      List<MatchItem> matches = const [];
      try {
        matches = await _matchRepo.getMatches();
      } catch (_) {}

      final matchById = <String, MatchItem>{
        for (final m in matches)
          if (m.matchId.isNotEmpty) m.matchId: m,
      };
      final matchByUserId = <String, MatchItem>{
        for (final m in matches)
          if (m.userId.isNotEmpty) m.userId: m,
      };

      if (!mounted) return;
      try {
        await _repo.markAllAsRead();
      } catch (_) {}
      if (!mounted) return;
      NotificationUnreadScope.of(context)?.updateUnreadCount(0);
      final asRead = list
          .map(
            (n) => NotificationModel(
              id: n.id,
              type: n.type,
              title: _enrichedTitle(n, matchById: matchById, matchByUserId: matchByUserId),
              body: _enrichedBody(n, matchById: matchById, matchByUserId: matchByUserId),
              data: _enrichedData(n, matchById: matchById, matchByUserId: matchByUserId),
              isRead: true,
              createdAt: n.createdAt,
              dedupeKey: n.dedupeKey,
            ),
          )
          .toList();
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
        return;
      }
    }

    if (n.type == 'match_created') {
      final data = n.data ?? const <String, dynamic>{};
      final chatId = data['chat_id'] as String? ?? data['chatId'] as String?;
      final userId =
          data['user_id'] as String? ??
          data['target_user_id'] as String? ??
          data['sender_id'] as String? ??
          data['userId'] as String?;
      final matchedName = _matchedName(n);

      if (userId != null && userId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MessageDetailPage(
              chatId: chatId,
              otherUserId: userId,
              otherName: matchedName,
              otherPhotoUrl: '',
            ),
          ),
        );
        return;
      }
    }

    // Interested / liked_you: open requester's profile (checkin context)
    if ((n.type == 'interested' || n.type == 'liked_you') && n.data != null) {
      final data = n.data!;
      final checkinId =
          data['checkin_id'] as String? ?? data['checkinId'] as String?;
      final venueId =
          data['venue_id'] as String? ?? data['venueId'] as String?;
      final userId =
          data['user_id'] as String? ??
          data['sender_id'] as String? ??
          data['target_user_id'] as String? ??
          data['userId'] as String?;
      if (checkinId != null &&
          venueId != null &&
          checkinId.isNotEmpty &&
          venueId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfilePreviewPage(
              checkinId: checkinId,
              venueId: venueId,
            ),
          ),
        );
        return;
      }

      if (userId != null && userId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfilePreviewPage(
              userId: userId,
              userName: n.title,
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

  String _matchedName(NotificationModel n) {
    final data = n.data ?? const <String, dynamic>{};
    debugPrint('data ne geliyir: $data');
    return (data['full_name'] as String? ??
            data['sender_name'] as String? ??
            data['name'] as String? ??
            data['fullName'] as String? ??
            n.title)
        .trim();
  }

  Map<String, dynamic>? _enrichedData(
    NotificationModel n, {
    required Map<String, MatchItem> matchById,
    required Map<String, MatchItem> matchByUserId,
  }) {
    if (n.type != 'match_created') return n.data;
    final source = n.data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(n.data!);

    final matchId = source['match_id'] as String? ?? source['matchId'] as String?;
    final userId =
        source['user_id'] as String? ??
        source['target_user_id'] as String? ??
        source['sender_id'] as String? ??
        source['userId'] as String?;
    final matched = (matchId != null && matchId.isNotEmpty)
        ? matchById[matchId]
        : (userId != null && userId.isNotEmpty ? matchByUserId[userId] : null);

    if (matched == null) return source;
    source['userId'] = source['userId'] ?? matched.userId;
    source['chatId'] = source['chatId'] ?? matched.chatId;
    source['fullName'] = source['fullName'] ?? matched.fullName;
    return source;
  }

  String _enrichedTitle(
    NotificationModel n, {
    required Map<String, MatchItem> matchById,
    required Map<String, MatchItem> matchByUserId,
  }) {
    if (n.type != 'match_created') return n.title;
    return 'New Kmstry';
  }

  String _enrichedBody(
    NotificationModel n, {
    required Map<String, MatchItem> matchById,
    required Map<String, MatchItem> matchByUserId,
  }) {
    if (n.type != 'match_created') return n.body;
    final enriched = _enrichedData(
      n,
      matchById: matchById,
      matchByUserId: matchByUserId,
    );
    final name =
        (enriched?['fullName'] as String? ??
                enriched?['full_name'] as String? ??
                enriched?['sender_name'] as String? ??
                enriched?['name'] as String? ??
                '')
            .trim();
    final safeName = name.isEmpty ? 'your match' : name;
    return "You've matched with $safeName. Start chat!";
  }

  String _displayTitle(NotificationModel n) {
    return n.title;
  }

  String _displayBody(NotificationModel n) {
    if (n.type == 'match_created') {
      return "You've matched with ${_matchedName(n)}. Start chat!";
    }
    return n.body;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'match_created':
        return Icons.favorite;
      case 'new_message':
        return Icons.chat_bubble_outline;
      case 'liked_you':
        return Icons.favorite_rounded;
      default:
        return Icons.notifications_none;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        title: Text(
          'Notifications',
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.75),
                ),
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
      return Center(
        child: Text(
          'No notifications',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colors.onSurface.withValues(alpha: 0.65),
          ),
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final time = _formatTime(n.createdAt);
    final icon = _iconForType(n.type);
    final title = _displayTitle(n);
    final body = _displayBody(n);
    return InkWell(
      onTap: () => _onNotificationTap(n),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colors.primary.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 28, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    time,
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
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
