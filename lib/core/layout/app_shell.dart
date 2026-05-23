import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/people/presentation/people_page.dart';
import 'package:kmstry_frontend/features/messages/presntation/messages.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notifications.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_realtime_service.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_profile_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_owner_guests_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_pending_page.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;
  /// When true the shell opens directly in venue mode — no personal-tab flash.
  final bool initialIsVenueContext;
  /// Passed straight through to venue tabs so they don't re-fetch context.
  final String? initialVenueId;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.initialIsVenueContext = false,
    this.initialVenueId,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  String _userInitial = 'D';
  int _unreadNotificationCount = 0;
  int _unreadDmCount = 0;
  final NotificationRepository _notificationRepo = NotificationRepository();
  final NotificationRealtimeService _notificationRealtime =
      NotificationRealtimeService();
  final ChatRepository _chatRepo = ChatRepository();
  final ChatRealtimeService _chatRealtime = ChatRealtimeService();
  final Map<String, int> _chatUnreadById = <String, int>{};
  StreamSubscription<ChatRealtimeEnvelope>? _chatEventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _chatStateSub;
  StreamSubscription<NotificationRealtimeEnvelope>? _notificationEventsSub;
  StreamSubscription<ChatRealtimeConnectionState>? _notificationStateSub;
  StreamSubscription<dynamic>? _foregroundPushSub;
  Timer? _dmRefreshDebounce;
  Timer? _notificationRefreshDebounce;

  final GlobalKey<DmListPageState> _dmListKey =
      GlobalKey<
        DmListPageState
      >(); // ignore: library_private_types_in_public_api

  bool _isVenueContext = false;
  bool _hasPersonalProfile = false;
  String _personalAccountLabel = 'Personal';
  String? _activeVenueId;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    // Apply auth-gate context immediately so the first frame is correct.
    if (widget.initialIsVenueContext) {
      _isVenueContext = true;
      _activeVenueId = widget.initialVenueId;
    }
    WidgetsBinding.instance.addObserver(this);
    _bindChatRealtime();
    _bindNotificationRealtime();
    unawaited(_connectChatRealtime());
    unawaited(_notificationRealtime.ensureConnected());
    _loadUserInitial();
    _loadUnreadNotificationCount();
    _loadUnreadDmCount();
    PushManager.instance.reconcileNotificationState();
    _initCheckinPing();
  }

  void _initCheckinPing() {
    CheckinPingManager.I.configure(
      getLocation: () async {
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        );
        return (lat: pos.latitude, lng: pos.longitude);
      },
      onCheckinExpired: () {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Check-in süren sona erdi. Tekrar check-in yapabilirsin.'),
            duration: const Duration(seconds: 5),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
    CheckinPingManager.I.ensureRunning();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatEventsSub?.cancel();
    _chatStateSub?.cancel();
    _notificationEventsSub?.cancel();
    _notificationStateSub?.cancel();
    _foregroundPushSub?.cancel();
    _dmRefreshDebounce?.cancel();
    _notificationRefreshDebounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_connectChatRealtime());
      unawaited(_notificationRealtime.ensureConnected());
      PushManager.instance.reconcileNotificationState();
      _loadUnreadNotificationCount();
      _loadUnreadDmCount();
      CheckinPingManager.I.ensureRunning();
      // Venue onay/red durumu arka plandan dönerken güncellensin.
      AuthRepository.invalidateMeCache();
      _loadUserInitial();
    } else if (state == AppLifecycleState.paused) {
      CheckinPingManager.I.stop();
    }
  }

  Future<void> _loadUnreadNotificationCount() async {
    try {
      final count = await _notificationRepo.getUnreadCount();
      if (!mounted) return;
      setState(() => _unreadNotificationCount = count);
    } catch (_) {
      try {
        final list = await _notificationRepo.getNotifications(limit: 50);
        if (!mounted) return;
        final count = list
            .where((n) => !n.isRead && n.type != 'new_message')
            .length;
        setState(() => _unreadNotificationCount = count);
      } catch (_) {}
    }
  }

  Future<void> _loadUnreadDmCount() async {
    try {
      final chats = await _chatRepo.getChats();
      if (!mounted) return;
      _applyDmUnreadFromChats(chats);
    } catch (_) {}
  }

  void _applyDmUnreadFromChats(List<ChatListItem> chats) {
    final nextMap = <String, int>{};
    var total = 0;
    for (final chat in chats) {
      final unread = chat.unreadCount;
      nextMap[chat.id] = unread;
      total += unread;
    }
    if (!mounted) return;
    setState(() {
      _chatUnreadById
        ..clear()
        ..addAll(nextMap);
      _unreadDmCount = total;
    });
  }

  Future<void> _connectChatRealtime() async {
    final token = await SecureStorage.getAccessToken();
    if (!mounted || token == null || token.trim().isEmpty) return;
    await _chatRealtime.connectWithToken(token: token);
  }

  void _bindChatRealtime() {
    _chatStateSub = _chatRealtime.connectionState.listen((state) {
      if (!mounted) return;
      if (state == ChatRealtimeConnectionState.connected ||
          state == ChatRealtimeConnectionState.reconnecting) {
        _scheduleDmRefresh();
      }
    });

    _chatEventsSub = _chatRealtime.events.listen((envelope) {
      if (!mounted) return;
      switch (envelope.event) {
        case 'chat.unread.updated':
          if (!_applyDmUnreadPatch(envelope.payload)) {
            _scheduleDmRefresh();
          }
          return;
        case 'chat.updated':
        case 'message.created':
          if (!_applyDmUnreadPatch(envelope.payload)) {
            _scheduleDmRefresh();
          }
          return;
        case 'chat.read':
        case 'socket.reconnected':
          _scheduleDmRefresh();
          return;
      }
    });
  }

  void _bindNotificationRealtime() {
    _notificationStateSub = _notificationRealtime.connectionState.listen((state) {
      if (!mounted) return;
      if (state == ChatRealtimeConnectionState.connected ||
          state == ChatRealtimeConnectionState.reconnecting) {
        _scheduleNotificationRefresh();
      }
    });

    _notificationEventsSub = _notificationRealtime.events.listen((envelope) {
      if (!mounted) return;
      switch (envelope.event) {
        case 'notification.created':
          if (!_applyNotificationUnreadPatch(envelope.payload)) {
            final type = _readStringField(envelope.payload, const ['type']);
            if (type != 'new_message') {
              setState(() {
                _unreadNotificationCount += 1;
              });
            }
          }
          return;
        case 'notification.updated':
        case 'notification.read':
        case 'socket.reconnected':
          if (!_applyNotificationUnreadPatch(envelope.payload)) {
            _scheduleNotificationRefresh();
          }
          return;
      }
    });

    _foregroundPushSub = PushManager.instance.foregroundMessages.listen((_) {
      if (!mounted) return;
      _scheduleNotificationRefresh();
    });
  }

  void _scheduleDmRefresh() {
    _dmRefreshDebounce?.cancel();
    _dmRefreshDebounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _loadUnreadDmCount();
    });
  }

  void _scheduleNotificationRefresh() {
    _notificationRefreshDebounce?.cancel();
    _notificationRefreshDebounce = Timer(const Duration(milliseconds: 220), () {
      if (!mounted) return;
      _loadUnreadNotificationCount();
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

  bool _applyDmUnreadPatch(Map<String, dynamic> payload) {
    final chatId = _readStringField(payload, const ['chatId', 'chat_id']);
    final unread = _readIntField(payload, const ['unreadCount', 'unread_count']);
    if (chatId == null || unread == null) return false;

    final previous = _chatUnreadById[chatId] ?? 0;
    final delta = unread - previous;
    if (!mounted) return true;
    setState(() {
      _chatUnreadById[chatId] = unread;
      final nextTotal = _unreadDmCount + delta;
      _unreadDmCount = nextTotal < 0 ? 0 : nextTotal;
    });
    return true;
  }

  bool _applyNotificationUnreadPatch(Map<String, dynamic> payload) {
    final type = _readStringField(payload, const ['type']);
    if (type == 'new_message') return true;
    final unread = _readIntField(payload, const ['unreadCount', 'unread_count']);
    if (unread == null) return false;
    if (!mounted) return true;
    setState(() {
      _unreadNotificationCount = unread < 0 ? 0 : unread;
    });
    return true;
  }

  final List<MemberVenue> _memberVenues = [];
  String _activeAccount = 'Personal';

  Future<void> _loadUserInitial() async {
    try {
      final me = await AuthRepository().getMe();
      final context = MeContextModel.fromMe(me);
      if (!mounted) return;
      final fullName = (me['fullName'] ?? me['full_name'])?.toString().trim();
      String activeLabel = 'Personal';
      final lastContext = context.lastActiveContext?.toUpperCase();
      // Sadece ACTIVE venue'lar context switching için kullanılır.
      final activeVenues = context.memberVenues.where((v) => v.isActive).toList();
      final hasVenueContext =
          context.hasVenueMembership || activeVenues.isNotEmpty;
      String? resolvedVenueId = context.activeVenueId;
      if (resolvedVenueId == null ||
          resolvedVenueId.isEmpty ||
          !activeVenues.any((venue) => venue.id == resolvedVenueId)) {
        resolvedVenueId = activeVenues.isNotEmpty
            ? activeVenues.first.id
            : null;
      }
      if (lastContext == 'VENUE' && resolvedVenueId != null) {
        for (final venue in activeVenues) {
          if (venue.id == resolvedVenueId) {
            activeLabel = venue.name;
            break;
          }
        }
      } else if (lastContext == 'VENUE' && activeVenues.isNotEmpty) {
        activeLabel = activeVenues.first.name;
      }
      setState(() {
        if (fullName != null && fullName.isNotEmpty) {
          _userInitial = fullName[0].toUpperCase();
        }
        _isVenueContext = lastContext == 'VENUE' && hasVenueContext;
        _hasPersonalProfile = context.hasPersonalProfile;
        _personalAccountLabel = fullName != null && fullName.isNotEmpty
            ? fullName
            : 'Personal';
        _memberVenues
          ..clear()
          ..addAll(context.memberVenues);
        _activeAccount = activeLabel;
        _activeVenueId = resolvedVenueId;
        if (_isVenueContext && _currentIndex > 3) {
          _currentIndex = 0;
        }
      });
    } catch (_) {}
  }

  Future<void> _logout(BuildContext context) async {
    try {
      await AuthRepository().logout();
      if (!context.mounted) return;

      Navigator.of(
        context,
      ).pushNamedAndRemoveUntil(AuthRoutes.login, (route) => false);
    } catch (_) {}
  }

  Future<void> _switchToPersonal() async {
    await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
    if (!mounted) return;
    if (!_hasPersonalProfile) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NameDobOnboardingPage()),
      );
      return;
    }
    Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
  }

  Future<void> _switchToVenue(MemberVenue venue) async {
    await AuthRepository().switchContext(
      lastActiveContext: 'VENUE',
      activeVenueId: venue.id,
    );
    if (!mounted) return;
    setState(() {
      _isVenueContext = true;
      _activeAccount = venue.name;
      _activeVenueId = venue.id;
      _currentIndex = 0;
    });
    _loadUnreadNotificationCount();
  }

  void _onItemTapped(int index) {
    if (!_isVenueContext && index == 2) {
      _dmListKey.currentState?.loadChats();
      _scheduleDmRefresh();
    }
    // Venue context: index 2 = notifications; Personal: index 1 = notifications
    final notifIndex = _isVenueContext ? 2 : 1;
    if (index == notifIndex) {
      _loadUnreadNotificationCount();
    }
    setState(() {
      _currentIndex = index;
    });
  }

  Future<void> _showAccountSwitcher(BuildContext context) async {
    // Her açılışta cache'i temizle ve taze veri çek — onay/red durumu anında yansısın.
    AuthRepository.invalidateMeCache();
    await _loadUserInitial();
    if (!mounted) return;

    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final activeVenues = _memberVenues.where((v) => v.isActive).toList();
    final pendingVenues = _memberVenues.where((v) => v.isPending).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 16, bottom: 8),
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // ── Venue listesi — scroll edilebilir ──
              if (activeVenues.isNotEmpty || pendingVenues.isNotEmpty)
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    children: [
                      // ACTIVE venue'lar
                      ...activeVenues.map(
                        (venue) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                colors.primary.withValues(alpha: 0.12),
                            child:
                                Icon(Icons.storefront, color: colors.primary),
                          ),
                          title: Text(
                            venue.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface,
                            ),
                          ),
                          trailing: _activeAccount == venue.name
                              ? Icon(Icons.check_circle, color: colors.primary)
                              : null,
                          onTap: () async {
                            Navigator.pop(context);
                            final rootContext = this.context;
                            try {
                              await _switchToVenue(venue);
                            } catch (_) {
                              if (!rootContext.mounted) return;
                              await showPremiumErrorDialog(
                                rootContext,
                                message: 'Could not switch to venue account.',
                              );
                            }
                          },
                        ),
                      ),

                      // PENDING venue'lar
                      ...pendingVenues.map(
                        (venue) => ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                colors.onSurface.withValues(alpha: 0.08),
                            child: Icon(
                              Icons.hourglass_top_rounded,
                              color: colors.onSurface.withValues(alpha: 0.45),
                              size: 20,
                            ),
                          ),
                          title: Text(
                            venue.name,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: colors.onSurface.withValues(alpha: 0.55),
                            ),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Pending',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.orange,
                              ),
                            ),
                          ),
                          onTap: () {
                            Navigator.pop(context);
                            Navigator.of(this.context).push(
                              MaterialPageRoute(
                                builder: (_) => const VenuePendingPage(),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),

              // ── Sabit footer ──
              // Add Venue Account
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.add, color: colors.primary, size: 22),
                ),
                title: Text(
                  'Add Venue Account',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push(
                    MaterialPageRoute(
                      builder: (_) => const VenueContextOnboardingPage(
                        fromAppShell: true,
                      ),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              // Account Settings
              ListTile(
                leading: Icon(Icons.settings_outlined, color: colors.onSurface),
                title: Text(
                  'Account Settings',
                  style: TextStyle(color: colors.onSurface),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.of(this.context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccountSettingsPage(),
                    ),
                  );
                },
              ),

              // Personal hesap
              ListTile(
                leading:
                    Icon(Icons.person_outline, color: colors.onSurface),
                title: Text(
                  _isVenueContext
                      ? (_hasPersonalProfile
                            ? 'Switch to $_personalAccountLabel'
                            : 'Create Personal Account')
                      : _personalAccountLabel,
                  style: TextStyle(color: colors.onSurface),
                ),
                trailing: !_isVenueContext
                    ? Icon(Icons.check_circle, color: colors.primary)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  if (!_isVenueContext) return;
                  final rootContext = this.context;
                  try {
                    await _switchToPersonal();
                  } catch (_) {
                    if (!rootContext.mounted) return;
                    await showPremiumErrorDialog(
                      rootContext,
                      message: 'Could not switch to personal account.',
                    );
                  }
                },
              ),

              // Log out
              ListTile(
                leading: Icon(Icons.logout, color: colors.error),
                title: Text(
                  'Log out',
                  style: TextStyle(
                    color: colors.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () async {
                  final rootContext = this.context;
                  Navigator.pop(context);
                  await _logout(rootContext);
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final pages = _isVenueContext
        ? <Widget>[
            VenueAccountHomePage(venueId: _activeVenueId),
            VenueOwnerGuestsPage(venueId: _activeVenueId),
            const NotificationPage(),
            VenueProfilePage(
              activeVenueName:
                  _activeAccount == 'Personal' ? null : _activeAccount,
              venueNames: _memberVenues.map((v) => v.name).toList(),
              venueId: _activeVenueId,
            ),
          ]
        : <Widget>[
            const VenueHomePage(),
            const NotificationPage(),
            DmListPage(key: _dmListKey),
            const PeoplePage(),
            const ProfilePage(),
          ];
    final safeIndex = _currentIndex >= pages.length
        ? pages.length - 1
        : _currentIndex;

    return NotificationUnreadScope(
      unreadCount: _unreadNotificationCount,
      updateUnreadCount: (count) {
        if (_unreadNotificationCount != count) {
          setState(() => _unreadNotificationCount = count);
        }
      },
      child: Scaffold(
        extendBody: true,
        body: pages[safeIndex],
        bottomNavigationBar: _buildNavBar(safeIndex, isDark, theme, context),
      ),
    );
  }

  Widget _buildProfileAvatar({
    required bool isActive,
    required bool isDark,
    required ThemeData theme,
  }) {
    final colors = theme.colorScheme;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isActive ? colors.onSurface : Colors.transparent,
          width: 2.5,
        ),
        color: isDark
            ? colors.primary.withValues(alpha: 0.2)
            : colors.primary.withValues(alpha: 0.12),
      ),
      alignment: Alignment.center,
      child: Text(
        _userInitial,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
          color: isDark ? colors.primary : colors.onSurface,
        ),
      ),
    );
  }

  Widget _buildNotificationIcon(Color color) {
    final icon = Icon(Icons.notifications_none, size: 27, color: color);
    if (_unreadNotificationCount <= 0) {
      return icon;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -4,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(
              color: AppTheme.brandCta,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _unreadNotificationCount > 99
                  ? '99+'
                  : '$_unreadNotificationCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageIcon(Color color) {
    final icon = Icon(Icons.chat_bubble_outline, size: 27, color: color);
    if (_unreadDmCount <= 0) {
      return icon;
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        Positioned(
          right: -4,
          top: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
            decoration: const BoxDecoration(
              color: AppTheme.brandCta,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _unreadDmCount > 99 ? '99+' : '$_unreadDmCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNavBar(
    int safeIndex,
    bool isDark,
    ThemeData theme,
    BuildContext ctx,
  ) {
    final colors = theme.colorScheme;
    final activeColor = colors.onSurface;
    final inactiveColor = colors.onSurface.withValues(alpha: 0.30);

    Widget navIcon(IconData filled, IconData outlined, int index) {
      return Icon(
        safeIndex == index ? filled : outlined,
        size: 28,
        color: safeIndex == index ? activeColor : inactiveColor,
      );
    }

    Widget navItem(int index, Widget child, {VoidCallback? onLongPress}) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onItemTapped(index),
        onLongPress: onLongPress,
        child: SizedBox.expand(
          child: Center(child: child),
        ),
      );
    }

    final List<Widget> items = _isVenueContext
        ? [
            navItem(0, navIcon(Icons.home, Icons.home_outlined, 0)),
            navItem(1, navIcon(Icons.people, Icons.people_outline, 1)),
            navItem(
              2,
              _buildNotificationIcon(
                safeIndex == 2 ? activeColor : inactiveColor,
              ),
            ),
            navItem(
              3,
              _buildProfileAvatar(
                isActive: safeIndex == 3,
                isDark: isDark,
                theme: theme,
              ),
              onLongPress: () => _showAccountSwitcher(ctx),
            ),
          ]
        : [
            navItem(0, navIcon(Icons.home, Icons.home_outlined, 0)),
            navItem(
              1,
              _buildNotificationIcon(
                safeIndex == 1 ? activeColor : inactiveColor,
              ),
            ),
            navItem(
              2,
              _buildMessageIcon(safeIndex == 2 ? activeColor : inactiveColor),
            ),
            navItem(3, navIcon(Icons.people_alt, Icons.people_alt_outlined, 3)),
            navItem(
              4,
              _buildProfileAvatar(
                isActive: safeIndex == 4,
                isDark: isDark,
                theme: theme,
              ),
              onLongPress: () => _showAccountSwitcher(ctx),
            ),
          ];

    return Container(
      decoration: BoxDecoration(
        color: isDark ? colors.surface : Colors.white,
        border: Border(
          top: BorderSide(
            width: 0.5,
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.10),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 52,
          child: Row(
            children: items.map((item) => Expanded(child: item)).toList(),
          ),
        ),
      ),
    );
  }
}
