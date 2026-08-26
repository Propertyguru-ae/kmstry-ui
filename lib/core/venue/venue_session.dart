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
  bool _loading = false;
  bool _loadFailed = false;
  int _loadGeneration = 0;

  String? get venueId => _venueId;
  VenueMemberRole get role => _role;
  bool get loaded => _loaded;
  bool get loading => _loading;
  bool get loadFailed => _loadFailed;
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
    final generation = ++_loadGeneration;
    final venueChanged = _venueId != venueId;
    _venueId = venueId;
    _role = role;
    _loading = true;
    _loadFailed = false;
    if (venueChanged) {
      _loaded = false;
      _permissions = {};
      _plan = VenuePlan.free;
      _planUntil = null;
      _features = {};
    }
    notifyListeners();

    try {
      final access = await _repo.getMyPermissions(venueId);
      if (generation != _loadGeneration || _venueId != venueId) return;
      _permissions = access.permissions.toSet();
      _plan = access.plan;
      _planUntil = access.planUntil;
      _features = access.features;
      _loaded = true;
    } catch (_) {
      if (generation != _loadGeneration || _venueId != venueId) return;
      // A transient API failure is not a FREE plan. Keep a previously loaded
      // snapshot for the same venue; otherwise expose an explicit error state.
      _loadFailed = true;
    }
    if (generation != _loadGeneration || _venueId != venueId) return;
    _loading = false;
    notifyListeners();
  }

  Future<void> retry() async {
    final id = _venueId;
    if (id == null || _loading) return;
    await load(id, _role);
  }

  void clear() {
    _loadGeneration++;
    _venueId = null;
    _role = VenueMemberRole.staff;
    _permissions = {};
    _plan = VenuePlan.free;
    _planUntil = null;
    _features = {};
    _loaded = false;
    _loading = false;
    _loadFailed = false;
    notifyListeners();
  }
}
