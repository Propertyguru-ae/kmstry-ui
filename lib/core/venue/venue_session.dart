import 'package:flutter/foundation.dart';
import 'package:kmstry_frontend/core/venue/venue_plan.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_repository.dart';

/// Aktif venue context'inde oturum açmış kullanıcının rol ve permission'larını tutar.
/// Venue context açıldığında [load] çağrılır, kapatıldığında [clear] çağrılır.
class VenueSession extends ChangeNotifier {
  static final VenueSession instance = VenueSession._();
  VenueSession._();

  final _repo = VenueMemberRepository();

  String? _venueId;
  VenueMemberRole _role = VenueMemberRole.staff;
  Set<VenuePermission> _permissions = {};
  VenuePlan _plan = VenuePlan.free;
  DateTime? _planUntil;
  Set<VenueFeature> _features = {};
  bool _loaded = false;

  String? get venueId => _venueId;
  VenueMemberRole get role => _role;
  bool get loaded => _loaded;
  bool get isOwner => _role == VenueMemberRole.owner;

  /// Venue'nun abonelik kademesi.
  VenuePlan get plan => _plan;
  DateTime? get planUntil => _planUntil;

  bool can(VenuePermission permission) {
    if (isOwner) return true;
    return _permissions.contains(permission);
  }

  /// Venue planı bu özelliği açıyor mu? (rol izninden bağımsız kademe kontrolü)
  bool hasFeature(VenueFeature feature) => _features.contains(feature);

  Future<void> load(String venueId, VenueMemberRole role) async {
    _venueId = venueId;
    _role = role;
    _loaded = false;
    notifyListeners();

    try {
      final access = await _repo.getMyPermissions(venueId);
      _permissions = access.permissions.toSet();
      _plan = access.plan;
      _planUntil = access.planUntil;
      _features = access.features;
    } catch (_) {
      _permissions = _defaultPermissions(role);
      _plan = VenuePlan.free;
      _planUntil = null;
      _features = {};
    }

    _loaded = true;
    notifyListeners();
  }

  void clear() {
    _venueId = null;
    _role = VenueMemberRole.staff;
    _permissions = {};
    _plan = VenuePlan.free;
    _planUntil = null;
    _features = {};
    _loaded = false;
    notifyListeners();
  }

  Set<VenuePermission> _defaultPermissions(VenueMemberRole role) {
    switch (role) {
      case VenueMemberRole.owner:
        return VenuePermission.values.toSet();
      case VenueMemberRole.admin:
        return {
          VenuePermission.eventManage,
          VenuePermission.eventAttendeesView,
          VenuePermission.storyManage,
          VenuePermission.storyViewStats,
          VenuePermission.postCreate,
          VenuePermission.venueEdit,
          VenuePermission.viewGuests,
          VenuePermission.sendPush,
          VenuePermission.viewStats,
          VenuePermission.viewAnalytics,
          VenuePermission.memberManage,
        };
      case VenueMemberRole.staff:
        return {
          VenuePermission.viewGuests,
          VenuePermission.viewStats,
        };
    }
  }
}
