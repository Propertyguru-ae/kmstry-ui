import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/media_viewer_buttons.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:video_player/video_player.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_upload_coordinator.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_picker.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_content_sections.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';
import 'package:kmstry_frontend/features/reports/presentation/report_user_sheet.dart';
import 'package:kmstry_frontend/features/content_moderation/data/pending_public_media.dart';
import 'package:kmstry_frontend/features/content_moderation/presentation/pending_public_media_preview.dart';
import 'package:kmstry_frontend/features/stories/presentation/owner_story_upload.dart';
import 'package:kmstry_frontend/core/venue/visible_venue_read.dart';

const _kMagenta = Color(0xFFE020D8);

/// Venue profilinde gösterilen galeri; yeni seçimler public paylaşım kuralını izler.
/// Kendi verisini yükler; [canEdit] true ise ekleme/silme kısayolları görünür.
class VenueGallerySection extends StatefulWidget {
  final String venueId;
  final bool canEdit;
  final bool isActive;
  final int refreshRevision;
  final VenueGalleryRepository? _repository;
  final PendingPublicMediaService? _uploads;

  const VenueGallerySection({
    super.key,
    required this.venueId,
    required this.canEdit,
    VenueGalleryRepository? repository,
    this.isActive = true,
    this.refreshRevision = 0,
  }) : _repository = repository,
       _uploads = null;

  @visibleForTesting
  const VenueGallerySection.forTest({
    super.key,
    required this.venueId,
    required this.canEdit,
    required VenueGalleryRepository repository,
    required PendingPublicMediaService uploads,
    this.isActive = true,
    this.refreshRevision = 0,
  }) : _repository = repository,
       _uploads = uploads;

  @override
  State<VenueGallerySection> createState() => _VenueGallerySectionState();
}

