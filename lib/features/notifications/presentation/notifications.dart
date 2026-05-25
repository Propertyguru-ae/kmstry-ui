import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/messageDetail/presentation/message_detail.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_model.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_realtime_service.dart';
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
  final NotificationRealtimeService _realtime = NotificationRealtimeService();
  List<NotificationModel> _list = [];
  bool _loading = true;
  String? _error;
  String _activeContextType = 'PERSONAL';
  String? _activeVenueId;
  static const int _daysWindow = 30;
  StreamSubscription<NotificationRealtimeEnvelope>? _eventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _bindRealtime();
    unawaited(_realtime.ensureConnected());
    _loadNotifications();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _stateSub?.cancel();
    super.dispose();
  }

  Future<void> _loadNotifications() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      try {
        final me = await AuthRepository().getMe();
        final lastContext =
            (me['lastActiveContext'] ?? me['last_active_context'])
                ?.toString()
                .toUpperCase();
        _activeContextType = lastContext == 'VENUE' ? 'VENUE' : 'PERSONAL';
        _activeVenueId = (me['activeVenueId'] ?? me['active_venue_id'])
            ?.toString()
            .trim();
        if (_activeVenueId?.isEmpty == true) _activeVenueId = null;
      } catch (_) {}

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
          .where(_isVisibleForCurrentContext)
          .where((n) => n.type != 'new_message')
          .map(
            (n) => NotificationModel(
              id: n.id,
              type: n.type,
              title: _enrichedTitle(
                n,
                matchById: matchById,
                matchByUserId: matchByUserId,
              ),
              body: _enrichedBody(
                n,
                matchById: matchById,
                matchByUserId: matchByUserId,
              ),
              data: _enrichedData(
                n,
                matchById: matchById,
                matchByUserId: matchByUserId,
              ),
              contextType: n.contextType,
              venueId: n.venueId,
              isRead: true,
              createdAt: n.createdAt,
              dedupeKey: n.dedupeKey,
            ),
          )
          .where((n) => !_isStaleInterestedAfterMatch(n))
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

  bool _isVisibleForCurrentContext(NotificationModel n) {
    final itemContext = n.contextType?.toUpperCase();
    if (itemContext == null || itemContext.isEmpty) return true;
    if (itemContext != _activeContextType) return false;
    if (itemContext == 'VENUE') {
      final itemVenueId = n.venueId?.trim();
      if (_activeVenueId == null || _activeVenueId!.isEmpty) return true;
      if (itemVenueId == null || itemVenueId.isEmpty) return true;
      return itemVenueId == _activeVenueId;
    }
    return true;
  }

  void _bindRealtime() {
    _stateSub = _realtime.connectionState.listen((state) {
      if (!mounted) return;
      if (state == ChatRealtimeConnectionState.connected ||
          state == ChatRealtimeConnectionState.reconnecting) {
        unawaited(_loadNotifications());
      }
    });

    _eventsSub = _realtime.events.listen((envelope) {
      if (!mounted) return;
      final unread = _readUnreadCount(envelope.payload);
      if (unread != null) {
        NotificationUnreadScope.of(context)?.updateUnreadCount(unread);
      }

      switch (envelope.event) {
        case 'notification.created':
        case 'notification.updated':
        case 'notification.read':
          if (!_applyNotificationEvent(envelope.payload)) {
            unawaited(_loadNotifications());
          }
          return;
        case 'socket.reconnected':
          unawaited(_loadNotifications());
          return;
      }
    });
  }

  int? _readUnreadCount(Map<String, dynamic> payload) {
    final raw = payload['unreadCount'] ?? payload['unread_count'];
    if (raw is int) return raw;
    if (raw == null) return null;
    return int.tryParse(raw.toString());
  }

  bool _applyNotificationEvent(Map<String, dynamic> payload) {
    final rawNotification = payload['notification'];
    final notificationMap = rawNotification is Map
        ? Map<String, dynamic>.from(rawNotification)
        : Map<String, dynamic>.from(payload);
    // No id → meta-only event (e.g. bulk-read count update). Already handled
    // via unreadCount field above; nothing to insert into the list.
    if (notificationMap['id'] == null) return true;
    final model = NotificationModel.fromJson(notificationMap);
    // 'system' type entries are internal signals, not displayable notifications.
    if (model.type == 'system') return true;
    if (model.type == 'new_message') return true;
    if (!_isVisibleForCurrentContext(model)) return true;
    if (_isStaleInterestedAfterMatch(model)) return true;

    if (!mounted) return true;
    setState(() {
      final existingIndex = _list.indexWhere((n) => n.id == model.id);
      if (existingIndex >= 0) {
        _list[existingIndex] = model;
      } else {
        _list.insert(0, model);
      }
      _list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    });
    return true;
  }

  Future<void> _onNotificationTap(NotificationModel n) async {
    final data = _profileContextData(n);

    if (n.type == 'new_message' && n.data != null) {
      final chatId = _firstNonEmptyString(data, const ['chatId', 'chat_id']);
      final senderId = _firstNonEmptyString(data, const [
        'senderId',
        'sender_id',
        'userId',
        'user_id',
      ]);
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
      final chatId = _firstNonEmptyString(data, const ['chat_id', 'chatId']);
      final userId = _firstNonEmptyString(data, const [
        'user_id',
        'target_user_id',
        'sender_id',
        'requester_id',
        'actor_user_id',
        'userId',
        'targetUserId',
        'senderId',
        'requesterId',
        'actorUserId',
      ]);
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
    if (n.type == 'interested' || n.type == 'liked_you') {
      final actionHint = _inferActionHintFromNotification(data, n.type);
      final checkinId = _firstNonEmptyString(data, const [
        'checkin_id',
        'checkinId',
      ]);
      final venueId = _firstNonEmptyString(data, const ['venue_id', 'venueId']);
      final userId = _firstNonEmptyString(data, const [
        'user_id',
        'sender_id',
        'requester_id',
        'actor_user_id',
        'target_user_id',
        'userId',
        'senderId',
        'requesterId',
        'actorUserId',
        'targetUserId',
      ]);
      final userName = _firstNonEmptyString(data, const [
        'fullName',
        'full_name',
        'sender_name',
        'name',
      ]);
      final username = _firstNonEmptyString(data, const [
        'username',
        'user_name',
        'sender_username',
        'senderUsername',
      ]);
      if (checkinId != null && checkinId.isNotEmpty) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfilePreviewPage(
              checkinId: checkinId,
              venueId: venueId,
              userId: userId,
              userName: userName,
              userUsername: username,
              actionStateHint:
                  actionHint ?? ProfileActionState.incomingInterested,
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
              userName: userName ?? n.title,
              userUsername: username,
              actionStateHint:
                  actionHint ?? ProfileActionState.incomingInterested,
            ),
          ),
        );
        return;
      }

      await showPremiumErrorDialog(
        context,
        message: 'Profile data is not available for this notification.',
      );
    }
  }

  Map<String, dynamic> _normalizeNotificationData(Map<String, dynamic>? data) {
    final source = data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(data);
    final nested = source['data'];
    if (nested is Map) {
      source.addAll(Map<String, dynamic>.from(nested));
    }
    final payload = source['payload'];
    if (payload is Map) {
      source.addAll(Map<String, dynamic>.from(payload));
    }
    return source;
  }

  Map<String, dynamic> _profileContextData(NotificationModel n) {
    final source = _normalizeNotificationData(n.data);
    final relatedUser =
        _asMap(source['relatedUser']) ?? _asMap(source['related_user']);
    if (relatedUser != null) {
      source['userId'] = source['userId'] ?? relatedUser['id'];
      source['user_id'] = source['user_id'] ?? relatedUser['id'];
      source['username'] = source['username'] ?? relatedUser['username'];
      source['user_name'] = source['user_name'] ?? relatedUser['user_name'];
      source['fullName'] = source['fullName'] ?? relatedUser['fullName'];
      source['full_name'] = source['full_name'] ?? relatedUser['full_name'];
    }

    final activeCheckin =
        _asMap(source['activeCheckin']) ?? _asMap(source['active_checkin']);
    if (activeCheckin != null) {
      source['checkinId'] = source['checkinId'] ?? activeCheckin['id'];
      source['checkin_id'] = source['checkin_id'] ?? activeCheckin['id'];
      source['venueId'] = source['venueId'] ?? activeCheckin['venueId'];
      source['venue_id'] = source['venue_id'] ?? activeCheckin['venue_id'];
    }
    return source;
  }

  String? _firstNonEmptyString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final str = value.toString().trim();
      if (str.isNotEmpty && str.toLowerCase() != 'null') return str;
    }
    return null;
  }

  ProfileActionState? _inferActionHintFromNotification(
    Map<String, dynamic> data,
    String type,
  ) {
    final rel = _asMap(data['relationship']);
    final myActionObj = _asMap(rel?['myAction']);
    final theirActionObj = _asMap(rel?['theirAction']);
    final matchObj = _asMap(rel?['match']);

    final status = _firstNonEmptyString(rel ?? data, const [
      'status',
      'relationshipStatus',
      'relationship_status',
    ])?.toLowerCase();
    final myAction = _firstNonEmptyString(myActionObj ?? rel ?? data, const [
      'action',
      'myAction',
      'my_action',
      'feedAction',
      'feed_action',
    ])?.toLowerCase();
    final theirAction = _firstNonEmptyString(
      theirActionObj ?? rel ?? data,
      const [
        'action',
        'theirAction',
        'their_action',
        'incomingAction',
        'incoming_action',
      ],
    )?.toLowerCase();
    final chatId = _firstNonEmptyString(matchObj ?? rel ?? data, const [
      'chatId',
      'chat_id',
    ]);

    bool hasAny(String? value, List<String> candidates) =>
        value != null && value.isNotEmpty && candidates.contains(value);

    if (hasAny(status, const ['matched']) ||
        (chatId != null && chatId.isNotEmpty)) {
      return ProfileActionState.matched;
    }
    if (hasAny(status, const [
      'incoming_interested',
      'liked_you',
      'incoming',
      'received_interest',
    ])) {
      return ProfileActionState.incomingInterested;
    }
    if (hasAny(status, const [
      'outgoing_interested',
      'waiting_response',
      'pending',
      'requested',
    ])) {
      return ProfileActionState.waitingResponse;
    }
    if (hasAny(status, const ['outgoing_pass'])) {
      return ProfileActionState.proactivePass;
    }
    if (hasAny(status, const ['incoming_pass'])) {
      return ProfileActionState.showActions;
    }
    if (hasAny(theirAction, const ['interested'])) {
      if (hasAny(myAction, const ['interested'])) {
        return ProfileActionState.matched;
      }
      return ProfileActionState.incomingInterested;
    }
    if (hasAny(myAction, const ['interested'])) {
      return ProfileActionState.waitingResponse;
    }
    if (hasAny(myAction, const ['pass'])) {
      return ProfileActionState.proactivePass;
    }
    if (type == 'interested' || type == 'liked_you') {
      return ProfileActionState.incomingInterested;
    }
    return null;
  }

  bool _isStaleInterestedAfterMatch(NotificationModel n) {
    if (n.type != 'interested' && n.type != 'liked_you') return false;
    final data = _profileContextData(n);
    final hint = _inferActionHintFromNotification(data, n.type);
    return hint == ProfileActionState.matched;
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
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

    final matchId =
        source['match_id'] as String? ?? source['matchId'] as String?;
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
    return 'Connection made';
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
    return "You and $safeName are now connected. Say hi when you're ready.";
  }

  String _displayTitle(NotificationModel n) {
    return n.title;
  }

  String _displayBody(NotificationModel n) {
    if (n.type == 'match_created') {
      return "You and ${_matchedName(n)} are now connected. Say hi when you're ready.";
    }
    return n.body;
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'match_created':
        return Icons.auto_awesome_rounded;
      case 'new_message':
        return Icons.chat_bubble_outline;
      case 'liked_you':
        return Icons.visibility_rounded;
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
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Notifications',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(
            color: theme.brightness == Brightness.dark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.grey[200],
            height: 1,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: _daysWindow));
    final recentList = _list
        .where((n) => !n.createdAt.isBefore(cutoff))
        .toList();
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
    if (recentList.isEmpty) {
      return Center(
        child: Text(
          'No notifications in last 30 days',
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
        itemCount: recentList.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(2, 4, 2, 12),
              child: Text(
                'Last 30 days',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: colors.onSurface.withValues(alpha: 0.88),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            );
          }
          final n = recentList[index - 1];
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
          border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
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
