import 'dart:async';
import 'package:flutter/foundation.dart';

import '../network/api_exception.dart';
import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/venue/data/venue_checkin_reporsitory.dart';
import '../../features/content_moderation/data/pending_public_media.dart';
import 'checkin_renewal_info.dart';
import '../storage/secure_storage.dart';

export 'checkin_renewal_info.dart';

/// Uygulama açıkken aktif check-in varsa periyodik ping atar.
/// - Tek instance (singleton)
/// - Tek timer (double ping yok)
/// - Sayfadan bağımsız
class CheckinPingManager {
  CheckinPingManager._()
    : _repo = VenueCheckinRepository(),
      _getSessionGeneration = (() =>
          PendingPublicMediaService.instance.sessionGeneration) {
    SecureStorage.sessionEnded.listen((_) => resetSession());
  }
  @visibleForTesting
  CheckinPingManager.forTest({
    required VenueCheckinRepository repository,
    required int Function() getSessionGeneration,
  }) : _repo = repository,
       _getSessionGeneration = getSessionGeneration;
  static final CheckinPingManager I = CheckinPingManager._();

  Timer? _timer;
  bool _running = false;
  String? _runningCheckinId;

  final VenueCheckinRepository _repo;
  final int Function() _getSessionGeneration;
  int _generation = 0;
  Object? _flight;

  /// Dışarıdan konum ver
  Future<({double lat, double lng})> Function()? _getLocation;

  /// Aktif oturumdaki kullanıcıyı verir. Hesap değişiminde eski check-in'in
  /// yeni kullanıcı adına pinglenmesini engeller.
  Future<String?> Function()? _getCurrentUserId;

  /// Check-in bittiğinde (süre doldu ya da mekandan uzaklaşıldı) çağrılır —
  /// UI katmanı state'i sıfırlar. Snackbar göstermez (sessiz).
  VoidCallback? onCheckinExpired;

  /// Live timeout at the venue. UI decides whether the personal-context
  /// notice is eligible; never renews or defers a popup.
  void Function(CheckinRenewalInfo info)? onCheckinTimedOut;

  String? _lastExpiredNotifiedCheckinId;

  void configure({
    required Future<({double lat, double lng})> Function() getLocation,
    Future<String?> Function()? getCurrentUserId,
    VoidCallback? onCheckinExpired,
    void Function(CheckinRenewalInfo info)? onCheckinTimedOut,
  }) {
    stop(); // Invalidate callbacks owned by the previous shell.
    _getLocation = getLocation;
    _getCurrentUserId = getCurrentUserId;
    this.onCheckinExpired = onCheckinExpired;
    this.onCheckinTimedOut = onCheckinTimedOut;
  }

  /// App açıkken çağrılır: aktif check-in varsa başlatır, yoksa durdurur.
  void ensureRunning() {
    final checkinId = ActiveCheckinService().activeCheckinId;

    if (checkinId == null) {
      stop();
      return;
    }

    // Zaten çalışıyorsa tekrar başlatma
    if (_running && _runningCheckinId == checkinId) return;
    stop();

    _running = true;
    _runningCheckinId = checkinId;

    // İlk ping'i hemen at (UI geçişlerinde beklemesin)
    unawaited(_tick(checkinId));

    // Sonra periyodik
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      final currentId = ActiveCheckinService().activeCheckinId;
      if (currentId == null) {
        stop();
        return;
      }
      unawaited(_tick(currentId));
    });
  }

  Future<void> _tick(String checkinId) async {
    if (_flight != null) return;
    final flight = Object();
    _flight = flight;
    final generation = _generation;
    final session = _getSessionGeneration();
    final identity = ActiveCheckinService().identityRevision;
    bool isCurrent() =>
        generation == _generation &&
        session == _getSessionGeneration() &&
        identity == ActiveCheckinService().identityRevision &&
        checkinId == ActiveCheckinService().activeCheckinId;
    try {
      final getLoc = _getLocation;
      if (getLoc == null) {
        debugPrint('❌ PingManager: Location provider not configured');
        return;
      }

      final currentUserId = await _getCurrentUserId?.call();
      if (!isCurrent()) return;
      if (currentUserId == null || currentUserId.trim().isEmpty) return;
      if (!ActiveCheckinService().belongsToUser(currentUserId)) {
        ActiveCheckinService().clear();
        stop();
        return;
      }

      final loc = await getLoc();
      if (!isCurrent()) return;

      final res = await _repo.pingCheckin(
        checkinId: checkinId,
        latitude: loc.lat,
        longitude: loc.lng,
      );
      if (!isCurrent()) return;

      debugPrint('✅ ping status=${res.status} distance=${res.distance}');

      // Check-in bittiyse state temizle, timer durdur ve UI'ı bilgilendir.
      if (res.status != 'active') {
        ActiveCheckinService().clear();
        stop();
        // Foreground expiry notice, not a renewal offer.
        if (res.status == 'expired' &&
            res.nearVenue &&
            res.venueId != null &&
            res.expiresAt != null &&
            _lastExpiredNotifiedCheckinId != checkinId) {
          _lastExpiredNotifiedCheckinId = checkinId;
          onCheckinTimedOut?.call(
            CheckinRenewalInfo(
              checkinId: checkinId,
              venueId: res.venueId!,
              venueName: res.venueName,
              expiresAt: res.expiresAt,
              position:
                  res.renewalLatitude != null && res.renewalLongitude != null
                  ? (lat: res.renewalLatitude!, lng: res.renewalLongitude!)
                  : null,
              userId: currentUserId,
            ),
          );
        } else {
          // Diğer tüm durumlar (uzaklaştı / süre doldu ama uzakta) → sessiz reset.
          _notifyExpiredOnce(checkinId);
        }
      }
    } catch (e) {
      if (!isCurrent()) return;
      if (_isInvalidLocalStateError(e)) {
        ActiveCheckinService().clear();
        stop();
        return;
      }
      // Network / GPS hatalarında sessiz devam (app'i bozma)
      debugPrint('❌ ping error: $e');
    } finally {
      if (identical(_flight, flight)) _flight = null;
    }
  }

  @visibleForTesting
  Future<void> pingNow() async {
    final id = ActiveCheckinService().activeCheckinId;
    if (id != null) await _tick(id);
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
    _generation++;
    _flight = null;
    _timer?.cancel();
    _timer = null;
    _running = false;
    _runningCheckinId = null;
  }

  void resetSession() {
    stop();
    _lastExpiredNotifiedCheckinId = null;
    _getLocation = null;
    _getCurrentUserId = null;
    onCheckinExpired = null;
    onCheckinTimedOut = null;
  }
}