class _VenueGallerySectionState extends State<VenueGallerySection>
    with WidgetsBindingObserver {
  late final _repo = widget._repository ?? VenueGalleryRepository();
  late final _uploads = widget._uploads ?? PendingPublicMediaService.instance;
  int _loadRequest = 0;
  List<VenueGalleryItem> _items = [];
  bool _loading = true;
  late final _visibleRead = VisibleVenueRead(
    read: _readGallery,
    isVisible: () => mounted && widget.isActive,
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _uploads.changes.addListener(_onPendingChanged);
    VenueGalleryRepository.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    _visibleRead.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _uploads.changes.removeListener(_onPendingChanged);
    VenueGalleryRepository.changes.removeListener(_load);
    super.dispose();
  }

  void _onPendingChanged() {
    if (mounted && widget.isActive) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _visibleRead.activate();
  }

  @override
  void didUpdateWidget(covariant VenueGallerySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.venueId != widget.venueId) {
      _items = [];
      _loading = true;
      _loadRequest++;
      _visibleRead.reset();
      _load();
    } else if (oldWidget.refreshRevision != widget.refreshRevision) {
      _load();
    } else if (widget.isActive && !oldWidget.isActive) {
      _visibleRead.activate();
    }
  }

  Future<void> _load() => _visibleRead.invalidate();

  Future<bool> _readGallery() async {
    final request = ++_loadRequest;
    final venueId = widget.venueId;
    final session = _uploads.sessionGeneration;
    try {
      final items = await _repo.getGallery(venueId);
      if (!mounted ||
          request != _loadRequest ||
          venueId != widget.venueId ||
          !_uploads.isCurrentSession(session)) {
        return false;
      }
      setState(() {
        _items = items;
        _loading = false;
      });
      return true;
    } catch (_) {
      if (mounted &&
          request == _loadRequest &&
          venueId == widget.venueId &&
          _uploads.isCurrentSession(session)) {
        setState(() => _loading = false);
      }
      return false;
    }
  }

  bool _pickingMedia = false;

  Future<void> _addMedia() async {
    if (!widget.canEdit || _pickingMedia) return;
    final venueId = widget.venueId;
    final session = PendingPublicMediaService.instance.sessionGeneration;
    _pickingMedia = true;
    try {
      final files = await pickVenueGalleryMedia();
      if (!mounted ||
          venueId != widget.venueId ||
          !PendingPublicMediaService.instance.isCurrentSession(session)) {
        return;
      }
      if (files.isEmpty) return;
      VenueGalleryUploadCoordinator.instance.share(
        venueId: venueId,
        files: files,
        expectedGeneration: session,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open your photos. Please try again.'),
          ),
        );
      }
    } finally {
      _pickingMedia = false;
    }
  }

  Future<void> _confirmDelete(VenueGalleryItem item) async {
    final ok = await showDestructiveConfirmationDialog(
      context,
      title: 'Remove from gallery',
      message: 'This media will be permanently removed.',
      confirmLabel: 'Remove',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await _repo.deleteItem(widget.venueId, item.id);
      if (mounted) {
        setState(() => _items = _items.where((i) => i.id != item.id).toList());
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove media'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// [index] galerideki birleşik sıradır (sahibine önce bekleyen yüklemeler,
  /// sonra yayınlananlar) — görüntüleyici de aynı sırayı kullanır.
  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GalleryViewer(
          venueId: widget.venueId,
          items: List.of(_items),
          initialIndex: index,
          pendingUploads: widget.canEdit ? _uploads : null,
          onRetake: widget.canEdit ? _addMedia : null,
          onDelete: widget.canEdit
              ? (item) async {
                  await _repo.deleteItem(widget.venueId, item.id);
                  if (mounted) {
                    setState(
                      () => _items = _items
                          .where((i) => i.id != item.id)
                          .toList(),
                    );
                  }
                }
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final kText = colors.onSurface;
    final kDim = kText.withValues(alpha: 0.55);
    final pending = widget.canEdit
        ? _uploads.forKind(
            PendingPublicMediaKind.venueGallery,
            venueId: widget.venueId,
          )
        : <PendingPublicMedia>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              venueSectionTitle(context, AppColors.teal, 'Gallery'),
              if (_items.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kMagenta.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${_items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: _kMagenta,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              if (widget.canEdit)
                GestureDetector(
                  onTap: _addMedia,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _kMagenta.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 15, color: _kMagenta),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: _kMagenta,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),

        if (_loading && pending.isEmpty && _items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_kMagenta),
              ),
            ),
          )
        else if (_items.isEmpty && pending.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 30),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colors.outlineVariant.withValues(alpha: 0.4),
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 34,
                    color: kDim.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'No gallery yet',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.canEdit
                        ? 'Add photos of your venue'
                        : 'This venue has no gallery yet',
                    style: TextStyle(fontSize: 12, color: kDim),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const cols = 3;
                const gap = 6.0;
                // Kare tile boyu (genişlikten) → 3 satırlık sabit yükseklik
                final tile = (constraints.maxWidth - gap * (cols - 1)) / cols;
                final maxHeight = tile * 3 + gap * 2; // 9 öğe (3 satır)
                final total = pending.length + _items.length;
                final scrolls = total > 9;

                final grid = GridView.builder(
                  shrinkWrap: !scrolls,
                  physics: scrolls
                      ? const ClampingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                  ),
                  itemCount: total,
                  itemBuilder: (_, i) {
                    if (i < pending.length) {
                      final item = pending[i];
                      // Popup yerine büyük gösterim (event galerisi gibi).
                      return GestureDetector(
                        onTap: () => _openViewer(i),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              PendingPublicMediaPreview(item: item),
                              Align(
                                alignment: Alignment.bottomCenter,
                                child: PublicMediaUploadStatus(
                                  item: item,
                                  overlay: true,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final item = _items[i - pending.length];
                    return GestureDetector(
                      onTap: () => _openViewer(i),
                      onLongPress: widget.canEdit
                          ? () => _confirmDelete(item)
                          : null,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: GalleryTile(item: item),
                      ),
                    );
                  },
                );

                return scrolls
                    ? SizedBox(
                        height: maxHeight,
                        child: Scrollbar(child: grid),
                      )
                    : grid;
              },
            ),
          ),
      ],
    );
  }
}

