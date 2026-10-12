import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';

bool _usesInlinePublishing(PendingPublicMedia item) =>
    item.isStory ||
    item.isAvatar ||
    item.kind == PendingPublicMediaKind.checkinMoment ||
    item.kind == PendingPublicMediaKind.venueGallery ||
    item.kind == PendingPublicMediaKind.eventPhoto;

bool publicMediaIsSharing(PendingPublicMedia item) => switch (item.state) {
  PendingPublicMediaState.preparing ||
  PendingPublicMediaState.uploading ||
  PendingPublicMediaState.checking ||
  PendingPublicMediaState.publishing => true,
  _ => false,
};

class PendingPublicMediaPreview extends StatelessWidget {
  const PendingPublicMediaPreview({
    super.key,
    required this.item,
    this.fit = BoxFit.cover,
  });

  final PendingPublicMedia item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final rejected =
        item.state == PendingPublicMediaState.rejected ||
        item.state == PendingPublicMediaState.failed;
    final path = item.previewPath ?? (item.isVideo ? null : item.localPath);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (!rejected && path != null)
          Image.file(
            File(path),
            fit: fit,
            // Picker originals may be very large; grid previews must not
            // decode several full-resolution photos at once.
            cacheWidth: fit == BoxFit.contain ? 1080 : 540,
            // Preview file no longer on the device: show a photo placeholder
            // instead of an unexplained empty dark box.
            errorBuilder: (_, _, _) => const Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Color(0xFF253047)),
                Center(
                  child: Icon(
                    Icons.image_outlined,
                    color: Colors.white54,
                    size: 26,
                  ),
                ),
              ],
            ),
          )
        else
          _fallback(),
        if (!_usesInlinePublishing(item) || rejected)
          ColoredBox(
            color: Colors.black.withValues(alpha: rejected ? 0.55 : 0.42),
          ),
        if (!_usesInlinePublishing(item) ||
            rejected ||
            path == null ||
            path.isEmpty)
          Center(
            child: Icon(
              rejected
                  ? Icons.error_outline_rounded
                  : item.isVideo
                  ? Icons.videocam_outlined
                  : Icons.shield_outlined,
              color: Colors.white,
              size: 24,
            ),
          ),
      ],
    );
  }

  Widget _fallback() => const ColoredBox(color: Color(0xFF253047));
}

String pendingPublicMediaLabel(PendingPublicMedia item) => item.isAvatar
    ? switch (item.state) {
        PendingPublicMediaState.preparing ||
        PendingPublicMediaState.uploading ||
        PendingPublicMediaState.checking ||
        PendingPublicMediaState.publishing => 'Updating photo',
        PendingPublicMediaState.published => 'Photo updated',
        PendingPublicMediaState.rejected ||
        PendingPublicMediaState.failed => 'Photo not updated',
        PendingPublicMediaState.delayed => 'Taking longer',
        PendingPublicMediaState.underReview => 'Under review',
        PendingPublicMediaState.connectionIssue => 'Check photo update',
        PendingPublicMediaState.cancelled => 'Update cancelled',
      }
    : switch (item.state) {
        PendingPublicMediaState.preparing =>
          _usesInlinePublishing(item) ? 'Sharing' : 'Preparing…',
        PendingPublicMediaState.uploading =>
          _usesInlinePublishing(item) ? 'Sharing' : 'Uploading…',
        PendingPublicMediaState.checking =>
          _usesInlinePublishing(item) ? 'Sharing' : 'Checking…',
        PendingPublicMediaState.delayed =>
          _usesInlinePublishing(item)
              ? 'Taking longer'
              : 'Taking a little longer',
        PendingPublicMediaState.underReview => 'Under review',
        PendingPublicMediaState.publishing =>
          _usesInlinePublishing(item) ? 'Sharing' : 'Sharing…',
        PendingPublicMediaState.published => 'Shared',
        PendingPublicMediaState.rejected =>
          _usesInlinePublishing(item) ? 'Not shared' : 'Not posted',
        PendingPublicMediaState.connectionIssue =>
          _usesInlinePublishing(item)
              ? 'Check upload'
              : 'Connection interrupted',
        PendingPublicMediaState.failed =>
          _usesInlinePublishing(item) ? 'Not shared' : 'Could not post',
        PendingPublicMediaState.cancelled => 'Cancelled',
      };

