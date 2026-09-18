import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_content_sections.dart';
import 'package:kmstry_frontend/features/venue/data/venue_gallery_repository.dart';

const _kMagenta = Color(0xFFE020D8);
const _maxVenueVideoDuration = Duration(seconds: 60);
const _maxVenueVideoUploadBytes = 100 * 1024 * 1024;

/// Venue profilinde gösterilen galeri: fotoğraf + en fazla 60 saniyelik video.
/// Kendi verisini yükler; [canEdit] true ise ekleme/silme kısayolları görünür.
class VenueGallerySection extends StatefulWidget {
  final String venueId;
  final bool canEdit;

  const VenueGallerySection({
    super.key,
    required this.venueId,
    required this.canEdit,
  });

  @override
  State<VenueGallerySection> createState() => _VenueGallerySectionState();
}

class _VenueGallerySectionState extends State<VenueGallerySection> {
  final _repo = VenueGalleryRepository();
  List<VenueGalleryItem> _items = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.getGallery(widget.venueId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  static const _videoExts = {
    'mp4',
    'mov',
    'm4v',
    '3gp',
    'webm',
    'mkv',
    'avi',
    'mpeg',
    'mpg',
  };
  static const _imageExts = {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'heic',
    'heif',
    'gif',
    'bmp',
  };

  bool _isVideoPath(String path) =>
      _videoExts.contains(path.split('.').last.toLowerCase());
  bool _isMediaPath(String path) {
    final ext = path.split('.').last.toLowerCase();
    return _videoExts.contains(ext) || _imageExts.contains(ext);
  }

  Future<void> _addMedia() async {
    if (_uploading) return;
    // FileType.media → yalnızca foto + video gösterir (belge/PDF gösterilmez), çoklu seçim.
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.media,
        allowMultiple: true,
      );
    } catch (_) {}
    final paths = (result?.files ?? [])
        .map((f) => f.path)
        .whereType<String>()
        .where(_isMediaPath) // güvenlik: medya olmayan her şeyi ele
        .toList();
    if (paths.isEmpty || !mounted) return;

    final validationMessage = await _validateSelectedVideos(paths);
    if (!mounted) return;
    if (validationMessage != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(validationMessage),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _uploading = true);
    var hadError = false;
    String? uploadErrorMessage;

    // Yüklemeden önce sıkıştır (foto → JPEG ~1600px, video → 720p) ve hepsini
    // paralel yükle; giriş sırasını koru.
    Future<VenueGalleryItem?> processAndUpload(String path) async {
      try {
        final isVideo = _isVideoPath(path);
        final File fileToUpload;
        File? thumb;
        if (isVideo) {
          fileToUpload = await MediaCompressor.compressGalleryVideo(File(path));
          if (await fileToUpload.length() > _maxVenueVideoUploadBytes) {
            uploadErrorMessage =
                'Video is too large. Please choose a smaller file.';
            hadError = true;
            return null;
          }
          thumb = await _generateThumbnail(path);
        } else {
          fileToUpload = await MediaCompressor.compressImage(File(path));
        }
        return await _repo.uploadItem(
          widget.venueId,
          fileToUpload,
          thumbnail: thumb,
        );
      } catch (error) {
        hadError = true;
        if (error.toString().contains('413')) {
          uploadErrorMessage =
              'Video is too large. Please choose a smaller file.';
        }
        return null;
      }
    }

    final results = await Future.wait(paths.map(processAndUpload));
    final added = results.whereType<VenueGalleryItem>().toList();

    if (!mounted) return;
    setState(() {
      if (added.isNotEmpty) _items = [...added.reversed, ..._items];
      _uploading = false;
    });
    if (added.isNotEmpty) {
      showSuccessSnackBar(
        context,
        message: added.length == 1
            ? 'Added to gallery!'
            : '${added.length} added to gallery!',
      );
    }
    if (hadError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            uploadErrorMessage ?? 'Some uploads failed. Please try again.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<String?> _validateSelectedVideos(List<String> paths) async {
    for (final path in paths.where(_isVideoPath)) {
      final controller = VideoPlayerController.file(File(path));
      try {
        await controller.initialize();
        if (controller.value.duration > _maxVenueVideoDuration) {
          return 'Video must be 60 seconds or shorter.';
        }
      } catch (_) {
        return 'Could not read the selected video. Please try another file.';
      } finally {
        await controller.dispose();
      }
    }
    return null;
  }