class GalleryTile extends StatelessWidget {
  final VenueGalleryItem item;
  const GalleryTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = Container(color: colors.surfaceContainerHighest);
    if (item.isVideo) {
      // Video: thumbnail varsa göster, yoksa koyu tile — üstte play ikonu
      return Stack(
        fit: StackFit.expand,
        children: [
          if (item.thumbnailUrl != null && item.thumbnailUrl!.isNotEmpty)
            CachedImage(
              item.thumbnailUrl!,
              mediaReference: item.thumbnailReference,
              fit: BoxFit.cover,
              errorWidget: (_) => Container(color: Colors.black),
            )
          else
            Container(color: Colors.black87),
          const Center(
            child: Icon(Icons.play_circle_fill, size: 34, color: Colors.white),
          ),
        ],
      );
    }
    return CachedImage(
      item.url,
      mediaReference: item.mediaReference,
      fit: BoxFit.cover,
      placeholder: (_) => placeholder,
      errorWidget: (_) => placeholder,
    );
  }
}

// ── Fullscreen viewer ────────────────────────────────────────────────────────
class GalleryViewer extends StatefulWidget {
  final String venueId;
  final List<VenueGalleryItem> items;
  final int initialIndex;
  final bool allowReport;

  /// null → salt-okunur (silme ikonu gösterilmez, ör. müşteri detay sayfası).
  final Future<void> Function(VenueGalleryItem item)? onDelete;

  /// Verilirse (yalnızca sahibi) henüz yayınlanmamış yüklemeler galerinin
  /// başında sayfa olarak gösterilir; altta durum kartı (Under review /
  /// Photo not shared …) çıkar. [initialIndex] bu birleşik sıraya göredir.
  final PendingPublicMediaService? pendingUploads;

  /// "Create new photo" — reddedilen/başarısız yüklemeden yenisini ekler.
  final VoidCallback? onRetake;
  const GalleryViewer({
    super.key,
    required this.venueId,
    required this.items,
    required this.initialIndex,
    this.allowReport = false,
    this.onDelete,
    this.pendingUploads,
    this.onRetake,
  });

  bool get canEdit => onDelete != null;

  @override
  State<GalleryViewer> createState() => _GalleryViewerState();
}

class _GalleryViewerState extends State<GalleryViewer> {
  late final PageController _controller;
  late List<VenueGalleryItem> _items;
  late int _index;

  @override
  void initState() {
    super.initState();
    _items = List.of(widget.items);
    _index = widget.initialIndex;
    _controller = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<PendingPublicMedia> get _pending =>
      widget.pendingUploads?.forKind(
        PendingPublicMediaKind.venueGallery,
        venueId: widget.venueId,
      ) ??
      const [];

  /// Görünen sayfa yayınlanmış bir öğe ise o; bekleyen yüklemede null.
  VenueGalleryItem? _publishedAt(int index, int pendingCount) {
    final i = index - pendingCount;
    return i >= 0 && i < _items.length ? _items[i] : null;
  }

  Future<void> _delete() async {
    final item = _publishedAt(_index, _pending.length);
    if (item == null) return;
    final ok = await showDestructiveConfirmationDialog(
      context,
      title: 'Remove from gallery',
      message: 'This media will be permanently removed.',
      confirmLabel: 'Remove',
      icon: Icons.delete_outline_rounded,
    );
    if (!ok || !mounted) return;
    try {
      await widget.onDelete!(item);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not remove media'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _items = _items.where((i) => i.id != item.id).toList();
      final total = _pending.length + _items.length;
      if (_index >= total) _index = total - 1;
    });
    if (_pending.length + _items.length == 0) Navigator.of(context).pop();
  }

  Future<void> _report() async {
    final item = _publishedAt(_index, _pending.length);
    if (item == null) return;
    await showReportUserSheet(
      context,
      title: 'Why are you reporting this media?',
      venueGalleryItemId: item.id,
    );
  }

  @override
  Widget build(BuildContext context) {
    final uploads = widget.pendingUploads;
    if (uploads == null) return _buildPage(const []);
    return ListenableBuilder(
      listenable: uploads.changes,
      builder: (context, _) => _buildPage(_pending),
    );
  }

  /// Bekleyen bir yükleme kaybolunca (yayınlandı / kapatıldı) görünen sayfayı
  /// aralıkta tut; hiç sayfa kalmazsa kapat.
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