Future<void> showPendingPublicMediaDetails(
  BuildContext context,
  PendingPublicMedia item, {
  VoidCallback? onRetake,
  VoidCallback? onViewPublished,
  PendingPublicMediaService? service,
}) async {
  final uploads = service ?? PendingPublicMediaService.instance;
  if (_usesInlinePublishing(item)) {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => PublicMediaUploadDetails(
        item: item,
        onRetake: onRetake,
        onViewPublished: onViewPublished,
        service: uploads,
      ),
    );
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) => ValueListenableBuilder<int>(
      valueListenable: uploads.changes,
      builder: (context, _, _) {
        final current = uploads.byId(item.id);
        if (current == null) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                uploads.wasPublished(item.id)
                    ? 'Your upload is now available.'
                    : 'Upload details are no longer available.',
                style: Theme.of(sheetContext).textTheme.titleMedium,
              ),
            ),
          );
        }
        return _pendingMediaDetails(sheetContext, current, onRetake);
      },
    ),
  );
}

/// Compact owner feedback. Only the normal Sharing phase animates; delayed,
/// review and failure states use a stable label instead of an endless spinner.
class PublicMediaUploadStatus extends StatelessWidget {
  static const labelStyle = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    height: 1.4,
  );
  static const _verticalPadding = 4.0;

  /// Horizontal trays need an explicit height, including scaled text and the
  /// status label's padding. Clipping the label hides useful upload feedback.
  static double preferredHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Sharing',
        style: DefaultTextStyle.of(context).style.merge(labelStyle),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final height =
        (painter.height < 12 ? 12.0 : painter.height) + _verticalPadding * 2;
    painter.dispose();
    return height;
  }

  const PublicMediaUploadStatus({
    super.key,
    required this.item,
    this.onTap,
    this.overlay = false,
  });
  final PendingPublicMedia item;
  final VoidCallback? onTap;
  final bool overlay;

  @override
  Widget build(BuildContext context) {
    final problem =
        item.state == PendingPublicMediaState.rejected ||
        item.state == PendingPublicMediaState.failed ||
        item.state == PendingPublicMediaState.connectionIssue;
    final sharing =
        publicMediaIsSharing(item) &&
        (item.isStory ||
            item.kind == PendingPublicMediaKind.checkinMoment ||
            item.kind == PendingPublicMediaKind.eventPhoto);
    final color = overlay
        ? Colors.white
        : problem
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: .65);
    return Semantics(
      label: '${pendingPublicMediaLabel(item)}. Tap for upload details.',
      button: onTap != null,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 140),
          padding: EdgeInsets.symmetric(
            horizontal: overlay ? 8 : 0,
            vertical: _verticalPadding,
          ),
          decoration: overlay
              ? BoxDecoration(
                  color: Colors.black.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(12),
                )
              : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (sharing) ...[
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: color,
                    semanticsLabel: 'Sharing',
                  ),
                ),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  pendingPublicMediaLabel(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: labelStyle.copyWith(color: color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Keep story call sites compatible while gallery adopts the same components.
typedef StoryUploadStatus = PublicMediaUploadStatus;
typedef StoryUploadDetails = PublicMediaUploadDetails;

class PublicMediaUploadDetails extends StatelessWidget {
  const PublicMediaUploadDetails({
    super.key,
    required this.item,
    this.onRetake,
    this.onViewPublished,
    this.service,
  });
  final PendingPublicMedia item;
  final VoidCallback? onRetake;
  final VoidCallback? onViewPublished;
  final PendingPublicMediaService? service;
  bool get _isGallery => item.kind == PendingPublicMediaKind.venueGallery;
  bool get _isMoment => item.kind == PendingPublicMediaKind.checkinMoment;
  bool get _isEvent => item.kind == PendingPublicMediaKind.eventPhoto;

  @override
  Widget build(BuildContext context) {
    final uploads = service ?? PendingPublicMediaService.instance;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: ValueListenableBuilder<int>(
          valueListenable: uploads.changes,
          builder: (context, _, _) {
            final entries = uploads.forKind(
              item.kind,
              venueId: item.kind != PendingPublicMediaKind.personalStory
                  ? item.venueId
                  : null,
            );
            if (_isMoment) {
              entries.removeWhere((entry) => entry.checkinId != item.checkinId);
            }
            if (_isEvent) {
              entries.removeWhere(
                (entry) =>
                    entry.eventId != item.eventId ||
                    entry.recurringRuleId != item.recurringRuleId,
              );
            }
            // A tile opens its own item first, even within a multi-file batch.
            final selected = uploads.byId(item.id);
            if (selected != null && entries.remove(selected)) {
              entries.insert(0, selected);
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(
                  item.isAvatar
                      ? 'Photo update'
                      : _isMoment
                      ? 'Your Moments'
                      : _isEvent
                      ? 'Event photos'
                      : 'Your uploads',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  item.isAvatar
                      ? 'Photo updates are checked before they are shown to others.'
                      : _isMoment
                      ? 'Only shared Moments are visible to others.'
                      : _isGallery
                      ? 'Only shared gallery items are visible to others.'
                      : _isEvent
                      ? 'Only shared event photos are visible to others.'
                      : 'Only shared stories are visible to others.',
                ),
                const SizedBox(height: 18),
                if (entries.isEmpty)
                  Text(
                    uploads.wasPublished(item.id)
                        ? (item.isAvatar
                              ? 'Your photo is now updated.'
                              : _isMoment
                              ? 'Your Moment is now shared.'
                              : _isGallery
                              ? 'Your gallery item is now shared.'
                              : _isEvent
                              ? 'Your event photo is now shared.'
                              : 'Your story is now shared.')
                        : (item.isAvatar
                              ? 'No pending photo updates.'
                              : _isMoment
                              ? 'No pending Moment uploads.'
                              : _isGallery
                              ? 'No pending gallery uploads.'
                              : _isEvent
                              ? 'No pending event photo uploads.'
                              : 'No pending story uploads.'),
                  ),
                for (final entry in entries) _entry(context, uploads, entry),
                if (onViewPublished != null)
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context);
                      onViewPublished!();
                    },
                    child: Text(
                      _isMoment
                          ? 'View Moments'
                          : _isGallery
                          ? 'View gallery'
                          : _isEvent
                          ? 'View event photos'
                          : 'View shared stories',
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _entry(
    BuildContext context,
    PendingPublicMediaService uploads,
    PendingPublicMedia entry,
  ) {
    final rejected = entry.state == PendingPublicMediaState.rejected;
    final failed = entry.state == PendingPublicMediaState.failed;
    final cancelled = entry.state == PendingPublicMediaState.cancelled;
    final uncertain =
        entry.state == PendingPublicMediaState.connectionIssue &&
        !entry.hasServerReceipt;
    final transferring = entry.state == PendingPublicMediaState.uploading;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!rejected && !failed && !cancelled)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 220,
                width: double.infinity,
                child: PendingPublicMediaPreview(
                  item: entry,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Text(
            pendingPublicMediaLabel(entry),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            entry.isAvatar
                ? avatarUploadMessage(entry)
                : _isMoment
                ? _momentMessage(entry)
                : _isGallery
                ? _galleryMessage(entry)
                : _isEvent
                ? _eventPhotoMessage(entry)
                : _storyMessage(entry),
          ),
          if (transferring && entry.progress != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: entry.progress),
          ],
          if (_isEvent &&
              ((entry.hasServerReceipt &&
                      entry.state != PendingPublicMediaState.published) ||
                  failed))
            EventPhotoRemovalButton(
              key: ValueKey(entry.id),
              item: entry,
              service: uploads,
            )
          else if (rejected || failed || uncertain || cancelled) ...[
            // Uygulama genelindeki standart butonlar (büyük gösterimle aynı).
            const SizedBox(height: 14),
            if (!uncertain && !cancelled && onRetake != null) ...[
              SizedBox(
                width: double.infinity,
                child: PrimaryButton(
                  label: 'Try again',
                  onPressed: () {
                    uploads.dismiss(entry.id);
                    Navigator.pop(context);
                    onRetake!();
                  },
                ),
              ),
              const SizedBox(height: 4),
            ],
            SizedBox(
              width: double.infinity,
              child: PrimaryButton.secondary(
                label: 'Dismiss',
                onPressed: () => uploads.dismiss(entry.id),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _eventPhotoMessage(PendingPublicMedia entry) {
    if (entry.message != null) return entry.message!;
    return switch (entry.state) {
      PendingPublicMediaState.rejected =>
        'This photo did not meet our community content policy and was not shared.',
      PendingPublicMediaState.failed =>
        'This event photo could not be shared. Please choose another photo.',
      PendingPublicMediaState.connectionIssue =>
        'We could not confirm this upload. Refresh your event before uploading it again.',
      PendingPublicMediaState.underReview =>
        'This photo is awaiting review and is not visible to others yet.',
      PendingPublicMediaState.delayed =>
        'This photo is taking a little longer. You can keep using KMSTRY.',
      PendingPublicMediaState.published => 'Your event photo is now shared.',
      PendingPublicMediaState.cancelled =>
        'This event photo is no longer available.',
      _ =>
        'Your event photo is being prepared for sharing. You can keep using KMSTRY.',
    };
  }
}

class EventPhotoRemovalButton extends StatefulWidget {
  const EventPhotoRemovalButton({
    super.key,
    required this.item,
    required this.service,
    this.onDark = false,
  });
  final PendingPublicMedia item;
  final PendingPublicMediaService service;

  /// Koyu medya görüntüleyicisinde (siyah zemin) açık kırmızı kullanılır.
  final bool onDark;

  @override
  State<EventPhotoRemovalButton> createState() =>
      _EventPhotoRemovalButtonState();
}

class _EventPhotoRemovalButtonState extends State<EventPhotoRemovalButton> {
  bool _busy = false;
  String? _error;

  Future<void> _remove() async {
    final generation = widget.service.sessionGeneration;
    final series = widget.item.recurringRuleId != null;
    // Uygulama genelindeki silme onayı tasarımı.
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      icon: Icons.hide_image_outlined,
      title: series ? 'Remove photo from all events?' : 'Remove photo?',
      message: series
          ? 'This photo will be removed from every event in this recurring series. The events and other photos will not be deleted.'
          : 'This photo will be removed and will not be shared. Your event and other photos will not be deleted.',
      confirmLabel: 'Remove photo',
    );
    if (!mounted ||
        !confirmed ||
        !widget.service.isCurrentSession(generation)) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.removeEventPhoto(
        widget.item.id,
        expectedGeneration: generation,
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not remove this photo. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Uygulama genelindeki ikincil buton ölçüleri (52px, 14 radius); yıkıcı
    // eylem olduğu için kırmızı.
    final danger = widget.onDark
        ? const Color(0xFFFF6B6B)
        : Theme.of(context).colorScheme.error;
    final disabled =
        _busy || widget.service.isRemovingEventPhoto(widget.item.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 52,
          child: TextButton.icon(
            onPressed: disabled ? null : _remove,
            style: TextButton.styleFrom(
              foregroundColor: danger,
              disabledForegroundColor: danger.withValues(alpha: 0.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _busy
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: danger,
                    ),
                  )
                : const Icon(Icons.delete_outline_rounded, size: 19),
            label: Text(
              _busy ? 'Removing…' : 'Remove photo',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: danger, fontSize: 12.5),
            ),
          ),
      ],
    );
  }
}

String avatarUploadMessage(
  PendingPublicMedia item, {
  bool hasPreviousPhoto = false,
}) {
  final previousPhoto = hasPreviousPhoto
      ? ' Your previous photo is still in use.'
      : '';
  // Old terminal feedback can survive an app restart in the local upload store.
  // Keep its reason, but do not ask the owner to remove already-rejected media.
  final message = item.message
      ?.replaceAll(
        'Please remove the flagged content or choose a different file.',
        'Please choose a photo.',
      )
      .replaceAll(
        'Please choose a different photo.',
        'Please choose a photo.',
      )
      .replaceAll(
        'Please try uploading again or choose another file.',
        'Please choose a photo.',
      );
  return switch (item.state) {
    PendingPublicMediaState.preparing ||
    PendingPublicMediaState.uploading ||
    PendingPublicMediaState.checking ||
    PendingPublicMediaState.publishing =>
      'Only you can see your new photo for now. You can keep using KMSTRY.',
    PendingPublicMediaState.delayed =>
      'This update is taking longer than usual.$previousPhoto You do not need to upload it again.',
    PendingPublicMediaState.underReview =>
      '${message ?? 'Your new photo needs a review.'}$previousPhoto',
    PendingPublicMediaState.rejected || PendingPublicMediaState.failed =>
      '${message ?? "Your photo wasn’t updated. Please choose a photo."}$previousPhoto',
    PendingPublicMediaState.connectionIssue =>
      'We are reconnecting to check your photo update. Please do not upload it again.',
    PendingPublicMediaState.published => 'Your photo is now updated.',
    PendingPublicMediaState.cancelled =>
      'A newer photo was selected or this photo was removed.',
  };
}

String _momentMessage(PendingPublicMedia item) => switch (item.state) {
  PendingPublicMediaState.preparing ||
  PendingPublicMediaState.uploading ||
  PendingPublicMediaState.checking ||
  PendingPublicMediaState.publishing =>
    'Only you can see this Moment for now. You can keep using KMSTRY.',
  PendingPublicMediaState.delayed =>
    'Sharing is taking longer than usual. This Moment is not visible to others yet. You do not need to upload it again.',
  PendingPublicMediaState.underReview =>
    item.message ??
        'This Moment needs a review before it can be shared. Only you can see it for now.',
  PendingPublicMediaState.rejected =>
    item.message ??
        'This Moment did not meet our content guidelines and was not shared.',
  PendingPublicMediaState.failed =>
    item.message ?? 'This Moment could not be shared. Please try again.',
  PendingPublicMediaState.connectionIssue =>
    'We are reconnecting to check this Moment. Please do not upload it again.',
  PendingPublicMediaState.published => 'Your Moment is now shared.',
  PendingPublicMediaState.cancelled => 'This upload was cancelled.',
};

String _galleryMessage(PendingPublicMedia item) => switch (item.state) {
  PendingPublicMediaState.preparing =>
    'Getting this item ready. Only you can see it for now. You can keep using KMSTRY.',
  PendingPublicMediaState.uploading ||
  PendingPublicMediaState.checking ||
  PendingPublicMediaState.publishing =>
    'Only you can see this for now. You can keep using KMSTRY.',
  PendingPublicMediaState.delayed =>
    'Sharing is taking longer than usual. This item is not visible to others yet. You do not need to upload it again.',
  PendingPublicMediaState.underReview =>
    item.message ??
        'This item needs a review before it can be shared. Only you can see it for now.',
  PendingPublicMediaState.rejected =>
    item.message ??
        'This item did not meet our content guidelines and was not added to your public gallery.',
  PendingPublicMediaState.failed =>
    item.message ??
        'This item could not be added to your gallery. Please choose another file.',
  PendingPublicMediaState.connectionIssue =>
    item.message ??
        'We are reconnecting to check this item. Please do not upload it again.',
  PendingPublicMediaState.published => 'This item is now in your gallery.',
  PendingPublicMediaState.cancelled => 'This upload was cancelled.',
};

String _storyMessage(PendingPublicMedia item) => switch (item.state) {
  PendingPublicMediaState.preparing ||
  PendingPublicMediaState.uploading ||
  PendingPublicMediaState.checking ||
  PendingPublicMediaState.publishing =>
    'Only you can see this for now. You can keep using KMSTRY.',
  PendingPublicMediaState.delayed =>
    'Sharing is taking longer than usual. Your story is not visible to others yet. You do not need to upload it again.',
  PendingPublicMediaState.underReview =>
    item.message ??
        'Your story needs a review before it can be shared. Only you can see it for now.',
  PendingPublicMediaState.rejected =>
    item.message ??
        'This story did not meet our content guidelines and was not shared.',
  PendingPublicMediaState.failed =>
    item.message ?? 'Your story could not be shared. Please try again.',
  PendingPublicMediaState.connectionIssue =>
    item.message ??
        'We are reconnecting to check your story. Please do not upload it again.',
  PendingPublicMediaState.published => 'Your story is now shared.',
  PendingPublicMediaState.cancelled => 'This upload was cancelled.',
};

Widget _pendingMediaDetails(
  BuildContext sheetContext,
  PendingPublicMedia item,
  VoidCallback? onRetake,
) => SafeArea(
  child: Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (item.state != PendingPublicMediaState.rejected &&
            item.state != PendingPublicMediaState.failed) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 190,
              width: double.infinity,
              child: PendingPublicMediaPreview(item: item),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Text(
          pendingPublicMediaLabel(item),
          style: Theme.of(sheetContext).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(switch (item.state) {
          PendingPublicMediaState.preparing =>
            'Your media is being prepared for upload.',
          PendingPublicMediaState.uploading => 'Your media is being uploaded.',
          PendingPublicMediaState.checking =>
            'Your upload is being checked. You can keep using KMSTRY.',
          PendingPublicMediaState.delayed =>
            'Your upload is taking longer to process and is not published yet. You do not need to upload it again.',
          PendingPublicMediaState.underReview =>
            'Your upload needs an additional review. It is visible only to you until approved.',
          PendingPublicMediaState.publishing =>
            'The content check is complete. Your upload is getting ready to appear for others.',
          PendingPublicMediaState.published => 'Your upload is now available.',
          PendingPublicMediaState.rejected =>
            item.message ?? 'This upload did not pass the content check.',
          PendingPublicMediaState.connectionIssue =>
            item.message ??
                'We could not refresh your upload status. We will check again when the connection is available.',
          PendingPublicMediaState.failed =>
            item.message ??
                'The content check could not finish. Your upload was not published. Please try again.',
          PendingPublicMediaState.cancelled => 'This upload was cancelled.',
        }),
        if (item.state == PendingPublicMediaState.rejected ||
            item.state == PendingPublicMediaState.failed ||
            (!item.hasServerReceipt &&
                item.state == PendingPublicMediaState.connectionIssue)) ...[
          const SizedBox(height: 18),
          if (onRetake != null &&
              (item.hasServerReceipt ||
                  item.state == PendingPublicMediaState.failed))
            FilledButton(
              onPressed: () {
                PendingPublicMediaService.instance.dismiss(item.id);
                Navigator.pop(sheetContext);
                onRetake();
              },
              child: const Text('Try again'),
            ),
          TextButton(
            onPressed: () {
              PendingPublicMediaService.instance.dismiss(item.id);
              Navigator.pop(sheetContext);
            },
            child: const Text('Dismiss'),
          ),
        ],
      ],
    ),
  ),
);
