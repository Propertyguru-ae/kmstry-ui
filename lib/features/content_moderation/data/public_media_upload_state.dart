/// Shared states for owner-only public-media upload feedback. Transfer states
/// are supplied by the uploader; moderation states come from the backend.
enum PendingPublicMediaState {
  preparing,
  uploading,
  checking,
  delayed,
  underReview,
  publishing,
  published,
  rejected,
  connectionIssue,
  failed,
  cancelled,
}

class MediaModerationSnapshot {
  const MediaModerationSnapshot({
    this.status,
    this.message,
    this.processingIssue = false,
    this.photoPublication,
    this.publicationDisabled = false,
  });

  final String? status;
  final String? message;
  final bool processingIssue;
  final String? photoPublication;
  final bool publicationDisabled;
}

/// Approval alone does not establish public visibility. Only a successful
/// publication lookup may return [PendingPublicMediaState.published].
PendingPublicMediaState resolvePublicMediaState({
  required MediaModerationSnapshot moderation,
  required Duration elapsed,
  bool isPublished = false,
  bool connectionIssue = false,
  bool isVideo = false,
}) {
  if (moderation.publicationDisabled) {
    return moderation.status == 'REJECTED'
        ? PendingPublicMediaState.rejected
        : PendingPublicMediaState.failed;
  }
  if (isPublished) return PendingPublicMediaState.published;
  switch (moderation.status) {
    case 'REJECTED':
      return PendingPublicMediaState.rejected;
    case 'ERROR':
      return PendingPublicMediaState.failed;
    case 'NEEDS_REVIEW':
      // Automatic retries have ended. Keep watching for an admin decision,
      // but do not present a terminal processing failure as an endless upload.
      return PendingPublicMediaState.underReview;
  }
  if (connectionIssue) return PendingPublicMediaState.connectionIssue;
  if (moderation.status == 'APPROVED') {
    // Approval must not keep a stalled publication looking nearly complete
    // indefinitely. The public endpoint still determines actual visibility.
    return elapsed >= const Duration(seconds: 30)
        ? PendingPublicMediaState.delayed
        : PendingPublicMediaState.publishing;
  }
  // Video analysis is asynchronous. The recent 50-second gallery clip passed
  // its first attempt in about a minute; the image deadline was a false alarm.
  // This only changes owner feedback, never approval/public visibility.
  final delayAfter = isVideo
      ? const Duration(seconds: 90)
      : const Duration(seconds: 30);
  return elapsed >= delayAfter
      ? PendingPublicMediaState.delayed
      : PendingPublicMediaState.checking;
}

Duration publicMediaPollDelay({
  required bool isVideo,
  required Duration elapsed,
  required PendingPublicMediaState state,
  int activeUploads = 1,
}) {
  // Do not add a 15-second UI polling delay to a normally processing video
  // after just 30 seconds. Only small owner decision endpoints are polled.
  final fastWindow = isVideo
      ? const Duration(seconds: 90)
      : const Duration(seconds: 30);
  final responsive =
      elapsed < fastWindow &&
      state != PendingPublicMediaState.underReview &&
      state != PendingPublicMediaState.connectionIssue;
  final baselineSeconds = responsive ? 2 : 15;
  // Keep the combined status polls near 60/minute, below the backend's 120
  // authenticated read budget, even with a whole gallery batch in flight.
  return Duration(
    seconds: activeUploads > baselineSeconds ? activeUploads : baselineSeconds,
  );
}
