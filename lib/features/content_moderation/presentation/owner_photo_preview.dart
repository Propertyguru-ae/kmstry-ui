import 'dart:io';
import 'package:flutter/material.dart';
import '../data/pending_public_media.dart';
import 'pending_public_media_preview.dart';

PendingPublicMedia? _latestPhoto(
  PendingPublicMediaService service,
  PendingPublicMediaKind kind,
  String? venueId,
  String? checkinId,
) {
  if (kind != PendingPublicMediaKind.personalAvatar &&
      kind != PendingPublicMediaKind.venueAvatar &&
      kind != PendingPublicMediaKind.checkinAvatar) {
    return null;
  }
  // Never let an unresolved venue context match every venue's pending photo.
  if (kind == PendingPublicMediaKind.venueAvatar &&
      (venueId?.isEmpty ?? true)) {
    return null;
  }
  if (kind == PendingPublicMediaKind.checkinAvatar) {
    if (checkinId == null || checkinId.isEmpty) return null;
    return service
        .forKind(kind)
        .where((item) => item.checkinId == checkinId)
        .firstOrNull;
  }
  final latest = service.latest(kind, venueId: venueId);
  if (kind == PendingPublicMediaKind.personalAvatar &&
      checkinId != null &&
      (latest == null ||
          latest.state == PendingPublicMediaState.rejected ||
          latest.state == PendingPublicMediaState.failed ||
          latest.state == PendingPublicMediaState.cancelled)) {
    return _latestPhoto(
      service,
      PendingPublicMediaKind.checkinAvatar,
      null,
      checkinId,
    );
  }
  return latest;
}

/// Only mount on the signed-in account's own surfaces, never public profiles.
/// Rejection/missing local files reveal the unchanged canonical server photo.
class OwnerPhotoPreview extends StatelessWidget {
  const OwnerPhotoPreview({
    super.key,
    required this.kind,
    required this.child,
    required this.width,
    required this.height,
    this.preserveChildHeight = false,
    this.venueId,
    this.checkinId,
    this.radius = 0,
    this.service,
    this.isActive = true,
  });
  final PendingPublicMediaKind kind;
  final String? venueId;
  final String? checkinId;
  final Widget child;
  final double width, height, radius;

  /// Let a canonical cover include its attribution below the image. A local
  /// candidate still uses [height] and never inherits the old photo's credits.
  final bool preserveChildHeight;
  final PendingPublicMediaService? service;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final uploads = service ?? PendingPublicMediaService.instance;
    Widget preview() {
      final item = _latestPhoto(uploads, kind, venueId, checkinId);
      final path = item?.previewPath ?? item?.localPath;
      final hidden =
          item == null ||
          item.state == PendingPublicMediaState.rejected ||
          item.state == PendingPublicMediaState.failed ||
          item.state == PendingPublicMediaState.cancelled;
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: width,
          height: preserveChildHeight ? null : height,
          child: hidden || path == null || path.isEmpty
              ? child
              : Image.file(
                  File(path),
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  cacheWidth: width > 200 ? 1080 : 540,
                  errorBuilder: (_, _, _) => child,
                ),
        ),
      );
    }

    // Retained hidden profiles need no repaint on every upload-progress tick.
    // Re-activation builds a fresh preview from the same owner-scoped service.
    if (!isActive) return preview();
    return ValueListenableBuilder<int>(
      valueListenable: uploads.changes,
      builder: (context, _, _) => preview(),
    );
  }
}

class OwnerPhotoUploadStatus extends StatelessWidget {
  const OwnerPhotoUploadStatus({
    super.key,
    required this.kind,
    required this.hasPreviousPhoto,
    this.venueId,
    this.onRetry,
    this.overlay = false,
    this.service,
    this.isActive = true,
  });
  final PendingPublicMediaKind kind;
  // Canonical account photo, not the local candidate being checked.
  final bool hasPreviousPhoto;
  final String? venueId;
  final VoidCallback? onRetry;
  final bool overlay;
  final PendingPublicMediaService? service;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    final uploads = service ?? PendingPublicMediaService.instance;
    Widget status() {
      final item = _latestPhoto(uploads, kind, venueId, null);
      if (item == null ||
          item.state == PendingPublicMediaState.published ||
          item.state == PendingPublicMediaState.cancelled) {
        return const SizedBox.shrink();
      }
      final label = PublicMediaUploadStatus(item: item, overlay: overlay);
      final terminal =
          item.state == PendingPublicMediaState.rejected ||
          item.state == PendingPublicMediaState.failed;
      final uncertain =
          item.state == PendingPublicMediaState.connectionIssue &&
          !item.hasServerReceipt;
      final explain =
          terminal ||
          item.state == PendingPublicMediaState.underReview ||
          item.state == PendingPublicMediaState.delayed ||
          item.state == PendingPublicMediaState.connectionIssue;
      if (!explain) return label;

      final color = overlay
          ? Colors.white
          : Theme.of(context).colorScheme.onSurface;
      final generation = uploads.sessionGeneration;
      void dismiss() {
        if (uploads.isCurrentSession(generation)) uploads.dismiss(item.id);
      }

      // Keep exceptional feedback beside the avatar. No legacy uploads sheet,
      // private-media preview or extra popup interrupts a successful update.
      return Container(
        key: overlay ? const ValueKey('owner-photo-status-backdrop') : null,
        constraints: BoxConstraints(
          maxWidth: (MediaQuery.sizeOf(context).width - 48)
              .clamp(0, 300)
              .toDouble(),
        ),
        padding: overlay
            ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
            : null,
        decoration: overlay
            ? BoxDecoration(
                color: Colors.black.withValues(alpha: .6),
                borderRadius: BorderRadius.circular(16),
              )
            : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            label,
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                avatarUploadMessage(item, hasPreviousPhoto: hasPreviousPhoto),
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
            if (terminal || uncertain)
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  if (terminal && onRetry != null)
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: color),
                      onPressed: () {
                        if (!uploads.isCurrentSession(generation)) return;
                        dismiss();
                        onRetry!();
                      },
                      child: const Text('Try again'),
                    ),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: color),
                    onPressed: dismiss,
                    child: const Text('Dismiss'),
                  ),
                ],
              ),
          ],
        ),
      );
    }

    if (!isActive) return status();
    return ValueListenableBuilder<int>(
      valueListenable: uploads.changes,
      builder: (context, _, _) => status(),
    );
  }
}
