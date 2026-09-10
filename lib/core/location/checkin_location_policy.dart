/// Shared client-side proximity policy for every GPS check-in entry point.
///
/// The backend remains authoritative and may allow a small, capped GPS
/// accuracy margin when the check-in is submitted.
abstract final class CheckinLocationPolicy {
  static const double maxDistanceMeters = 100;
}
