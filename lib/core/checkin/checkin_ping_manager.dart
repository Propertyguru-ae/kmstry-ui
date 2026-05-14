import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/venue/data/venue_checkin_reporsitory.dart';

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

  /// Check-in süresi dolduğunda çağrılır — UI katmanı snackbar/dialog gösterir.
  VoidCallback? onCheckinExpired;

  void configure({
    required Future<({double lat, double lng})> Function() getLocation,
    VoidCallback? onCheckinExpired,
  }) {
    _getLocation = getLocation;
    if (onCheckinExpired != null) {
      this.onCheckinExpired = onCheckinExpired;
    }
  }

  /// App açıkken çağrılır: aktif check-in varsa başlatır, yoksa durdurur.
  void ensureRunning() {
    final checkinId = ActiveCheckinService().activeCheckinId;

    if (checkinId == null) {
      stop();
      return;
    }

    // Zaten çalışıyorsa tekrar başlatma
    if (_running) return;

    _running = true;

    // İlk ping'i hemen at (UI geçişlerinde beklemesin)
    _tick(checkinId);

    // Sonra periyodik
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      final currentId = ActiveCheckinService().activeCheckinId;
      if (currentId == null) {
        stop();
        return;
      }
      _tick(currentId);
    });
  }

  Future<void> _tick(String checkinId) async {
    try {
      final getLoc = _getLocation;
      if (getLoc == null) {
        debugPrint('❌ PingManager: Location provider not configured');
        return;
      }

      final loc = await getLoc();

      final res = await _repo.pingCheckin(
        checkinId: checkinId,
        latitude: loc.lat,
        longitude: loc.lng,
      );

      debugPrint('✅ ping status=${res.status} distance=${res.distance}');

      // Check-in bittiyse state temizle, timer durdur ve UI'ı bilgilendir
      if (res.status != 'active') {
        ActiveCheckinService().clear();
        stop();
        onCheckinExpired?.call();
      }
    } catch (e) {
      // Network / GPS hatalarında sessiz devam (app'i bozma)
      debugPrint('❌ ping error: $e');
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _running = false;
  }
}
