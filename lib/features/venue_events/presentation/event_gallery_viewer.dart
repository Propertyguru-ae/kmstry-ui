import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/stories/presentation/owner_story_upload.dart';

import 'event_photo_uploads.dart';

/// Event galerisinin tam ekran görüntüleyicisi — venue galerisi gibi:
/// kaydırılabilir sayfalar, üstte "1 / 3" sayacı ve kapat. Henüz
/// yayınlanmamış fotoğraflarda (yalnızca yükleyen görür) altta kişisel
/// profildeki gibi durum kartı (Under review / Photo not shared …) çıkar.
class EventGalleryViewer extends StatefulWidget {
  const EventGalleryViewer({
    super.key,
    required this.photos,
    required this.venueId,
    required this.eventId,
    this.recurringRuleId,
    this.initialIndex = 0,
    this.includePendingUploads = true,
    this.service,
  });

  /// Yayınlanmış fotoğraf URL'leri (galeride önce bunlar gelir).
  final List<String> photos;
  final String venueId, eventId;
  final String? recurringRuleId;
  final int initialIndex;

  /// Personal/public event details must show published photos only, even if
  /// the same user has a venue-management session available.
  final bool includePendingUploads;
  final PendingPublicMediaService? service;

  @override
  State<EventGalleryViewer> createState() => _EventGalleryViewerState();
}

class _EventGalleryViewerState extends State<EventGalleryViewer> {
  late final PageController _controller;
  late int _index;

  PendingPublicMediaService get _uploads =>
      widget.service ?? PendingPublicMediaService.instance;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Bekleyen bir fotoğraf kaldırılınca sayfa sayısı azalır; görünen sayfayı
  /// geçerli aralıkta tut, hiç sayfa kalmazsa görüntüleyiciyi kapat.
  void _keepIndexInRange(int count) {
    if (count == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return;
    }
    if (_index < count) return;
    final last = count - 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _index = last);
      if (_controller.hasClients) _controller.jumpToPage(last);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_uploads.changes, VenueSession.instance]),
      builder: (context, _) {
        final pending = widget.includePendingUploads
            ? ownerUnpublishedEventPhotos(
                _uploads,
                widget.venueId,
                widget.eventId,
                widget.recurringRuleId,
              )
            : const <PendingPublicMedia>[];
        final count = widget.photos.length + pending.length;
        _keepIndexInRange(count);
        final index = count == 0 ? 0 : _index.clamp(0, count - 1);
        final current = index >= widget.photos.length && count > 0
            ? pending[index - widget.photos.length]
            : null;

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                itemCount: count,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) {
                  if (i < widget.photos.length) {
                    return InteractiveViewer(
                      minScale: 1,
                      maxScale: 4,
                      child: Center(
                        child: Image.network(
                          widget.photos[i],
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.image_outlined,
                            color: Colors.white38,
                            size: 40,
                          ),
                        ),
                      ),
                    );
                  }
                  final item = pending[i - widget.photos.length];
                  return OwnerStoryUploadMedia(
                    key: ValueKey(item.id),
                    item: item,
                    paused: i != index,
                  );
                },
              ),

              // Üst şerit — venue galerisi ile aynı: karartma, sayaç, kapat.
              const Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: MediaViewerTopScrim(),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 38, 12, 0),
                    child: Row(
                      children: [
                        if (count > 0)
                          MediaViewerCounterPill(index: index, count: count),
                        const Spacer(),
                        MediaViewerCloseButton(
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Yayınlanmamış fotoğraf: durum kartı (+ kaldırma) altta.
              if (current != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black87],
                      ),
                    ),
                    child: _PendingFooter(item: current, service: _uploads),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _PendingFooter extends StatelessWidget {
  const _PendingFooter({required this.item, required this.service});
  final PendingPublicMedia item;
  final PendingPublicMediaService service;

  bool get _canRemove =>
      (item.hasServerReceipt &&
          item.state != PendingPublicMediaState.published) ||
      item.state == PendingPublicMediaState.failed;

  @override
  Widget build(BuildContext context) {
    // Kişisel profildeki moment görüntüleyicisiyle aynı durum kartı; kaldırma
    // butonu kartın içinde, diğer butonlarla aynı stilde.
    return OwnerStoryUploadStatus(
      key: ValueKey(item.id),
      item: item,
      action: _canRemove
          ? EventPhotoRemovalButton(
              key: ValueKey('remove-${item.id}'),
              item: item,
              service: service,
              onDark: true,
            )
          : null,
    );
  }
}
