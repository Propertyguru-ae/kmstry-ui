import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/user/user_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_home_page.dart';
import 'package:kmstry_frontend/features/home/presentation/personal_home_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/profile_page.dart';
import 'package:kmstry_frontend/features/checkin/services/active_checkin_service.dart';
import 'package:kmstry_frontend/features/checkin/services/quick_checkin_launcher.dart';
import 'package:kmstry_frontend/features/messages/presntation/messages.dart';
import 'package:kmstry_frontend/features/notifications/presentation/notification_unread_scope.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_repository.dart';
import 'package:kmstry_frontend/features/notifications/data/notification_realtime_service.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/push/push_deep_link_handler.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_profile_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_owner_guests_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_manage_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/account_settings_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

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
  String _userInitial = '?';
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
  // Cold start yenileme popup'ı aynı check-in için tek sefer gösterilsin.
  final Set<String> _promptedRenewalCheckinIds = <String>{};

  final GlobalKey<DmListPageState> _dmListKey =
      GlobalKey<
        DmListPageState
      >(); // ignore: library_private_types_in_public_api

  bool _isVenueContext = false;
  bool _hasPersonalProfile = false;
  bool _isPendingClaim = false;
  bool _isRejectedClaim = false;
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
    // Cold-start'ta (uygulama kapalıyken) bildirime basılarak açıldıysa,
    // AuthGate zinciri bitip shell ayağa kalktığı için artık güvenle route edilir.
    PushDeepLinkHandler.instance.consumePendingColdStart();
  }

  void _initCheckinPing() {
    CheckinPingManager.I.configure(
      getLocation: () async {
        // Low accuracy (network/cell-based) konum, sınıra yakın gerçek
        // check-in'lerde 200m'yi yanlışlıkla aşıp check-in'i erken kapatabiliyordu.
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        return (lat: pos.latitude, lng: pos.longitude);
      },
      getCurrentUserId: () async {
        try {
          final me = await AuthRepository().getMe();
          return me['id']?.toString();
        } catch (_) {
          return null;
        }
      },
      onCheckinExpired: () {
        if (!mounted) return;
        // Check-in bitince (uzaklaştı / süre doldu-uzakta) sessiz sıfırlama:
        // snackbar gösterme. Avatar otomatik kullanıcının kalıcı fotosuna dönsün
        // diye stale `me` cache'ini geçersiz kıl ve shell verisini tazele.
        AuthRepository.invalidateMeCache();
        _loadUserInitial();
      },
      onCheckinRenewable: (info) {
        if (!mounted) return;
        // Süre doldu ama kullanıcı hâlâ mekanda → yenileme popup'ı.
        AuthRepository.invalidateMeCache();
        _loadUserInitial();
        _showCheckinRenewalDialog(info);
      },
    );
    CheckinPingManager.I.ensureRunning();
    // Cold start: aktif check-in yoksa, yakın zamanda süre dolan bir check-in
    // varsa ve kullanıcı hâlâ o mekandaysa yenileme popup'ı göster.
    unawaited(_maybePromptColdStartRenewal());
  }

  /// Aktif check-in olmadığında: backend'e "yenilenebilir son check-in" sor;
  /// varsa ve mevcut konum ≤200m ise yenileme dialog'unu göster. Konum yoksa
  /// (izin/GPS) sessizce atlar — açılışta zorla GPS istemez.
  Future<void> _maybePromptColdStartRenewal() async {
    try {
      if (ActiveCheckinService().hasActiveCheckin) return;
      final r = await VenueCheckinRepository().getRenewableCheckin();
      if (r == null || !mounted) return;
      if (_promptedRenewalCheckinIds.contains(r.checkinId)) return;

      final pos = await Geolocator.getLastKnownPosition();
      if (pos == null) return; // Zorla GPS isteme; son bilinen yoksa atla.
      final distance = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        r.venueLatitude,
        r.venueLongitude,
      );
      if (distance > 200 || !mounted) return;

      await _showCheckinRenewalDialog(
        CheckinRenewalInfo(
          checkinId: r.checkinId,
          venueId: r.venueId,
          venueName: r.venueName,
        ),
      );
    } catch (_) {
      // Sessiz geç — açılışı bozma.
    }
  }

  /// Süre dolduğunda kullanıcı hâlâ mekandaysa: "yenile" popup'ı.
  Future<void> _showCheckinRenewalDialog(CheckinRenewalInfo info) async {
    // Ping-tetikli ve cold-start yolları aynı check-in için ikinci kez
    // göstermesin.
    if (_promptedRenewalCheckinIds.contains(info.checkinId)) return;
    _promptedRenewalCheckinIds.add(info.checkinId);

    final venueLabel = (info.venueName ?? '').trim().isNotEmpty
        ? info.venueName!.trim()
        : 'this venue';
    final renew = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: const Text('Check-in süren doldu'),
        content: Text(
          'Hâlâ $venueLabel\'dasın gibi görünüyor. Check-in\'ini 3 saat daha '
          'uzatmak ister misin?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Şimdi değil'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yenile'),
          ),
        ],
      ),
    );
    if (renew != true || !mounted) return;
    await _renewCheckin(info);
  }

  Future<void> _renewCheckin(CheckinRenewalInfo info) async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      final result = await VenueCheckinRepository().renewCheckin(
        checkinId: info.checkinId,
        latitude: pos.latitude,
        longitude: pos.longitude,
      );
      if (!mounted) return;
      final newId = (result['checkinId'] ?? result['id'])?.toString();
      if (newId != null && newId.isNotEmpty) {
        final me = await AuthRepository().getMe();
        ActiveCheckinService().setActiveCheckin(
          newId,
          venueId: info.venueId,
          userId: me['id']?.toString(),
        );
        CheckinPingManager.I.ensureRunning();
        AuthRepository.invalidateMeCache();
        _loadUserInitial();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Check-in\'in yenilendi.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yenilenemedi. Mekana yakın olduğundan emin ol.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
      // Ön plana dönünce presence'i anında "online" yap.
      _chatRealtime.notifyForeground();
      PushManager.instance.reconcileNotificationState();
      _loadUnreadNotificationCount();
      _loadUnreadDmCount();
      CheckinPingManager.I.ensureRunning();
      unawaited(_maybePromptColdStartRenewal());
      // Venue onay/red durumu arka plandan dönerken güncellensin.
      AuthRepository.invalidateMeCache();
      _loadUserInitial();
    } else if (state == AppLifecycleState.paused) {
      // Arka plana alınınca karşı taraf hemen "offline" görsün.
      _chatRealtime.notifyAway();
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
    _notificationStateSub = _notificationRealtime.connectionState.listen((
      state,
    ) {
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
    final unread = _readIntField(payload, const [
      'unreadCount',
      'unread_count',
    ]);
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
    final unread = _readIntField(payload, const [
      'unreadCount',
      'unread_count',
    ]);
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
      // Keep KMSTRY+ entitlement fresh for the CURRENT account (fixes stale
      // premium leaking across account switches).
      UserSession.instance.applyFromMe(me);
      _syncActiveCheckinFromMe(me);
      final context = MeContextModel.fromMe(me);
      if (!mounted) return;
      final fullName = (me['fullName'] ?? me['full_name'])?.toString().trim();
      final username = (me['username'])?.toString().trim();
      String activeLabel = 'Personal';
      final lastContext = context.lastActiveContext?.toUpperCase();
      // Sadece ACTIVE venue'lar context switching için kullanılır.
      final activeVenues = context.memberVenues
          .where((v) => v.isActive)
          .toList();
      final hasPendingClaim = context.memberVenues.any(
        (v) => v.isPendingOwnerClaim,
      );
      final hasRejectedClaim =
          context.hasRejectedClaimOnly ||
          context.memberVenues.any((v) => v.isRejectedOwnerClaim);
      final hasVenueContext =
          context.hasVenueMembership ||
          activeVenues.isNotEmpty ||
          hasPendingClaim ||
          hasRejectedClaim;
      final allKnownVenues = context.memberVenues;
      String? resolvedVenueId = context.activeVenueId;
      if (resolvedVenueId == null ||
          resolvedVenueId.isEmpty ||
          !allKnownVenues.any((venue) => venue.id == resolvedVenueId)) {
        resolvedVenueId = activeVenues.isNotEmpty
            ? activeVenues.first.id
            : hasPendingClaim
            ? context.memberVenues.firstWhere((v) => v.isPendingOwnerClaim).id
            : hasRejectedClaim
            ? context.memberVenues.firstWhere((v) => v.isRejectedOwnerClaim).id
            : null;
      }
      // Rejected claim: last_active_context null'a sıfırlandı ama venue context'te kalmalı.
      final isVenueCtx = hasRejectedClaim
          ? true
          : lastContext == 'VENUE' && hasVenueContext;
      if (isVenueCtx && resolvedVenueId != null) {
        for (final venue in allKnownVenues) {
          if (venue.id == resolvedVenueId) {
            activeLabel = venue.name;
            break;
          }
        }
      } else if (isVenueCtx && allKnownVenues.isNotEmpty) {
        activeLabel = allKnownVenues.first.name;
      }
      final resolvedVenue = resolvedVenueId == null
          ? null
          : allKnownVenues
              .where((venue) => venue.id == resolvedVenueId)
              .firstOrNull;
      final email = me['email']?.toString().trim();
      setState(() {
        if (fullName != null && fullName.isNotEmpty) {
          _userInitial = fullName[0].toUpperCase();
        } else if (username != null && username.isNotEmpty) {
          _userInitial = username[0].toUpperCase();
        } else if (email != null && email.isNotEmpty) {
          _userInitial = email[0].toUpperCase();
        }
        _isVenueContext = isVenueCtx;
        _isPendingClaim = resolvedVenue?.isPendingOwnerClaim ?? false;
        _isRejectedClaim = resolvedVenue?.isRejectedOwnerClaim ?? false;
        _hasPersonalProfile = context.hasPersonalProfile;
        _personalAccountLabel = username != null && username.isNotEmpty
            ? '@$username'
            : (fullName != null && fullName.isNotEmpty ? fullName : 'Personal');
        _memberVenues
          ..clear()
          ..addAll(context.memberVenues);
        _activeAccount = activeLabel;
        _activeVenueId = resolvedVenueId;
        // Venue has fewer tabs than personal; clamp a stale personal index.
        if (_isVenueContext && _currentIndex > 3) {
          _currentIndex = 0;
        }
      });

      // Venue izinlerini context çözülür çözülmez yükle — böylece Manage/Profile'a
      // gidildiğinde gecikme/pop-in olmaz. Kişisel context'te oturumu temizle.
      if (isVenueCtx && resolvedVenueId != null) {
        final match = allKnownVenues.where((v) => v.id == resolvedVenueId);
        final roleStr = match.isNotEmpty ? match.first.role : null;
        final role = VenueMemberRoleExt.fromApi(roleStr ?? 'STAFF');
        if (VenueSession.instance.venueId != resolvedVenueId ||
            !VenueSession.instance.loaded) {
          VenueSession.instance.load(resolvedVenueId, role);
        }
      } else if (!isVenueCtx) {
        VenueSession.instance.clear();
      }
    } catch (_) {}
  }

  void _syncActiveCheckinFromMe(Map<String, dynamic> me) {
    final raw = me['activeCheckin'] ?? me['active_checkin'];
    if (raw is! Map) {
      ActiveCheckinService().clear();
      CheckinPingManager.I.stop();
      return;
    }

    final activeCheckin = Map<String, dynamic>.from(raw);
    final userId = me['id']?.toString();
    final checkinId = activeCheckin['id']?.toString();
    String? venueId = (activeCheckin['venueId'] ?? activeCheckin['venue_id'])
        ?.toString();
    final nestedVenue = activeCheckin['venue'];
    if ((venueId == null || venueId.trim().isEmpty) && nestedVenue is Map) {
      venueId = nestedVenue['id']?.toString();
    }

    ActiveCheckinService().syncForUser(
      userId: userId,
      checkinId: checkinId,
      venueId: venueId,
    );

    if (ActiveCheckinService().hasActiveCheckin) {
      CheckinPingManager.I.ensureRunning();
    } else {
      CheckinPingManager.I.stop();
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      CheckinPingManager.I.stop();
      ActiveCheckinService().clear();
      UserSession.instance.clear();
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

  void _onItemTapped(int index, [VoidCallback? onSelected]) {
    // Tab-specific side effects come from the tab descriptor — no hardcoded
    // indices, so navbar order can change freely without breaking anything.
    onSelected?.call();
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
                            backgroundColor: colors.primary.withValues(
                              alpha: 0.12,
                            ),
                            child: Icon(
                              Icons.storefront,
                              color: colors.primary,
                            ),
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
                            backgroundColor: colors.onSurface.withValues(
                              alpha: 0.08,
                            ),
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
                          onTap: () async {
                            Navigator.pop(context);
                            final rootContext = this.context;
                            try {
                              await _switchToVenue(venue);
                              if (!rootContext.mounted) return;
                              Navigator.of(rootContext).pushNamedAndRemoveUntil(
                                AuthRoutes.authGate,
                                (r) => false,
                              );
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
                      builder: (_) =>
                          const VenueContextOnboardingPage(fromAppShell: true),
                    ),
                  );
                },
              ),

              const Divider(height: 1),

              // Account Settings
              ListTile(
                leading: Icon(Icons.settings_outlined, color: colors.onSurface),
                title: Text(
                  'Accounts Center',
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
                leading: Icon(Icons.person_outline, color: colors.onSurface),
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
    final tabs = _isVenueContext
        ? _venueTabs(isDark, theme)
        : _personalTabs(isDark, theme);
    final safeIndex = _currentIndex >= tabs.length
        ? tabs.length - 1
        : _currentIndex;

    return NotificationUnreadScope(
      unreadCount: _unreadNotificationCount,
      updateUnreadCount: (count) {
        if (_unreadNotificationCount != count) {
          setState(() => _unreadNotificationCount = count);
        }
      },
      child: AppShellNav(
        selectTab: (index) => _onItemTapped(index),
        child: Scaffold(
          extendBody: true,
          body: tabs[safeIndex].page,
          bottomNavigationBar: _buildNavBar(tabs, safeIndex, isDark, theme),
        ),
      ),
    );
  }

  /// Centre navbar check-in button — a filled accent circle so it reads as the
  /// primary action, distinct from the flat destination icons around it.
  Widget _buildCheckinNavButton(ThemeData theme) {
    final colors = theme.colorScheme;
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: colors.primary.withValues(alpha: 0.35),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Icon(Icons.add_location_alt, color: colors.onPrimary, size: 22),
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

  /// Builds a nav-icon closure so an icon's active/inactive rendering stays
  /// coupled to its tab (no index math).
  Widget Function(bool) _navIconBuilder(
    IconData filled,
    IconData outlined,
    ThemeData theme,
  ) {
    final activeColor = theme.colorScheme.onSurface;
    final inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.30);
    return (bool active) => Icon(
      active ? filled : outlined,
      size: 28,
      color: active ? activeColor : inactiveColor,
    );
  }

  /// Personal-context tabs. Order here is the ONLY source of truth — the body,
  /// the navbar and tap side-effects all derive from it, so reordering is safe.
  /// Notifications are intentionally absent: reached via the Home header bell.
  List<_NavTab> _personalTabs(bool isDark, ThemeData theme) {
    final activeColor = theme.colorScheme.onSurface;
    final inactiveColor = theme.colorScheme.onSurface.withValues(alpha: 0.30);
    return [
      _NavTab(
        page: const PersonalHomePage(),
        icon: _navIconBuilder(Icons.home, Icons.home_outlined, theme),
      ),
      _NavTab(
        page: const VenueHomePage(),
        icon: _navIconBuilder(
          Icons.search,
          Icons.search,
          theme,
        ),
      ),
      _NavTab(
        // Centre action: opens the quick check-in flow. Never a destination.
        page: const PersonalHomePage(),
        icon: (_) => _buildCheckinNavButton(theme),
        action: () => QuickCheckinLauncher().launch(context),
      ),
      _NavTab(
        page: DmListPage(key: _dmListKey),
        icon: (active) =>
            _buildMessageIcon(active ? activeColor : inactiveColor),
        onSelected: () {
          _dmListKey.currentState?.loadChats();
          _scheduleDmRefresh();
        },
      ),
      _NavTab(
        page: const ProfilePage(),
        icon: (active) =>
            _buildProfileAvatar(isActive: active, isDark: isDark, theme: theme),
      ),
    ];
  }

  /// Venue-context tabs. Notifications reached via the Dashboard header bell.
  List<_NavTab> _venueTabs(bool isDark, ThemeData theme) {
    return [
      _NavTab(
        page: VenueAccountHomePage(venueId: _activeVenueId),
        icon: _navIconBuilder(Icons.home, Icons.home_outlined, theme),
      ),
      _NavTab(
        page: VenueOwnerGuestsPage(
          venueId: _activeVenueId,
          isPendingClaim: _isPendingClaim,
          isRejectedClaim: _isRejectedClaim,
        ),
        icon: _navIconBuilder(Icons.people, Icons.people_outline, theme),
      ),
      _NavTab(
        page: VenueManagePage(venueId: _activeVenueId),
        icon: _navIconBuilder(Icons.grid_view, Icons.grid_view_outlined, theme),
      ),
      _NavTab(
        page: VenueProfilePage(
          activeVenueName: _activeAccount == 'Personal' ? null : _activeAccount,
          venueNames: _memberVenues.map((v) => v.name).toList(),
          venueId: _activeVenueId,
        ),
        icon: (active) =>
            _buildProfileAvatar(isActive: active, isDark: isDark, theme: theme),
      ),
    ];
  }

  Widget _buildNavBar(
    List<_NavTab> tabs,
    int safeIndex,
    bool isDark,
    ThemeData theme,
  ) {
    final colors = theme.colorScheme;

    final List<Widget> items = [
      for (var i = 0; i < tabs.length; i++)
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final action = tabs[i].action;
            if (action != null) {
              action();
            } else {
              _onItemTapped(i, tabs[i].onSelected);
            }
          },
          child: SizedBox.expand(
            child: Center(child: tabs[i].icon(safeIndex == i)),
          ),
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

/// A single navbar destination: its page, its icon (given active state) and an
/// optional side-effect to run when the tab is selected. Keeping all three
/// together is what removes hardcoded index assumptions from the shell.
/// Lets descendants (e.g. the Home tab's CTAs) switch the shell's active tab
/// without pushing a new route, so the navbar stays visible.
class AppShellNav extends InheritedWidget {
  final void Function(int index) selectTab;

  const AppShellNav({super.key, required this.selectTab, required super.child});

  static AppShellNav? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellNav>();

  @override
  bool updateShouldNotify(AppShellNav oldWidget) => false;
}

class _NavTab {
  final Widget page;
  final Widget Function(bool active) icon;
  final VoidCallback? onSelected;

  /// When set, tapping this item runs the action instead of switching tabs
  /// (e.g. the centre check-in button, which opens the quick check-in flow and
  /// never becomes a selected destination). [page] is only a safe fallback.
  final VoidCallback? action;

  const _NavTab({
    required this.page,
    required this.icon,
    this.onSelected,
    this.action,
  });
}
