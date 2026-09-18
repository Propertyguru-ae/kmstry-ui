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
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/push/push_manager.dart';
import 'package:kmstry_frontend/core/push/push_deep_link_handler.dart';
import 'package:kmstry_frontend/core/checkin/checkin_ping_manager.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:geolocator/geolocator.dart';
import 'package:kmstry_frontend/core/location/checkin_location_policy.dart';
import 'package:kmstry_frontend/features/chat/data/chat_list_item_model.dart';
import 'package:kmstry_frontend/features/chat/data/chat_realtime_service.dart';
import 'package:kmstry_frontend/features/chat/data/chat_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_account_home_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_profile_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_owner_guests_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_manage_page.dart';
import 'package:kmstry_frontend/features/profile/presentation/settings_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';

class AppShell extends StatefulWidget {
  final int initialIndex;

  /// When true the shell opens directly in venue mode — no personal-tab flash.
  final bool initialIsVenueContext;

  /// Passed straight through to venue tabs so they don't re-fetch context.
  final String? initialVenueId;

  /// When true the shell opens on the active context's Profile tab instead of
  /// Home — used when the user switches account from the profile screen so they
  /// stay on Profile rather than being dropped on Home.
  final bool openProfileTab;

  const AppShell({
    super.key,
    this.initialIndex = 0,
    this.initialIsVenueContext = false,
    this.initialVenueId,
    this.openProfileTab = false,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _currentIndex = 0;
  bool _openProfilePending = false;
  String _userInitial = '?';
  String? _userAvatarUrl;
  MediaReference? _userAvatarReference;
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
    _openProfilePending = widget.openProfileTab;
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
    // Aktif check-in değişince (yeni check-in / temizleme) navbar avatarını
    // tazele — avatarı olmayan kullanıcının geçici (featured) avatarı yansısın.
    ActiveCheckinService.changes.addListener(_onActiveCheckinChanged);
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
        // check-in'lerde mesafe sınırını yanlışlıkla aşıp check-in'i erken kapatabiliyordu.
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
  /// varsa ve mevcut konum izin verilen mesafedeyse yenileme dialog'unu göster. Konum yoksa
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
      if (distance > CheckinLocationPolicy.maxDistanceMeters || !mounted) {
        return;
      }

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
    final renew = await showCheckinExpiredDialog(
      context,
      venueLabel: venueLabel,
    );
    if (!renew || !mounted) return;
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
          content: Text('Your check-in has been renewed.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Couldn\'t renew. Make sure you\'re near the venue.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _onActiveCheckinChanged() {
    if (!mounted) return;
    // Check-in avatar'ı /auth/me üzerinden gelir → cache'i tazele ve yeniden çek.
    AuthRepository.invalidateMeCache();
    _loadUserInitial();
  }

  @override
  void dispose() {
    ActiveCheckinService.changes.removeListener(_onActiveCheckinChanged);
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
      final avatarUrl = _readUserAvatarUrl(me);
      final profileReference = MediaReference.profilePhoto(me);
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
        _userAvatarUrl = avatarUrl;
        _userAvatarReference = profileReference.url.isEmpty
            ? null
            : profileReference;
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
            (!VenueSession.instance.loaded &&
                !VenueSession.instance.loading &&
                !VenueSession.instance.loadFailed)) {
          VenueSession.instance.load(resolvedVenueId, role);
        }
      } else if (!isVenueCtx) {
        VenueSession.instance.clear();
      }
    } catch (_) {}
  }

  String? _readUserAvatarUrl(Map<String, dynamic> me) {
    for (final key in const [
      'photo',
      'profilePhoto',
      'profile_photo',
      'avatarUrl',
      'avatar_url',
    ]) {
      final value = me[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    // Profil fotosu yoksa: aktif check-in'in geçici avatarını (featured foto'dan
    // kırpılan) kullan — diğer ekranlarda (who's here vb.) gösterilenle tutarlı.
    final active = me['activeCheckin'];
    if (active is Map) {
      for (final key in const [
        'avatarPhoto',
        'avatar_photo',
        'featuredPhoto',
        'featured_photo',
      ]) {
        final value = active[key]?.toString().trim();
        if (value != null && value.isNotEmpty) return value;
      }
    }
    return null;
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

  /// In-place switch to the personal context landing on the Profile tab — the
  /// smooth counterpart of [_switchToVenue] for the profile-screen switcher.
  Future<void> _switchToPersonalProfile() async {
    await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
    if (!mounted) return;
    if (!_hasPersonalProfile) {
      // No personal profile yet → let the gate handle onboarding.
      Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
      return;
    }
    setState(() {
      _isVenueContext = false;
      _activeVenueId = null;
      _activeAccount = 'Personal';
      _currentIndex = 0;
      _openProfilePending = true;
    });
    AuthRepository.invalidateMeCache();
    _loadUserInitial();
    _loadUnreadNotificationCount();
  }

  Future<void> _switchToVenue(
    MemberVenue venue, {
    bool openProfile = false,
  }) async {
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
      // Land on the venue Profile tab when the switch came from the profile
      // screen (consumed in build via the stable tab id).
      _openProfilePending = openProfile;
    });
    // Refresh the new venue's context (session, permissions, member list) so the
    // freshly-keyed venue pages render the right venue, not the previous one.
    AuthRepository.invalidateMeCache();
    _loadUserInitial();
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
      // isScrollControlled: varsayılan ~9/16 ekran sınırını kaldırır — sabit
      // footer + venue listesi o sınırı birkaç px aşıp "bottom overflow"
      // veriyordu. maxHeight ile de aşırı uzamayı engelliyoruz; venue listesi
      // zaten Flexible olduğundan çok hesap varsa içeride scroll olur.
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
            ),
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
                                ? Icon(
                                    Icons.check_circle,
                                    color: colors.primary,
                                  )
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
                                Navigator.of(
                                  rootContext,
                                ).pushNamedAndRemoveUntil(
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
                  leading: Icon(
                    Icons.settings_outlined,
                    color: colors.onSurface,
                  ),
                  title: Text(
                    'Accounts Center',
                    style: TextStyle(color: colors.onSurface),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.of(this.context).push(
                      MaterialPageRoute(builder: (_) => const SettingsPage()),
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
    // One-shot: open the active context's Profile tab (used after an account
    // switch initiated from the profile screen).
    if (_openProfilePending) {
      _openProfilePending = false;
      final profileId = _isVenueContext
          ? kVenueProfileTabId
          : kPersonalProfileTabId;
      final profileIndex = tabs.indexWhere((t) => t.id == profileId);
      if (profileIndex >= 0) _currentIndex = profileIndex;
    }
    final safeIndex = _currentIndex >= tabs.length
        ? tabs.length - 1
        : _currentIndex;
    final isPersonalDiscoverTab = tabs[safeIndex].id == kPersonalDiscoverTabId;

    return NotificationUnreadScope(
      unreadCount: _unreadNotificationCount,
      updateUnreadCount: (count) {
        if (_unreadNotificationCount != count) {
          setState(() => _unreadNotificationCount = count);
        }
      },
      child: AppShellNav(
        selectTab: (index) => _onItemTapped(index),
        selectTabId: (id) {
          final i = tabs.indexWhere((t) => t.id == id);
          if (i >= 0) _onItemTapped(i);
        },
        switchToVenueProfile: (venue) =>
            _switchToVenue(venue, openProfile: true),
        switchToPersonalProfile: _switchToPersonalProfile,
        child: Scaffold(
          extendBody: true,
          // Keep the map viewport fixed while the place-search keyboard is
          // open. Resizing the native map view shifts its camera and briefly
          // exposes the Scaffold background behind the search field.
          resizeToAvoidBottomInset: !isPersonalDiscoverTab,
          body: tabs[safeIndex].page,
          bottomNavigationBar: _buildNavBar(tabs, safeIndex, isDark, theme),
        ),
      ),
    );
  }

  /// Centre navbar check-in action — a flat icon, consistent with the other
  /// destination icons (no filled background).
  Widget _buildCheckinNavButton(ThemeData theme, bool active) {
    // Merkez birincil aksiyon: modal (sheet açılınca navbar kapanır) olduğu için
    // anlık "seçili" durumu gösterilemez; bu yüzden ikon HER ZAMAN pembe→turuncu
    // gradyanla dolu → diğer gri ikonlardan ayrışır, öne çıkar.
    return _NavIconShell(
      active: active,
      child: _navGradientIcon(
        // Seçili olmayan diğer ikonlarla aynı renk (gradyan/dolgu yok).
        Icons.add_location_alt_outlined,
        active: false,
        size: 27,
        theme: theme,
      ),
    );
  }

  Widget _buildProfileAvatar({
    required bool isActive,
    required bool isDark,
    required ThemeData theme,
  }) {
    final colors = theme.colorScheme;

    // Venue context'te profil avatarı aktif venue'nün logosunu/baş harfini
    // gösterir; personal context'te kullanıcının kendi avatarını. Hesaplar
    // arası geçişte avatar da doğru şekilde değişir.
    String? avatarUrl = _userAvatarUrl;
    MediaReference? avatarReference = _userAvatarReference;
    String initial = _userInitial;
    if (_isVenueContext) {
      final activeVenue = _memberVenues
          .where((v) => v.id == _activeVenueId)
          .firstOrNull;
      final venuePhoto = activeVenue?.photoUrl;
      avatarUrl = (venuePhoto != null && venuePhoto.isNotEmpty)
          ? venuePhoto
          : null;
      avatarReference = null;
      final venueName = activeVenue?.name.trim() ?? '';
      initial = venueName.isNotEmpty
          ? venueName[0].toUpperCase()
          : _userInitial;
    }

    return Container(
      width: 36,
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(11),
        // Seçili göstergesi diğer navbar sekmeleriyle AYNI (magenta→orange).
        gradient: isActive
            ? const LinearGradient(
                colors: [AppColors.magentaDark, AppColors.orange],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isActive ? null : colors.primary.withValues(alpha: 0.16),
      ),
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          // Harf dalında seçiliyken iç kutu şeffaf → dış gradient görünür ve
          // beyaz harf net okunur (light modda kaybolma sorunu giderildi).
          // Foto dalında foto zaten örtüyor; seçiliyken 2px gradient çerçeve kalır.
          color: (isActive && avatarUrl == null)
              ? Colors.transparent
              : isDark
              ? const Color(0xFF102238)
              : colors.primary.withValues(alpha: 0.10),
        ),
        alignment: Alignment.center,
        child: avatarUrl != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: CachedImage(
                  avatarUrl,
                  width: 32,
                  height: 32,
                  fit: BoxFit.cover,
                  mediaReference: avatarReference,
                  errorWidget: (context) => _ProfileInitial(
                    initial: initial,
                    isActive: isActive,
                    isDark: isDark,
                    colors: colors,
                  ),
                ),
              )
            : _ProfileInitial(
                initial: initial,
                isActive: isActive,
                isDark: isDark,
                colors: colors,
              ),
      ),
    );
  }

  Widget _buildMessageIcon({required bool active, required ThemeData theme}) {
    // Aktifken diğer sekmeler gibi pembe→turuncu gradyan; rozet kendi renginde.
    final icon = _navGradientIcon(
      Icons.chat_bubble_outline,
      active: active,
      size: 27,
      theme: theme,
    );
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

  Color _navInactiveColor(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return isDark ? const Color(0xFF6F7D96) : const Color(0xFF7A879A);
  }

  /// Builds a nav-icon closure so an icon's active/inactive rendering stays
  /// coupled to its tab (no index math).
  Widget Function(bool) _navIconBuilder(
    IconData filled,
    IconData outlined,
    ThemeData theme,
  ) {
    return (bool active) => _NavIconShell(
      active: active,
      child: _navGradientIcon(
        active ? filled : outlined,
        active: active,
        size: active ? 28 : 27,
        theme: theme,
      ),
    );
  }

  /// Nav icon: pasifken sade renk, aktifken içi pembe→turuncu (dot rengi) dolu.
  Widget _navGradientIcon(
    IconData icon, {
    required bool active,
    required double size,
    required ThemeData theme,
  }) {
    final iconWidget = Icon(
      icon,
      size: size,
      color: active ? Colors.white : _navInactiveColor(theme),
    );
    if (!active) return iconWidget;
    return ShaderMask(
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.magentaDark, AppColors.orange],
      ).createShader(rect),
      child: iconWidget,
    );
  }

  /// Personal-context tabs. Order here is the ONLY source of truth — the body,
  /// the navbar and tap side-effects all derive from it, so reordering is safe.
  /// Notifications are intentionally absent: reached via the Home header bell.
  List<_NavTab> _personalTabs(bool isDark, ThemeData theme) {
    return [
      _NavTab(
        id: kPersonalHomeTabId,
        page: const PersonalHomePage(),
        icon: _navIconBuilder(Icons.home, Icons.home_outlined, theme),
      ),
      _NavTab(
        id: kPersonalDiscoverTabId,
        page: const VenueHomePage(),
        icon: _navIconBuilder(Icons.search, Icons.search, theme),
      ),
      _NavTab(
        // Centre action: opens the quick check-in flow. Never a destination.
        page: const PersonalHomePage(),
        icon: (active) => _buildCheckinNavButton(theme, active),
        action: () => QuickCheckinLauncher().launch(context),
      ),
      _NavTab(
        id: kPersonalMessagesTabId,
        page: DmListPage(key: _dmListKey),
        icon: (active) => _NavIconShell(
          active: active,
          child: _buildMessageIcon(active: active, theme: theme),
        ),
        onSelected: () {
          _dmListKey.currentState?.loadChats();
          _scheduleDmRefresh();
        },
      ),
      _NavTab(
        id: kPersonalProfileTabId,
        page: const ProfilePage(),
        icon: (active) =>
            _buildProfileAvatar(isActive: active, isDark: isDark, theme: theme),
      ),
    ];
  }

  /// Venue-context tabs. Order here is the ONLY source of truth — body, navbar
  /// and any cross-page navigation target tabs by their stable [id], never by
  /// position, so reordering the navbar is safe.
  /// Notifications reached via the Dashboard header bell.
  List<_NavTab> _venueTabs(bool isDark, ThemeData theme) {
    return [
      _NavTab(
        id: kVenueHomeTabId,
        page: VenueAccountHomePage(
          key: ValueKey('venueHome_$_activeVenueId'),
          venueId: _activeVenueId,
        ),
        icon: _navIconBuilder(Icons.home, Icons.home_outlined, theme),
      ),
      _NavTab(
        id: kVenueGuestsTabId,
        page: VenueOwnerGuestsPage(
          key: ValueKey('venueGuests_$_activeVenueId'),
          venueId: _activeVenueId,
          isPendingClaim: _isPendingClaim,
          isRejectedClaim: _isRejectedClaim,
        ),
        icon: _navIconBuilder(Icons.people, Icons.people_outline, theme),
      ),
      _NavTab(
        id: kVenueManageTabId,
        page: VenueManagePage(
          key: ValueKey('venueManage_$_activeVenueId'),
          venueId: _activeVenueId,
        ),
        icon: _navIconBuilder(Icons.grid_view, Icons.grid_view_outlined, theme),
      ),
      _NavTab(
        id: kVenueProfileTabId,
        page: VenueProfilePage(
          key: ValueKey('venueProfile_$_activeVenueId'),
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
        if (tabs[i].action != null)
          // Aksiyon butonu (ör. hızlı check-in): FAB gibi basılınca kısa
          // ölçek animasyonu ile geri bildirim.
          _PressableScale(
            onTap: tabs[i].action!,
            child: SizedBox.expand(
              child: Center(child: tabs[i].icon(safeIndex == i)),
            ),
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _onItemTapped(i, tabs[i].onSelected),
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

class _NavIconShell extends StatelessWidget {
  final bool active;
  final Widget child;

  const _NavIconShell({required this.active, required this.child});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          child,
          Positioned(
            bottom: 4,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: active ? 5 : 0,
              height: active ? 5 : 0,
              // Aktif sayfa göstergesi: logodan ayrışsın diye pembe→turuncu.
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.magentaDark, AppColors.orange],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInitial extends StatelessWidget {
  final String initial;
  final bool isActive;
  final bool isDark;
  final ColorScheme colors;

  const _ProfileInitial({
    required this.initial,
    required this.isActive,
    required this.isDark,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    // Resim dalıyla aynı 32x32 kutu + gerçek ortalama. height:1.0, harfin
    // ascent/descent boşluğundan gelen optik kaymayı engeller (navbar'da baş
    // harf artık tam ortada — profildeki avatarla tutarlı).
    return SizedBox(
      width: 32,
      height: 32,
      child: Center(
        child: Text(
          initial,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
            height: 1.0,
            // Seçiliyken harf gradient kutunun üstünde → her iki temada beyaz.
            color: isActive
                ? Colors.white
                : isDark
                ? AppColors.blueDark
                : colors.onSurface,
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

  /// Sekmeyi index yerine kararlı kimliğiyle seçer (ör. [kVenueGuestsTabId]).
  /// Kimlik bulunamazsa hiçbir şey yapmaz — güvenli.
  final void Function(String id) selectTabId;

  /// Switches the active account to [venue] in place (no navigation) and lands
  /// on the venue's Profile tab — used by the profile-screen account switcher so
  /// the transition stays smooth and keeps the user on Profile.
  final void Function(MemberVenue venue) switchToVenueProfile;

  /// Switches to the personal context in place and lands on the Profile tab.
  final VoidCallback switchToPersonalProfile;

  const AppShellNav({
    super.key,
    required this.selectTab,
    required this.selectTabId,
    required this.switchToVenueProfile,
    required this.switchToPersonalProfile,
    required super.child,
  });

  static AppShellNav? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppShellNav>();

  @override
  bool updateShouldNotify(AppShellNav oldWidget) => false;
}

/// Sekmeleri sıralarından bağımsız, sabit kimlikle hedeflemek için kullanılır
/// (ör. dashboard'daki "See all" → Guests sekmesi). Böylece navbar'daki sıra
/// değişse bile hedef sekme doğru kalır — hiçbir ikonun yeri kodu bağlamaz.
// Venue context
const String kVenueHomeTabId = 'venueHome';
const String kVenueGuestsTabId = 'venueGuests';
const String kVenueManageTabId = 'venueManage';
const String kVenueProfileTabId = 'venueProfile';
// Personal context
const String kPersonalHomeTabId = 'personalHome';
const String kPersonalDiscoverTabId = 'personalDiscover';
const String kPersonalMessagesTabId = 'personalMessages';
const String kPersonalProfileTabId = 'personalProfile';

class _NavTab {
  final Widget page;
  final Widget Function(bool active) icon;
  final VoidCallback? onSelected;

  /// When set, tapping this item runs the action instead of switching tabs
  /// (e.g. the centre check-in button, which opens the quick check-in flow and
  /// never becomes a selected destination). [page] is only a safe fallback.
  final VoidCallback? action;

  /// Sıradan bağımsız kararlı kimlik — [AppShellNav.selectTabId] ile hedeflenir.
  final String? id;

  const _NavTab({
    required this.page,
    required this.icon,
    this.onSelected,
    this.action,
    this.id,
  });
}

/// FAB tarzı basılma geri bildirimi: dokununca kısa süre küçülüp bırakılınca
/// eski boyutuna döner. Nav'daki aksiyon butonları (hızlı check-in) için.
class _PressableScale extends StatefulWidget {
  const _PressableScale({required this.onTap, required this.child});

  final VoidCallback onTap;
  final Widget child;

  @override
  State<_PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<_PressableScale> {
  double _scale = 1.0;

  void _setScale(double value) {
    if (mounted) setState(() => _scale = value);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _setScale(0.84),
      onTapUp: (_) {
        _setScale(1.0);
        widget.onTap();
      },
      onTapCancel: () => _setScale(1.0),
      child: AnimatedScale(
        scale: _scale,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}
