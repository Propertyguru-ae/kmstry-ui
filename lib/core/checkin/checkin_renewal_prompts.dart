import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../features/checkin/services/active_checkin_service.dart';
import '../../features/content_moderation/data/pending_public_media.dart';
import '../storage/secure_storage.dart';
import 'checkin_renewal_info.dart';

export 'checkin_renewal_info.dart';

/// Dormant legacy renewal state. AppShell no longer uses this class;
/// shipping UI uses CheckinExpiryNotice and always starts a NEW check-in.
/// "Check-in süren doldu — yenile?" popup'ının ne zaman gösterileceğini tutar.
///
/// Kişisel check-in hesaba değil kullanıcıya aittir: venue hesabındayken popup
/// gösterilmez, ertelenir ve kullanıcı kişisel hesabına döndüğünde (yenileme
/// penceresi içindeyse) gösterilir. Hesap değişiminde app shell yeniden
/// kurulduğu için durum burada, tek instance'ta tutulur.
class CheckinRenewalPrompts {
  CheckinRenewalPrompts({DateTime Function()? clock, bool watchState = false})
    : _clock = clock ?? DateTime.now {
    if (watchState) {
      _watching = true;
      _session = PendingPublicMediaService.instance.sessionGeneration;
      ActiveCheckinService.changes.addListener(_onActiveChanged);
      PendingPublicMediaService.instance.changes.addListener(_onSessionChanged);
      _sessionEnded = SecureStorage.sessionEnded.listen((_) => reset());
    }
  }

  static final CheckinRenewalPrompts instance = CheckinRenewalPrompts(
    watchState: true,
  );

  /// Backend süresi dolmuş check-in'i 6 saate kadar "yenilenebilir" sayar.
  static const renewalWindow = CheckinRenewalInfo.renewalWindow;

  final DateTime Function() _clock;
  final Set<String> _prompted = <String>{};
  final Set<String> _discarded = {};
  ({CheckinRenewalInfo info, String userId})? _deferred;
  bool _watching = false;
  int _session = 0;
  int _revision = 0;
  int get revision => _revision;
  final changes = ValueNotifier<int>(0);
  String? _observedActiveId;
  StreamSubscription<void>? _sessionEnded;

  bool wasPrompted(String checkinId) =>
      _prompted.contains(checkinId) || _discarded.contains(checkinId);

  /// Popup bu check-in için şimdi gösterilecekse `true` döner ve kaydeder;
  /// aynı check-in için ikinci kez `false` döner.
  bool claim(String checkinId) {
    if (wasPrompted(checkinId)) return false;
    if (_deferred?.info.checkinId == checkinId) _deferred = null;
    return _prompted.add(checkinId);
  }

  /// Venue hesabındayken gelen popup'ı kişisel hesaba dönülene kadar bekletir.
  /// Konum referansı ve gerçek bitiş zamanı [info] ile taşınır.
  void defer(CheckinRenewalInfo info, {required String? userId}) {
    if (userId == null ||
        userId.trim().isEmpty ||
        (info.userId != null && info.userId != userId) ||
        !info.isWithinWindow(_clock()) ||
        wasPrompted(info.checkinId)) {
      return;
    }
    _deferred = (info: info, userId: userId);
  }

  /// Bekleyen popup'ı bir kez verir: başka kullanıcıya aitse, yenileme
  /// penceresi geçtiyse, zaten gösterildiyse ya da kullanıcı süre dolduğundaki
  /// yerden uzaklaştıysa (popup "hâlâ oradasın" der) `null`.
  CheckinRenewalInfo? takeDeferred({
    required String? userId,
    RenewalPosition? position,
  }) {
    final deferred = _deferred;
    if (deferred == null) return null;
    if (deferred.userId != userId ||
        !deferred.info.isWithinWindow(_clock()) ||
        wasPrompted(deferred.info.checkinId)) {
      clearDeferred();
      return null;
    }
    // No fresh GPS: do not claim the user is still at the venue. Retry later.
    if (position == null) return null;
    if (!deferred.info.isNear(position)) {
      clearDeferred();
      return null;
    }
    _deferred = null;
    return deferred.info;
  }

  /// Bekleyen popup'ı düşürür (yeni check-in yapıldı / çıkış yapıldı).
  void clearDeferred() {
    final deferred = _deferred;
    if (deferred != null) _discarded.add(deferred.info.checkinId);
    _deferred = null;
  }

  void reset() {
    _revision++;
    _deferred = null;
    _prompted.clear();
    _discarded.clear();
    _observedActiveId = null;
    changes.value = _revision;
  }

  void _onActiveChanged() {
    final id = ActiveCheckinService().activeCheckinId;
    if (id != null && id != _observedActiveId) {
      _revision++;
      clearDeferred();
      changes.value = _revision;
    }
    _observedActiveId = id;
  }

  void _onSessionChanged() {
    final session = PendingPublicMediaService.instance.sessionGeneration;
    if (session == _session) return;
    _session = session;
    reset();
  }

  void dispose() {
    if (!_watching) return;
    ActiveCheckinService.changes.removeListener(_onActiveChanged);
    PendingPublicMediaService.instance.changes.removeListener(
      _onSessionChanged,
    );
    _sessionEnded?.cancel();
    changes.dispose();
    _watching = false;
  }
}
