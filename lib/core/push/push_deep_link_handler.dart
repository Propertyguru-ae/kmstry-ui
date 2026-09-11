import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/auth/data/auth_repository.dart';
import '../../features/messageDetail/presentation/message_detail.dart';
import '../../features/auth/presentation/auth_routes.dart';
import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/venue/data/venue_repository.dart';
import '../../features/venue/presentation/venue_detail_page.dart';
import '../../features/venue/presentation/venue_member_status_page.dart';
import '../../features/venue/presentation/venue_people_page.dart';
import '../../features/venue/presentation/venue_team_page.dart';
import '../../features/venue/presentation/venue_claim_rejected_page.dart';
import '../../core/venue/venue_session.dart';
import '../../features/data_export/presentation/data_export_page.dart';
import '../../features/notifications/presentation/moderation_warning_page.dart';

/// FCM bildirimlerine dokunulduğunda (arka plan / kapalı uygulama)
/// ilgili ekrana yönlendiren handler.
///
/// Desteklenen bildirim türleri:
/// - `new_message` → MessageDetailPage (chatId gerekli)
/// - `match_created` → People sayfası
/// - `liked_you` → Notifications sayfası
/// - `report_update` → Moderation warning details sayfası
class PushDeepLinkHandler {
  PushDeepLinkHandler._();
  static final PushDeepLinkHandler instance = PushDeepLinkHandler._();

  final VenueRepository _venueRepo = VenueRepository();

  GlobalKey<NavigatorState>? _navigatorKey;

  /// Uygulama tamamen kapalıyken bildirime basılıp açıldığında (`getInitialMessage`)
  /// gelen data. Bu anda navigasyon ağacı henüz kurulmadığı ve AuthGate akışı
  /// `pushAndRemoveUntil(... => false)` ile tüm route'ları sildiği için burada
  /// hemen `push` etmek işe yaramaz — açtığımız sohbet sayfası anında silinir.
  /// Bunun yerine data'yı saklarız; AppShell mount olduktan sonra
  /// [consumePendingColdStart] ile güvenle route ederiz.
  Map<String, dynamic>? _pendingColdStart;

