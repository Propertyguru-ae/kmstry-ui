/// Release policy for new public uploads, identical in every build environment.
/// The backend remains authoritative; enabling it there must not silently expose
/// unfinished video controls in an already released app. Private venue-claim
/// verification and calls do not use this policy.
abstract final class PublicMediaUploadPolicy {
  static const allowVideo = false;
  static const videoUnavailableMessage =
      'Video sharing is currently unavailable. Please choose a photo.';
}
