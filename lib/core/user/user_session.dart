import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'daily_undo_quota.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

/// Holds the signed-in user's KMSTRY+ entitlement — the user-side mirror of
/// [VenueSession]. Binary today (premium vs free); [has] gates every
/// [PremiumFeature] on the single `isPremium` flag so tiering later is one change.
class UserSession extends ChangeNotifier {
  static final UserSession instance = UserSession._();
  UserSession._();

  final _auth = AuthRepository();

  bool _isPremium = false;
  DateTime? _premiumUntil;
  bool _loaded = false;
  int _generation = 0;

  bool get isPremium => _isPremium;
  DateTime? get premiumUntil => _premiumUntil;
  bool get loaded => _loaded;

  bool has(PremiumFeature feature) => _isPremium;

  DailyUndoQuota? _undoQuota;
  DateTime? _quotaFetchedAt;
  int? _quotaSession;
  int _quotaGeneration = 0;
  bool _fetchingQuota = false;

  DailyUndoQuota? get recentUndoQuota {
    final quota = _undoQuota;
    final now = DateTime.now();
    if (quota == null ||
        _quotaSession != SecureStorage.sessionRevision ||
        !quota.resetsAt.isAfter(now) ||
        now.difference(_quotaFetchedAt!) >= const Duration(minutes: 1)) {
      return null;
    }
    return quota;
  }

  void recordUndoQuota(DailyUndoQuota? value) {
    final current = recentUndoQuota;
    // Concurrent replies can arrive in reverse order. A free allowance only
    // decreases within the same quota window.
    if (current != null &&
        value != null &&
        current.resetsAt.isAtSameMomentAs(value.resetsAt) &&
        current.remaining < value.remaining) {
      value = current;
    }
    _quotaGeneration++;
    _fetchingQuota = false;
    _quotaSession = SecureStorage.sessionRevision;
    _quotaFetchedAt = DateTime.now();
    _undoQuota = value;
  }

  Future<void> warmUndoQuota(Future<DailyUndoQuota?> Function() fetch) async {
    if (_fetchingQuota || recentUndoQuota != null) return;
    final generation = _quotaGeneration;
    final session = SecureStorage.sessionRevision;
    _fetchingQuota = true;
    try {
      final value = await fetch();
      if (generation == _quotaGeneration &&
          session == SecureStorage.sessionRevision) {
        recordUndoQuota(value);
      }
    } catch (_) {
      // Undo still works with the authoritative DELETE if the hint is unavailable.
    } finally {
      if (generation == _quotaGeneration) _fetchingQuota = false;
    }
  }

  /// Loads once; subsequent calls are no-ops unless [force] is set. Safe to call
  /// from any screen that needs premium state before it renders.
  Future<void> ensureLoaded({bool force = false}) async {
    if (_loaded && !force) return;
    await load(force: force);
  }

  Future<void> load({bool force = false}) async {
    final generation = ++_generation;
    try {
      final me = await _auth.getMe(forceRefresh: force);
      if (generation != _generation) return;
      _readEntitlement(me);
    } catch (_) {
      if (generation != _generation) return;
      _isPremium = false;
      _premiumUntil = null;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Sync entitlement straight from a /auth/me payload the caller already has
  /// (e.g. AppShell). Marks the session loaded, so per-account switches reflect
  /// the current user immediately without a stale cached value.
  void applyFromMe(Map<String, dynamic> me) {
    _generation++;
    _readEntitlement(me);
    _loaded = true;
    notifyListeners();
  }

  void _readEntitlement(Map<String, dynamic> me) {
    final premium = me['isPremium'] == true;
    final raw = me['premiumUntil'] ?? me['premium_until'];
    final until = raw is String ? DateTime.tryParse(raw) : null;
    if (premium != _isPremium || until != _premiumUntil) recordUndoQuota(null);
    _isPremium = premium;
    _premiumUntil = until;
  }

  /// Optimistic local update after a successful purchase/toggle, so UI reflects
  /// the change without a round-trip. Server remains source of truth on reload.
  void setPremium(bool value, {DateTime? until}) {
    _generation++;
    recordUndoQuota(null);
    _isPremium = value;
    _premiumUntil = until;
    notifyListeners();
  }

  void clear() {
    recordUndoQuota(null);
    _generation++;
    _isPremium = false;
    _premiumUntil = null;
    _loaded = false;
    notifyListeners();
  }
}
