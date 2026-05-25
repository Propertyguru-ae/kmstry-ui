import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/chat/data/chat_repository.dart';
import '../../features/messageDetail/presentation/message_detail.dart';
import '../../features/auth/presentation/auth_routes.dart';
import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/venue/data/venue_repository.dart';
import '../../features/venue/presentation/venue_detail_page.dart';
import '../../features/venue/presentation/venue_people_page.dart';

/// FCM bildirimlerine dokunulduğunda (arka plan / kapalı uygulama)
/// ilgili ekrana yönlendiren handler.
///
/// Desteklenen bildirim türleri:
/// - `new_message` → MessageDetailPage (chatId gerekli)
/// - `match_created` → People sayfası
/// - `liked_you` → Notifications sayfası
class PushDeepLinkHandler {
  PushDeepLinkHandler._();
  static final PushDeepLinkHandler instance = PushDeepLinkHandler._();

  final ChatRepository _chatRepo = ChatRepository();
  final VenueRepository _venueRepo = VenueRepository();

  /// [AppShell.initState] içinde çağırılır. NavigatorKey ile ekran
  /// kontrolünü AppShell'e bırakır.
  void init(GlobalKey<NavigatorState> navigatorKey) {
    // 1) Uygulama arka plandayken bildirime dokunuldu
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _route(navigatorKey, message.data);
    });

    // 2) Uygulama tamamen kapalıyken bildirime dokunuldu
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        // Navigasyon ağacı henüz hazır olmayabilir — bir frame bekle
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _route(navigatorKey, message.data);
        });
      }
    });
  }

  /// Public entry-point used by flutter_local_notifications tap callback.
  Future<void> routeFromData(
    GlobalKey<NavigatorState> navigatorKey,
    Map<String, dynamic> data,
  ) =>
      _route(navigatorKey, data);

  Future<void> _route(
    GlobalKey<NavigatorState> navigatorKey,
    Map<String, dynamic> data,
  ) async {
    final type = data['type'] as String?;
    if (type == null) return;

    final nav = navigatorKey.currentState;
    if (nav == null) return;

    switch (type) {
      case 'new_message':
        final chatId = (data['chatId'] ?? data['chat_id']) as String?;
        if (chatId == null || chatId.isEmpty) return;
        await _openChat(nav, chatId);

      case 'match_created':
        nav.pushNamed(AuthRoutes.people);

      case 'liked_you':
        nav.pushNamed(AuthRoutes.notifications);

      case 'venue_claim_approved':
        // Venue context changed on the server — invalidate cache so authGate
        // re-fetches /me and routes the user to their new VENUE_HOME.
        AuthRepository.invalidateMeCache();
        nav.pushNamedAndRemoveUntil(
          AuthRoutes.authGate,
          (route) => false,
        );

      case 'venue_claim_rejected':
        nav.pushNamed(AuthRoutes.notifications);

      case 'test_venue_nearby':
        final venueId = (data['venueId'] ?? data['venue_id']) as String?;
        if (venueId == null || venueId.isEmpty) return;
        await _openTestVenue(nav, venueId);

      default:
        if (kDebugMode) {
          debugPrint('PushDeepLinkHandler: unknown type=$type');
        }
    }
  }

  /// venueId ile venue'yu fetch eder.
  /// Kullanıcının o venue'da aktif check-in'i varsa → VenuePeoplePage
  /// (who's here listesi). Yoksa → VenueDetailPage.
  Future<void> _openTestVenue(NavigatorState nav, String venueId) async {
    try {
      final venue = await _venueRepo.getVenueById(venueId);
      final isCheckedInHere = ActiveCheckinService().isCheckedInAt(venueId);

      if (isCheckedInHere) {
        nav.push(
          MaterialPageRoute(
            builder: (_) => VenuePeoplePage(venue: venue, listVenueId: venueId),
          ),
        );
      } else {
        nav.push(
          MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PushDeepLinkHandler: could not open venue $venueId — $e');
      }
      nav.pushNamed(AuthRoutes.home);
    }
  }

  /// chatId'den chat detayını fetch edip MessageDetailPage'i açar.
  /// Detay gelene kadar kullanıcı beklemez — hemen sayfayı açar, sayfa
  /// kendi yükleme state'ini yönetir.
  Future<void> _openChat(NavigatorState nav, String chatId) async {
    try {
      final chat = await _chatRepo.getChat(chatId, markRead: false, take: 1);
      final other = chat.displayOtherUser;
      nav.push(
        MaterialPageRoute(
          builder: (_) => MessageDetailPage(
            chatId: chatId,
            otherUserId: other?.id ?? '',
            otherName: other?.fullName ?? 'Someone',
            otherPhotoUrl: other?.photo ?? '',
          ),
        ),
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PushDeepLinkHandler: could not open chat $chatId — $e');
      }
      // Fallback: messages listesine git
      nav.pushNamed(AuthRoutes.messages);
    }
  }
}