  Widget _buildPage(List<PendingPublicMedia> pending) {
    final count = pending.length + _items.length;
    _keepIndexInRange(count);
    final index = count == 0 ? 0 : _index.clamp(0, count - 1);
    final currentPending = index < pending.length ? pending[index] : null;
    final isPublished = count > 0 && currentPending == null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: count,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              if (i < pending.length) {
                final upload = pending[i];
                return OwnerStoryUploadMedia(
                  key: ValueKey(upload.id),
                  item: upload,
                  paused: i != index,
                );
              }
              final item = _items[i - pending.length];
              if (item.isVideo) return _VideoPage(url: item.url);
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: CachedImage(
                    item.url,
                    mediaReference: item.mediaReference,
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),

          // Üst şerit — story / moment görüntüleyicisiyle aynı: koyu karartma,
          // güvenli alanın 38px altında satır, sağda ortak report/sil/kapat.
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
                    if (widget.allowReport && isPublished)
                      MediaViewerReportButton(onPressed: _report),
                    if (widget.canEdit && isPublished)
                      MediaViewerDeleteButton(onPressed: _delete),
                    MediaViewerCloseButton(
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Yayınlanmamış yükleme: kişisel profildeki gibi altta durum kartı.
          if (currentPending != null &&
              currentPending.state != PendingPublicMediaState.published)
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
                child: OwnerStoryUploadStatus(
                  key: ValueKey(currentPending.id),
                  item: currentPending,
                  onCreateStory: widget.onRetake == null
                      ? null
                      : () {
                          widget.pendingUploads?.dismiss(currentPending.id);
                          Navigator.of(context).pop();
                          widget.onRetake!();
                        },
                  onDismiss: () =>
                      widget.pendingUploads?.dismiss(currentPending.id),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoPage extends StatefulWidget {
  final String url;
  const _VideoPage({required this.url});

  @override
  State<_VideoPage> createState() => _VideoPageState();
}

class _VideoPageState extends State<_VideoPage> {
  VideoPlayerController? _controller;

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) async {
        if (!mounted) return;
        await _controller?.setLooping(true);
        await _controller?.play();
        if (!mounted) return;
        setState(() {});
      });
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }
    return Center(
      child: GestureDetector(
        onTap: _togglePlayback,
        child: Stack(
          alignment: Alignment.center,
          children: [
            AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
            if (!c.value.isPlaying)
              IgnorePointer(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.58),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.30),
                    ),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Read-only horizontal strip (customer venue detail page) ──────────────────
/// Kendi verisini yükler; boşsa hiç görünmez. Tap → salt-okunur fullscreen viewer.
class VenueGalleryStrip extends StatefulWidget {
  final String venueId;
  final int refreshEpoch;
  final VenueGalleryRepository? repository;

  /// Galeri yüklendiğinde öğe sayısını üst widget'a bildirir — böylece sayı
  /// strip'in kendi başlığı yerine ebeveynin bölüm başlığında gösterilebilir.
  final ValueChanged<int>? onCountChanged;

  const VenueGalleryStrip({
    super.key,
    required this.venueId,
    this.refreshEpoch = 0,
    this.repository,
    this.onCountChanged,
  });

  @override
  State<VenueGalleryStrip> createState() => _VenueGalleryStripState();
}

class _VenueGalleryStripState extends State<VenueGalleryStrip> {
  late final _repo = widget.repository ?? VenueGalleryRepository();
  List<VenueGalleryItem> _items = [];
  bool _loading = true;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant VenueGalleryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.venueId != widget.venueId ||
        oldWidget.refreshEpoch != widget.refreshEpoch) {
      _load();
    }
  }

  Future<void> _load() async {
    final request = ++_loadRequest;
    try {
      final items = await _repo.getGallery(widget.venueId);
      if (!mounted || request != _loadRequest) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      widget.onCountChanged?.call(_items.length);
    } catch (_) {
      if (!mounted || request != _loadRequest) return;
      setState(() => _loading = false);
      widget.onCountChanged?.call(_items.length);
    }
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GalleryViewer(
          venueId: widget.venueId,
          items: List.of(_items),
          initialIndex: index,
          allowReport: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || _items.isEmpty) return const SizedBox.shrink();

    // Başlık ve adet artık ebeveyndeki bölüm başlığında gösteriliyor; strip
    // sadece yatay görsel şeridini render eder.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            itemCount: _items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => GestureDetector(
              onTap: () => _openViewer(i),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 120,
                  height: 150,
                  child: GalleryTile(item: _items[i]),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
