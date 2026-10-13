import 'package:flutter/foundation.dart';

import 'checkin_renewal_info.dart';

/// Foreground-only notice. Never queues an expiry for another account/context.
/// The revision also invalidates a GPS/button action already in flight.
class CheckinExpiryNotice extends ChangeNotifier {
  String? _userId;
  int? _session;
  bool _eligible = false;
  int revision = 0;
  CheckinRenewalInfo? current;
  final Set<String> _seen = {};

  void setContext({
    required String? userId,
    required int session,
    required bool personal,
    required bool foreground,
  }) {
    final eligible = userId != null && personal && foreground;
    if (_userId == userId && _session == session && _eligible == eligible) {
      return;
    }
    if (_userId != userId || _session != session) _seen.clear();
    _userId = userId;
    _session = session;
    _eligible = eligible;
    dismiss();
  }

  void offer(CheckinRenewalInfo info, {required bool hasActiveCheckin}) {
    if (!_seen.add(info.checkinId)) return;
    if (_seen.length > 100) _seen.remove(_seen.first);
    if (!_eligible || hasActiveCheckin || info.userId != _userId) return;
    current = info;
    revision++;
    notifyListeners();
  }

  bool isCurrent(CheckinRenewalInfo info, int attempt) =>
      _eligible && identical(current, info) && revision == attempt;

  void dismiss() {
    current = null;
    revision++;
    notifyListeners();
  }
}
