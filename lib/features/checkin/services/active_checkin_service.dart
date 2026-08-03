class ActiveCheckinService {
  ActiveCheckinService._();
  static final ActiveCheckinService _instance = ActiveCheckinService._();
  factory ActiveCheckinService() => _instance;

  String? _activeCheckinId;
  String? _activeVenueId;
  String? _activeUserId;

  String? get activeCheckinId => _activeCheckinId;
  String? get activeVenueId => _activeVenueId;
  String? get activeUserId => _activeUserId;

  void setActiveCheckin(String checkinId, {String? venueId, String? userId}) {
    _activeCheckinId = checkinId;
    _activeVenueId = venueId;
    _activeUserId = userId;
  }

  void syncForUser({
    required String? userId,
    required String? checkinId,
    String? venueId,
  }) {
    final normalizedUserId = userId?.trim();
    final normalizedCheckinId = checkinId?.trim();
    if (normalizedUserId == null ||
        normalizedUserId.isEmpty ||
        normalizedCheckinId == null ||
        normalizedCheckinId.isEmpty) {
      clear();
      return;
    }
    setActiveCheckin(
      normalizedCheckinId,
      venueId: venueId,
      userId: normalizedUserId,
    );
  }

  bool belongsToUser(String? userId) {
    final normalizedUserId = userId?.trim();
    if (_activeUserId == null || _activeUserId!.isEmpty) return true;
    return normalizedUserId != null &&
        normalizedUserId.isNotEmpty &&
        _activeUserId == normalizedUserId;
  }

  void clear() {
    _activeCheckinId = null;
    _activeVenueId = null;
    _activeUserId = null;
  }

  bool get hasActiveCheckin => _activeCheckinId != null;

  /// Returns true when the user has an active check-in at [venueId].
  bool isCheckedInAt(String venueId) =>
      _activeCheckinId != null && _activeVenueId == venueId;
}
