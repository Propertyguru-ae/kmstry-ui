import 'package:flutter/foundation.dart';

class ActiveCheckinService {
  ActiveCheckinService._();
  static final ActiveCheckinService _instance = ActiveCheckinService._();
  factory ActiveCheckinService() => _instance;

  /// Aktif check-in durumu her değiştiğinde (yeni check-in / temizleme) artar.
  /// AppShell bunu dinleyip navbar avatarını tazeler — böylece avatarı olmayan
  /// bir kullanıcı check-in yapınca geçici (featured) avatar navbar'a da yansır.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  String? _activeCheckinId;
  String? _activeVenueId;
  String? _activeUserId;

  String? get activeCheckinId => _activeCheckinId;
  String? get activeVenueId => _activeVenueId;
  String? get activeUserId => _activeUserId;

  void setActiveCheckin(String checkinId, {String? venueId, String? userId}) {
    final changed = _activeCheckinId != checkinId || _activeVenueId != venueId;
    _activeCheckinId = checkinId;
    _activeVenueId = venueId;
    _activeUserId = userId;
    // Yalnızca gerçek değişimde bildir → _loadUserInitial → sync döngüsünü önler.
    if (changed) changes.value++;
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
    final changed = _activeCheckinId != null;
    _activeCheckinId = null;
    _activeVenueId = null;
    _activeUserId = null;
    if (changed) changes.value++;
  }

  /// Check-in medyası/avatarı yüklendikten sonra dinleyicileri (navbar) tekrar
  /// uyarır — id değişmediği için setActiveCheckin bump etmez; bu koşulsuz eder.
  void notifyMediaUpdated() => changes.value++;

  bool get hasActiveCheckin => _activeCheckinId != null;

  /// Returns true when the user has an active check-in at [venueId].
  bool isCheckedInAt(String venueId) =>
      _activeCheckinId != null && _activeVenueId == venueId;
}
