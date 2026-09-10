import 'dart:async';
import 'package:flutter/foundation.dart';

import '../network/api_exception.dart';
import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/venue/data/venue_checkin_reporsitory.dart';

/// "Hâlâ buradaysan yenile" popup'ı için gereken bilgi.
class CheckinRenewalInfo {
  final String checkinId;
  final String venueId;
  final String? venueName;
  const CheckinRenewalInfo({
    required this.checkinId,
    required this.venueId,
    this.venueName,
  });
}

/// Uygulama açıkken aktif check-in varsa periyodik ping atar.
/// - Tek instance (singleton)
/// - Tek timer (double ping yok)
/// - Sayfadan bağımsız
class CheckinPingManager {
  CheckinPingManager._();
  static final CheckinPingManager I = CheckinPingManager._();

  Timer? _timer;
  bool _running = false;

  final _repo = VenueCheckinRepository();

  /// Dışarıdan konum ver
  Future<({double lat, double lng})> Function()? _getLocation;

  /// Aktif oturumdaki kullanıcıyı verir. Hesap değişiminde eski check-in'in
  /// yeni kullanıcı adına pinglenmesini engeller.
  Future<String?> Function()? _getCurrentUserId;

  /// Check-in bittiğinde (süre doldu ya da mekandan uzaklaşıldı) çağrılır —
  /// UI katmanı state'i sıfırlar. Snackbar göstermez (sessiz).
  VoidCallback? onCheckinExpired;

  /// Süre 3h dolduğunda VE kullanıcı hâlâ mekandaysa (≤200m) çağrılır — UI
  /// "hâlâ buradaysan yenile" popup'ı gösterir.
  void Function(CheckinRenewalInfo info)? onCheckinRenewable;

  String? _lastExpiredNotifiedCheckinId;

  void configure({
    required Future<({double lat, double lng})> Function() getLocation,
    Future<String?> Function()? getCurrentUserId,
    VoidCallback? onCheckinExpired,
    void Function(CheckinRenewalInfo info)? onCheckinRenewable,
  }) {
    _getLocation = getLocation;
    _getCurrentUserId = getCurrentUserId;
    if (onCheckinExpired != null) {
      this.onCheckinExpired = onCheckinExpired;
    }
    if (onCheckinRenewable != null) {
      this.onCheckinRenewable = onCheckinRenewable;
    }
  }

  /// App açıkken çağrılır: aktif check-in varsa başlatır, yoksa durdurur.
  void ensureRunning() {
    unawaited(_ensureRunning());
  }

  Future<void> _ensureRunning() async {
    final checkinId = ActiveCheckinService().activeCheckinId;

    if (checkinId == null) {
      stop();
      return;
    }

    // Zaten çalışıyorsa tekrar başlatma
    if (_running) return;

    final currentUserId = await _getCurrentUserId?.call();
    if (!ActiveCheckinService().belongsToUser(currentUserId)) {
      ActiveCheckinService().clear();
      stop();
      return;
    }

    _running = true;

    // İlk ping'i hemen at (UI geçişlerinde beklemesin)
    _tick(checkinId);

    // Sonra periyodik
    _timer = Timer.periodic(const Duration(seconds: 60), (_) async {
      final currentId = ActiveCheckinService().activeCheckinId;
      if (currentId == null) {
        stop();
        return;
      }
      final currentUserId = await _getCurrentUserId?.call();
      if (!ActiveCheckinService().belongsToUser(currentUserId)) {
        ActiveCheckinService().clear();
        stop();
        return;
      }
      unawaited(_tick(currentId));
    });
  }

  Future<void> _tick(String checkinId) async {
    try {
      final getLoc = _getLocation;
      if (getLoc == null) {
        debugPrint('❌ PingManager: Location provider not configured');
        return;
      }

      final currentUserId = await _getCurrentUserId?.call();
      if (!ActiveCheckinService().belongsToUser(currentUserId)) {
        ActiveCheckinService().clear();
        stop();
        return;
      }

      final loc = await getLoc();

      final res = await _repo.pingCheckin(
        checkinId: checkinId,
        latitude: loc.lat,
        longitude: loc.lng,
      );

      debugPrint('✅ ping status=${res.status} distance=${res.distance}');

      // Check-in bittiyse state temizle, timer durdur ve UI'ı bilgilendir.
      if (res.status != 'active') {
        ActiveCheckinService().clear();
        stop();
        // Süre doldu VE kullanıcı hâlâ mekanda → yenileme popup'ı.
        if (res.status == 'expired' &&
            res.nearVenue &&
            res.venueId != null &&
            _lastExpiredNotifiedCheckinId != checkinId) {
          _lastExpiredNotifiedCheckinId = checkinId;
          onCheckinRenewable?.call(
            CheckinRenewalInfo(
              checkinId: checkinId,
              venueId: res.venueId!,
              venueName: res.venueName,
            ),
          );
        } else {
          // Diğer tüm durumlar (uzaklaştı / süre doldu ama uzakta) → sessiz reset.
          _notifyExpiredOnce(checkinId);
        }
      }
    } catch (e) {
      if (_isInvalidLocalStateError(e)) {
        ActiveCheckinService().clear();
        stop();
        return;
      }
      // Network / GPS hatalarında sessiz devam (app'i bozma)
      debugPrint('❌ ping error: $e');
    }
  }

  bool _isInvalidLocalStateError(Object e) {
    if (e is ApiException) {
      if (e.statusCode == 401 || e.statusCode == 403 || e.statusCode == 404) {
        return true;
      }
      final message = e.toString().toLowerCase();
      return message.contains('not owner') ||
          message.contains('not_owner') ||
          message.contains('not found') ||
          message.contains('not_found') ||
          message.contains('invalid checkin') ||
          message.contains('invalid_checkin');
    }
    final message = e.toString().toLowerCase();
    return message.contains('unauth') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        message.contains('not owner') ||
        message.contains('not_owner') ||
        message.contains('not found') ||
        message.contains('not_found') ||
        message.contains('invalid checkin') ||
        message.contains('invalid_checkin');
  }

  void _notifyExpiredOnce(String checkinId) {
    if (_lastExpiredNotifiedCheckinId == checkinId) return;
    _lastExpiredNotifiedCheckinId = checkinId;
    onCheckinExpired?.call();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
