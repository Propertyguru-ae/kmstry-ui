class ActiveCheckinService {
  ActiveCheckinService._();
  static final ActiveCheckinService _instance = ActiveCheckinService._();
  factory ActiveCheckinService() => _instance;

  String? _activeCheckinId;
  String? _activeVenueId;

  String? get activeCheckinId => _activeCheckinId;
  String? get activeVenueId => _activeVenueId;

  void setActiveCheckin(String checkinId, {String? venueId}) {
    _activeCheckinId = checkinId;
    _activeVenueId = venueId;
  }

  void clear() {
    _activeCheckinId = null;
    _activeVenueId = null;
  }

  bool get hasActiveCheckin => _activeCheckinId != null;

  /// Returns true when the user has an active check-in at [venueId].
  bool isCheckedInAt(String venueId) =>
      _activeCheckinId != null && _activeVenueId == venueId;
}
