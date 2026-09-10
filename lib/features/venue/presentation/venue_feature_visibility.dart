import '../data/venue_member_model.dart';

/// Temporary UI-only visibility. Menu data, routes and stored permissions stay
/// intact; this is not an authorization or backend feature switch.
class VenueFeatureVisibility {
  static bool get menu => false;

  static bool showPermission(VenuePermission permission) =>
      menu || permission != VenuePermission.menuManage;
}
