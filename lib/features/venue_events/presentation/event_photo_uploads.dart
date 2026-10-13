import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';

/// A local preview is never part of the public event model or shared by venue
/// membership. It belongs to the uploader's session and the exact event/series.
List<PendingPublicMedia> ownerEventPhotos(
  PendingPublicMediaService service,
  String venueId,
  String eventId,
  String? recurringRuleId,
) {
  final venue = VenueSession.instance;
  if (venue.venueId != venueId || !venue.can(VenuePermission.eventManage)) {
    return [];
  }
  return service
      .forKind(PendingPublicMediaKind.eventPhoto, venueId: venueId)
      .where((item) => item.belongsToEvent(venueId, eventId, recurringRuleId))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
}

/// Henüz yayınlanmamış (yükleniyor / incelemede / reddedildi …) yerel
/// event fotoğrafları — galeride yayınlanmışların yanında gösterilir.
List<PendingPublicMedia> ownerUnpublishedEventPhotos(
  PendingPublicMediaService service,
  String venueId,
  String eventId,
  String? recurringRuleId,
) => ownerEventPhotos(
  service,
  venueId,
  eventId,
  recurringRuleId,
).where((item) => item.state != PendingPublicMediaState.published).toList();

/// Yayınlanmamış tek bir event fotoğrafı: renkli önizleme + altta durum
/// etiketi (Sharing / Under review …). Dokununca ayrıntılar açılır.
class EventPendingPhotoTile extends StatelessWidget {
  const EventPendingPhotoTile({
    super.key,
    required this.item,
    this.service,
    this.radius = 14,
    this.onTap,
  });
  final PendingPublicMedia item;
  final PendingPublicMediaService? service;
  final double radius;

  /// Verilirse dokununca bu çalışır (ör. tam ekran galeri); yoksa ayrıntılar.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          onTap ??
          () => showPendingPublicMediaDetails(
            context,
            item,
            service: service ?? PendingPublicMediaService.instance,
          ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PendingPublicMediaPreview(item: item),
            Positioned(
              left: 5,
              right: 5,
              bottom: 5,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: .72),
                  borderRadius: BorderRadius.circular(8),
                ),
                // Küçük kare kutularda taşmasın.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: PublicMediaUploadStatus(item: item, overlay: true),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EventPhotoUploads extends StatelessWidget {
  const EventPhotoUploads({
    super.key,
    required this.venueId,
    required this.eventId,
    this.recurringRuleId,
    this.compact = false,
    this.service,
  });
  final String venueId, eventId;
  final String? recurringRuleId;
  final bool compact;
  final PendingPublicMediaService? service;

  @override
  Widget build(BuildContext context) {
    final uploads = service ?? PendingPublicMediaService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([uploads.changes, VenueSession.instance]),
      builder: (context, _) {
        final items = ownerUnpublishedEventPhotos(
          uploads,
          venueId,
          eventId,
          recurringRuleId,
        );
        if (items.isEmpty) return const SizedBox.shrink();
        if (compact) {
          final attention = items.where((item) => !publicMediaIsSharing(item));
          final selected = attention.isEmpty ? items.first : attention.first;
          return InkWell(
            onTap: () => showPendingPublicMediaDetails(
              context,
              selected,
              service: uploads,
            ),
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: PublicMediaUploadStatus(item: selected),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 140,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) => SizedBox(
                width: 140,
                child: EventPendingPhotoTile(
                  item: items[index],
                  service: uploads,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class EventPhotoUploadCover extends StatelessWidget {
  const EventPhotoUploadCover({
    super.key,
    required this.venueId,
    required this.eventId,
    this.recurringRuleId,
    required this.hasPublishedPhoto,
    required this.child,
    this.service,
  });
  final String venueId, eventId;
  final String? recurringRuleId;
  final bool hasPublishedPhoto;
  final Widget child;
  final PendingPublicMediaService? service;

  @override
  Widget build(BuildContext context) {
    final uploads = service ?? PendingPublicMediaService.instance;
    return ListenableBuilder(
      listenable: Listenable.merge([uploads.changes, VenueSession.instance]),
      builder: (context, _) {
        if (hasPublishedPhoto) return child;
        final candidates =
            ownerEventPhotos(uploads, venueId, eventId, recurringRuleId).where(
              (item) =>
                  item.state != PendingPublicMediaState.rejected &&
                  item.state != PendingPublicMediaState.failed &&
                  item.state != PendingPublicMediaState.cancelled,
            );
        if (candidates.isEmpty) return child;
        return PendingPublicMediaPreview(item: candidates.first);
      },
    );
  }
}
