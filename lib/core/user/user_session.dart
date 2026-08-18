import 'package:flutter/foundation.dart';
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

  bool get isPremium => _isPremium;
  DateTime? get premiumUntil => _premiumUntil;
  bool get loaded => _loaded;

  bool has(PremiumFeature feature) => _isPremium;

  /// Loads once; subsequent calls are no-ops unless [force] is set. Safe to call
  /// from any screen that needs premium state before it renders.
  Future<void> ensureLoaded({bool force = false}) async {
    if (_loaded && !force) return;
    await load(force: force);
  }

  Future<void> load({bool force = false}) async {
    try {
      final me = await _auth.getMe(forceRefresh: force);
      _isPremium = me['isPremium'] == true;
      final until = me['premiumUntil'] ?? me['premium_until'];
      _premiumUntil = until is String ? DateTime.tryParse(until) : null;
    } catch (_) {
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
    _isPremium = me['isPremium'] == true;
    final until = me['premiumUntil'] ?? me['premium_until'];
    _premiumUntil = until is String ? DateTime.tryParse(until) : null;
    _loaded = true;
    notifyListeners();
  }

  /// Optimistic local update after a successful purchase/toggle, so UI reflects
  /// the change without a round-trip. Server remains source of truth on reload.
  void setPremium(bool value, {DateTime? until}) {
    _isPremium = value;
    _premiumUntil = until;
    notifyListeners();
  }

  void clear() {
    _isPremium = false;
    _premiumUntil = null;
    _loaded = false;
    notifyListeners();
  }
}
