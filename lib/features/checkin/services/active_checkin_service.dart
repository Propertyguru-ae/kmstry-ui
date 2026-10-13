import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/media/media_reference.dart';

class ActiveCheckinService {
  ActiveCheckinService._();
  static final ActiveCheckinService _instance = ActiveCheckinService._();
  factory ActiveCheckinService() => _instance;

  /// Aktif check-in durumu her değiştiğinde (yeni check-in / temizleme) artar.
  /// AppShell bunu dinleyip navbar avatarını tazeler — böylece avatarı olmayan
  /// bir kullanıcı check-in yapınca geçici (featured) avatar navbar'a da yansır.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static final ValueNotifier<int> avatarChanges = ValueNotifier<int>(0);

  String? _featuredAvatarUrl;
  String? _featuredMediaId;
  MediaReference? _featuredReference;
  String? get featuredMediaId => _featuredMediaId;

  String? _activeCheckinId;
  String? _activeVenueId;
  String? _activeUserId;

  // Only replacing/clearing a check-in or changing a known owner/venue
  // invalidates room/ping requests. Filling missing metadata is not an exit.
  int _identityRevision = 0;
  int get identityRevision => _identityRevision;

  String? get activeCheckinId => _activeCheckinId;
  String? get activeVenueId => _activeVenueId;
  String? get activeUserId => _activeUserId;

  void setActiveCheckin(String checkinId, {String? venueId, String? userId}) {
    String? nonEmpty(String? value) {
      final normalized = value?.trim();
      return normalized == null || normalized.isEmpty ? null : normalized;
    }

    final incomingUserId = nonEmpty(userId);
    final incomingVenueId = nonEmpty(venueId);
    final sameCheckin = _activeCheckinId == checkinId;
    final ownerChanged =
        _activeUserId != null &&
        incomingUserId != null &&
        _activeUserId != incomingUserId;
    final canEnrich = sameCheckin && !ownerChanged;
    // A partial update for the same check-in must not erase known ownership.
    // Never carry missing fields over to a different check-in/account.
    final nextUserId = incomingUserId ?? (canEnrich ? _activeUserId : null);
    final nextVenueId = incomingVenueId ?? (canEnrich ? _activeVenueId : null);
    final identityChanged =
        !sameCheckin ||
        ownerChanged ||
        (_activeVenueId != null && _activeVenueId != nextVenueId);
    final changed =
        !sameCheckin ||
        _activeVenueId != nextVenueId ||
        _activeUserId != nextUserId;
    if (identityChanged) {
      _identityRevision++;
      _featuredAvatarUrl = null;
      _featuredMediaId = null;
      _featuredReference = null;
    }
    _activeCheckinId = checkinId;
    _activeVenueId = nextVenueId;
    _activeUserId = nextUserId;
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
    if (changed) _identityRevision++;
    _activeCheckinId = null;
    _activeVenueId = null;
    _activeUserId = null;
    _featuredAvatarUrl = null;
    _featuredMediaId = null;
    _featuredReference = null;
    if (changed) changes.value++;
  }

  /// Check-in medyası/avatarı yüklendikten sonra dinleyicileri (navbar) tekrar
  /// uyarır — id değişmediği için setActiveCheckin bump etmez; bu koşulsuz eder.
  void notifyMediaUpdated() => changes.value++;

  /// Only call after the server accepts a featured Moment change. The selected
  /// Moment is already published; no new/private media is made public here.
  void featuredPhotoChanged({
    required String checkinId,
    required String mediaId,
    required String url,
    MediaReference? reference,
  }) {
    if (_activeCheckinId != checkinId) return;
    _featuredMediaId = mediaId;
    _featuredAvatarUrl = url;
    _featuredReference = reference;
    avatarChanges.value++;
  }

  String? resolveAvatar({
    required String? checkinId,
    required String? userId,
    required String? avatarUrl,
    required String? featuredUrl,
  }) {
    final selected = _featuredAvatarUrl;
    if (_activeCheckinId == checkinId &&
        belongsToUser(userId) &&
        selected != null &&
        selected.isNotEmpty) {
      // A request started before starring may return the previous crop. Ignore
      // it until the server's featured photo matches this confirmed selection.
      if (Uri.tryParse(featuredUrl ?? '')?.path !=
          Uri.tryParse(selected)?.path) {
        return selected;
      }
    }
    return avatarUrl ?? featuredUrl;
  }

  MediaReference? avatarReference({
    required String? checkinId,
    required String? userId,
    required String? url,
  }) {
    if (_activeCheckinId != checkinId ||
        !belongsToUser(userId) ||
        url == null ||
        _featuredAvatarUrl == null) {
      return null;
    }
    final displayed = Uri.tryParse(url);
    final selected = Uri.tryParse(_featuredAvatarUrl!);
    return displayed?.host == selected?.host &&
            displayed?.path == selected?.path
        ? _featuredReference
        : null;
  }

  bool get hasActiveCheckin => _activeCheckinId != null;

  /// Returns true when the user has an active check-in at [venueId].
  bool isCheckedInAt(String venueId) =>
      _activeCheckinId != null && _activeVenueId == venueId;
}