  /// [main] içinde çağırılır. NavigatorKey ile ekran kontrolünü paylaşır.
  void init(GlobalKey<NavigatorState> navigatorKey) {
    _navigatorKey = navigatorKey;

    // 1) Uygulama arka plandayken bildirime dokunuldu — navigasyon ağacı
    //    zaten kurulu (AppShell ayakta), doğrudan route edebiliriz.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _route(navigatorKey, message.data);
    });

    // 2) Uygulama tamamen kapalıyken bildirime dokunuldu — hemen route etme,
    //    AuthGate akışı bitip AppShell ayağa kalkınca tüket.
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        _pendingColdStart = message.data;
      }
    });
  }

  /// AppShell mount olduktan sonra çağrılır. Cold-start'ta bekleyen bir bildirim
  /// varsa artık güvenle route eder (AuthGate zinciri tamamlandığı için silinmez).
  void consumePendingColdStart() {
    final data = _pendingColdStart;
    final navigatorKey = _navigatorKey;
    if (data == null || navigatorKey == null) return;
    _pendingColdStart = null;
    // AppShell'in ilk frame'i çizildikten sonra push et.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _route(navigatorKey, data);
    });
  }

  /// Public entry-point used by flutter_local_notifications tap callback.
  Future<void> routeFromData(
    GlobalKey<NavigatorState> navigatorKey,
    Map<String, dynamic> data,
  ) => _route(navigatorKey, data);

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
        final otherUserId = _readString(data, const [
          'senderId',
          'sender_id',
          'otherUserId',
          'other_user_id',
        ]);
        final otherName = _readString(data, const [
          'senderName',
          'sender_name',
          'otherName',
          'other_name',
        ]);
        _openChat(nav, chatId, otherUserId: otherUserId, otherName: otherName);

      case 'match_created':
        nav.pushNamed(AuthRoutes.people);

      case 'liked_you':
        nav.pushNamed(AuthRoutes.notifications);

      case 'report_update':
        nav.push(
          MaterialPageRoute(
            builder: (_) => ModerationWarningPage(
              contentRemoved: _readBool(data, const [
                'contentRemoved',
                'content_removed',
              ]),
            ),
          ),
        );

      case 'data_export_ready':
      case 'data_export_failed':
        nav.push(MaterialPageRoute(builder: (_) => const DataExportPage()));

      case 'venue_claim_approved':
        // Venue context changed on the server — invalidate cache so authGate
        // re-fetches /me and routes the user to their new VENUE_HOME.
        AuthRepository.invalidateMeCache();
        nav.pushNamedAndRemoveUntil(AuthRoutes.authGate, (route) => false);

      case 'venue_claim_rejected':
        final rejectedVenueId = _readString(data, ['venueId', 'venue_id']);
        final rejectedVenueName = _readString(data, [
          'venueName',
          'venue_name',
        ]);
        nav.push(
          MaterialPageRoute(
            builder: (_) => VenueClaimRejectedPage(
              venueId: rejectedVenueId,
              venueName: rejectedVenueName.isNotEmpty
                  ? rejectedVenueName
                  : 'Venue',
            ),
          ),
        );

      case 'venue_member_invite':
        final inviteMemberId = _readString(data, const [
          'memberId',
          'member_id',
        ]);
        final inviteVenueId = _readString(data, const ['venueId', 'venue_id']);
        final inviteRole = _readString(data, const ['role']);
        final inviteVenueName = _readString(data, const [
          'venueName',
          'venue_name',
        ]);
        final inviteInviterName = _readString(data, const [
          'inviterName',
          'inviter_name',
        ]);
        if (inviteMemberId.isNotEmpty && inviteVenueId.isNotEmpty) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => VenueMemberStatusPage(
                venueId: inviteVenueId,
                memberId: inviteMemberId,
                venueName: inviteVenueName.isNotEmpty
                    ? inviteVenueName
                    : 'Venue',
                role: inviteRole.isNotEmpty ? inviteRole : null,
                inviterName: inviteInviterName.isNotEmpty
                    ? inviteInviterName
                    : null,
              ),
            ),
          );
        }

      case 'venue_member_response':
        final responsVenueId = _readString(data, ['venueId', 'venue_id']);
        if (responsVenueId.isNotEmpty) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => VenueTeamPage(
                venueId: responsVenueId,
                callerRole: VenueSession.instance.role,
              ),
            ),
          );
        } else {
          nav.pushNamed(AuthRoutes.notifications);
        }

      case 'venue_member_role_changed':
        final roleChangeVenueId = _readString(data, ['venueId', 'venue_id']);
        if (roleChangeVenueId.isNotEmpty) {
          nav.push(
            MaterialPageRoute(
              builder: (_) => VenueTeamPage(
                venueId: roleChangeVenueId,
                callerRole: VenueSession.instance.role,
              ),
            ),
          );
        } else {
          nav.pushNamed(AuthRoutes.notifications);
        }

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

  String _readString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final v = data[key]?.toString().trim();
      if (v != null && v.isNotEmpty) return v;
    }
    return '';
  }

  bool _readBool(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is bool) return value;
      if (value?.toString().toLowerCase() == 'true') return true;
    }
    return false;
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

  /// chatId ile MessageDetailPage'i hemen açar; ek bir API çağrısı yapmaz.
  /// Sayfa kendi _loadChat() içinde detayı çeker.
  void _openChat(
    NavigatorState nav,
    String chatId, {
    String otherUserId = '',
    String otherName = '',
  }) {
    nav.push(
      MaterialPageRoute(
        builder: (_) => MessageDetailPage(
          chatId: chatId,
          otherUserId: otherUserId,
          otherName: otherName,
          otherPhotoUrl: '',
        ),
      ),
    );
  }
}