  Future<File?> _generateThumbnail(String videoPath) async {
    try {
      final dir = await getTemporaryDirectory();
      final path = await VideoThumbnail.thumbnailFile(
        video: videoPath,
        thumbnailPath: dir.path,
        imageFormat: ImageFormat.JPEG,
        maxWidth: 720,
        quality: 80,
      );
      return path == null ? null : File(path);
    } catch (_) {
      return null;
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
      if (mounted)
        setState(() => _items = _items.where((i) => i.id != item.id).toList());
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

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => GalleryViewer(
          items: List.of(_items),
          initialIndex: index,
          onDelete: widget.canEdit
              ? (item) async {
                  await _repo.deleteItem(widget.venueId, item.id);
                  if (mounted)
                    setState(
                      () => _items = _items
                          .where((i) => i.id != item.id)
                          .toList(),
                    );
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              venueSectionTitle(context, AppColors.teal, 'Photos & Videos'),
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
                  onTap: _uploading ? null : _addMedia,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _kMagenta.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: _uploading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(_kMagenta),
                            ),
                          )
                        : const Row(
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

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(_kMagenta),
              ),
            ),
          )
        else if (_items.isEmpty)
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
                        ? 'Add photos and videos of your venue'
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
                final scrolls = _items.length > 9;

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
                  itemCount: _items.length,
                  itemBuilder: (_, i) {
                    final item = _items[i];
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
  const GalleryTile({required this.item});

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
  final List<VenueGalleryItem> items;
  final int initialIndex;

  /// null → salt-okunur (silme ikonu gösterilmez, ör. müşteri detay sayfası).
  final Future<void> Function(VenueGalleryItem item)? onDelete;
  const GalleryViewer({
    super.key,
    required this.items,
    required this.initialIndex,
    this.onDelete,
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

  Future<void> _delete() async {
    final item = _items[_index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0B1322),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Text(
          'Remove from gallery',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        content: const Text(
          'This media will be permanently removed.',
          style: TextStyle(fontSize: 13, color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
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
      if (_index >= _items.length) _index = _items.length - 1;
    });
    if (_items.isEmpty) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: _items.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) {
              final item = _items[i];
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

          // Üst şerit: sayaç + silme + kapatma (story tarzı)
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 12,
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${_index + 1} / ${_items.length}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                if (widget.canEdit)
                  _CircleBtn(
                    icon: Icons.delete_outline_rounded,
                    color: const Color(0xFFEF4444),
                    onTap: _delete,
                  ),
                const SizedBox(width: 8),
                _CircleBtn(
                  icon: Icons.close_rounded,
                  color: Colors.white,
                  onTap: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _CircleBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.4),
        ),
        child: Icon(icon, size: 20, color: color),
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

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller?.play();
        _controller?.setLooping(true);
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
        onTap: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
        child: AspectRatio(
          aspectRatio: c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
      ),
    );
  }
}

// ── Read-only horizontal strip (customer venue detail page) ──────────────────
/// Kendi verisini yükler; boşsa hiç görünmez. Tap → salt-okunur fullscreen viewer.
class VenueGalleryStrip extends StatefulWidget {
  final String venueId;

  /// Galeri yüklendiğinde öğe sayısını üst widget'a bildirir — böylece sayı
  /// strip'in kendi başlığı yerine ebeveynin bölüm başlığında gösterilebilir.
  final ValueChanged<int>? onCountChanged;

  const VenueGalleryStrip({
    super.key,
    required this.venueId,
    this.onCountChanged,
  });

  @override
  State<VenueGalleryStrip> createState() => _VenueGalleryStripState();
}

class _VenueGalleryStripState extends State<VenueGalleryStrip> {
  final _repo = VenueGalleryRepository();
  List<VenueGalleryItem> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final items = await _repo.getGallery(widget.venueId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      widget.onCountChanged?.call(_items.length);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
      widget.onCountChanged?.call(0);
    }
  }

  void _openViewer(int index) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            GalleryViewer(items: List.of(_items), initialIndex: index),
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
