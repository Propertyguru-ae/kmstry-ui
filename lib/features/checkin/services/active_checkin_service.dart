class ActiveCheckinService {
  ActiveCheckinService._();
  static final ActiveCheckinService _instance = ActiveCheckinService._();
  factory ActiveCheckinService() => _instance;

  String? _activeCheckinId;

  String? get activeCheckinId => _activeCheckinId;

  void setActiveCheckin(String checkinId) {
    _activeCheckinId = checkinId;
  }

  void clear() {
    _activeCheckinId = null;
  }

  bool get hasActiveCheckin => _activeCheckinId != null;
}
