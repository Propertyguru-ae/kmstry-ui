import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/core/ui/destructive_confirmation_dialog.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/media/media_compressor.dart';
import 'package:kmstry_frontend/features/venue/data/venue_menu_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_menu_repository.dart';

/// Venue menü listeleme sayfası. [canManage] true ise menü öğeleri eklenebilir,
/// düzenlenebilir ve silinebilir; false ise salt-okunur (diğer kullanıcılar).
class VenueMenuPage extends StatefulWidget {
  final String venueId;
  final String venueName;
  final bool canManage;

  const VenueMenuPage({
    super.key,
    required this.venueId,
    required this.venueName,
    this.canManage = false,
  });

  @override
  State<VenueMenuPage> createState() => _VenueMenuPageState();
}

class _VenueMenuPageState extends State<VenueMenuPage> {
  final _repo = VenueMenuRepository();
  List<VenueMenuItem> _items = [];
  final Set<VenueMenuCategory> _collapsedCategories = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    VenueMenuRepository.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    VenueMenuRepository.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load();

  Future<void> _load() async {
    try {
      final items = await _repo.getMenu(widget.venueId);
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<VenueMenuCategory, List<VenueMenuItem>> get _grouped {
    final map = <VenueMenuCategory, List<VenueMenuItem>>{};
    for (final item in _items) {
      map.putIfAbsent(item.category, () => []).add(item);
    }
    return map;
  }

  Future<void> _openEditor([VenueMenuItem? existing]) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            VenueMenuItemEditPage(venueId: widget.venueId, existing: existing),
      ),
    );
    // Editör kaydettiyse repo.changes zaten tetikledi; yine de garanti için.
    if (mounted) _load();
  }

  Future<void> _openDetail(VenueMenuItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenueMenuItemDetailPage(
          venueId: widget.venueId,
          item: item,
          canManage: widget.canManage,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF6F7F9);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Text(
              'Menu',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              widget.venueName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: (isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: widget.canManage
          ? FloatingActionButton.extended(
              onPressed: () => _openEditor(),
              backgroundColor: AppColors.blue,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text(
                'Add item',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
          ? _buildEmpty(isDark)
          : _buildList(isDark),
    );
  }

  Widget _buildEmpty(bool isDark) {
    final sub = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restaurant_menu_outlined, size: 54, color: sub),
            const SizedBox(height: 14),
            Text(
              widget.canManage ? 'No menu items yet' : 'No menu available',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              widget.canManage
                  ? 'Add your first dish so guests can see what you serve.'
                  : 'This venue hasn’t published a menu yet.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: sub, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(bool isDark) {
    final grouped = _grouped;
    final sections = kVenueMenuCategoryOrder
        .where((c) => (grouped[c]?.isNotEmpty ?? false))
        .toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 8,
          bottom: MediaQuery.of(context).padding.bottom + 96,
        ),
        itemCount: sections.length,
        itemBuilder: (context, index) {
          final category = sections[index];
          final items = grouped[category]!;
          final collapsed = _collapsedCategories.contains(category);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(top: index == 0 ? 6 : 22, bottom: 12),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      setState(() {
                        if (collapsed) {
                          _collapsedCategories.remove(category);
                        } else {
                          _collapsedCategories.add(category);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.blue.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              category.icon,
                              size: 18,
                              color: AppColors.blue,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              category.label,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.06)
                                  : Colors.black.withValues(alpha: 0.045),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '${items.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: isDark
                                    ? AppColors.darkTextSecondary
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          AnimatedRotation(
                            turns: collapsed ? -0.25 : 0,
                            duration: const Duration(milliseconds: 180),
                            child: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: isDark
                                  ? AppColors.darkTextSecondary
                                  : AppColors.lightTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 200),
                firstCurve: Curves.easeOut,
                secondCurve: Curves.easeIn,
                sizeCurve: Curves.easeInOut,
                crossFadeState: collapsed
                    ? CrossFadeState.showSecond
                    : CrossFadeState.showFirst,
                firstChild: Column(
                  children: items
                      .map(
                        (item) => _MenuItemCard(
                          item: item,
                          isDark: isDark,
                          onTap: () => _openDetail(item),
                        ),
                      )
                      .toList(),
                ),
                secondChild: const SizedBox(width: double.infinity),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final VenueMenuItem item;
  final bool isDark;
  final VoidCallback onTap;

  const _MenuItemCard({
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? AppColors.darkSurface : Colors.white;
    final sub = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final price = item.priceLabel;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.05),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (price != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        price,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.blue,
                        ),
                      ),
                    ],
                  ],
                ),
                if (item.description != null &&
                    item.description!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.description!,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, height: 1.35, color: sub),
                  ),
                ],
                if (item.photos.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _MenuPhotosStrip(photos: item.photos, isDark: isDark),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Açıklamanın altında küçük foto şeridi: en fazla 3 küçük resim gösterir;
/// 3'ten fazlası varsa 3. karonun üzerine "+N" bindirilir (N = kalan sayı).
class _MenuPhotosStrip extends StatelessWidget {
  final List<String> photos;
  final bool isDark;
  const _MenuPhotosStrip({required this.photos, required this.isDark});

  static const double _tile = 58;
  static const int _maxTiles = 3;

  @override
  Widget build(BuildContext context) {
    final visible = photos.take(_maxTiles).toList();
    final extra = photos.length - visible.length;
    return Row(
      children: [
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: _tile,
              height: _tile,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedImage(visible[i], fit: BoxFit.cover),
                  // Son görünen karo + fazladan foto varsa "+N" bindirmesi.
                  if (i == visible.length - 1 && extra > 0)
                    Container(
                      color: Colors.black.withValues(alpha: 0.5),
                      alignment: Alignment.center,
                      child: Text(
                        '+$extra',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DETAIL PAGE — bir menü öğesinin tam görünümü (foto galerisi + açıklama).
// canManage ise app bar'da kalem (düzenle) + çöp kutusu (sil) aksiyonları.
// ─────────────────────────────────────────────────────────────────────────────

class VenueMenuItemDetailPage extends StatefulWidget {
  final String venueId;
  final VenueMenuItem item;
  final bool canManage;

  const VenueMenuItemDetailPage({
    super.key,
    required this.venueId,
    required this.item,
    this.canManage = false,
  });

  @override
  State<VenueMenuItemDetailPage> createState() =>
      _VenueMenuItemDetailPageState();
}

class _VenueMenuItemDetailPageState extends State<VenueMenuItemDetailPage> {
  final _repo = VenueMenuRepository();
  late VenueMenuItem _item;
  final _pageController = PageController();
  int _photoIndex = 0;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _item = widget.item;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _edit() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            VenueMenuItemEditPage(venueId: widget.venueId, existing: _item),
      ),
    );
    // Düzenleme sonrası güncel öğeyi çek; silinmişse detay sayfasını kapat.
    try {
      final items = await _repo.getMenu(widget.venueId);
      if (!mounted) return;
      final updated = items.where((i) => i.id == _item.id).toList();
      if (updated.isEmpty) {
        Navigator.pop(context);
      } else {
        setState(() {
          _item = updated.first;
          _photoIndex = 0;
        });
      }
    } catch (_) {
      /* sessiz geç — mevcut görünüm kalır */
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDestructiveConfirmationDialog(
      context,
      title: 'Remove item',
      message: '“${_item.title}” will be removed from your menu.',
      confirmLabel: 'Remove',
      icon: Icons.delete_outline_rounded,
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _repo.deleteItem(widget.venueId, _item.id);
      if (!mounted) return;
      showSuccessSnackBar(context, message: 'Item removed');
      Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() => _deleting = false);
        await showPremiumErrorDialog(
          context,
          message: 'Could not remove the item. Please try again.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF6F7F9);
    final sub = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final price = _item.priceLabel;
    final photos = _item.photos;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
        actions: widget.canManage
            ? [
                IconButton(
                  tooltip: 'Edit',
                  onPressed: _deleting ? null : _edit,
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: 'Remove',
                  onPressed: _deleting ? null : _delete,
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 4),
              ]
            : null,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          if (photos.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      itemCount: photos.length,
                      onPageChanged: (i) => setState(() => _photoIndex = i),
                      itemBuilder: (context, i) =>
                          CachedImage(photos[i], fit: BoxFit.cover),
                    ),
                    if (photos.length > 1)
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < photos.length; i++)
                              Container(
                                width: 7,
                                height: 7,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _photoIndex
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
          ],
          Row(
            children: [
              Icon(_item.category.icon, size: 16, color: AppColors.blue),
              const SizedBox(width: 6),
              Text(
                _item.category.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: sub,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _item.title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
              if (price != null) ...[
                const SizedBox(width: 12),
                Text(
                  price,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.blue,
                  ),
                ),
              ],
            ],
          ),
          if (_item.description != null && _item.description!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              _item.description!,
              style: TextStyle(fontSize: 15, height: 1.45, color: sub),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SECTION — venue profilinde galeri altında "Add menu" / "View menu"
// ─────────────────────────────────────────────────────────────────────────────

/// Venue profil sayfasında galeri altında gösterilir. Menü öğesi yoksa "Add menu",
/// varsa "View menu (N)" kısayolu sunar; ikisi de yönetilebilir menü sayfasını açar.
class VenueMenuProfileSection extends StatefulWidget {
  final String venueId;
  final String venueName;

  const VenueMenuProfileSection({
    super.key,
    required this.venueId,
    required this.venueName,
  });

  @override
  State<VenueMenuProfileSection> createState() =>
      _VenueMenuProfileSectionState();
}

class _VenueMenuProfileSectionState extends State<VenueMenuProfileSection> {
  final _repo = VenueMenuRepository();
  int _count = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
    VenueMenuRepository.changes.addListener(_onChanged);
  }

  @override
  void dispose() {
    VenueMenuRepository.changes.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => _load();

  Future<void> _load() async {
    try {
      final items = await _repo.getMenu(widget.venueId);
      if (!mounted) return;
      setState(() {
        _count = items.length;
        _loaded = true;
      });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _open() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VenueMenuPage(
          venueId: widget.venueId,
          venueName: widget.venueName,
          canManage: true,
        ),
      ),
    );
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasMenu = _count > 0;
    final sub = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: _loaded ? _open : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.blue.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.restaurant_menu_outlined,
                    color: AppColors.blue,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasMenu ? 'View menu' : 'Add menu',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasMenu
                            ? '$_count item${_count == 1 ? '' : 's'} · tap to manage'
                            : 'Show guests what you serve',
                        style: TextStyle(fontSize: 12.5, color: sub),
                      ),
                    ],
                  ),
                ),
                Icon(
                  hasMenu ? Icons.chevron_right_rounded : Icons.add_rounded,
                  color: AppColors.blue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ADD / EDIT PAGE
// ─────────────────────────────────────────────────────────────────────────────

class VenueMenuItemEditPage extends StatefulWidget {
  final String venueId;
  final VenueMenuItem? existing;

  const VenueMenuItemEditPage({
    super.key,
    required this.venueId,
    this.existing,
  });

  @override
  State<VenueMenuItemEditPage> createState() => _VenueMenuItemEditPageState();
}

class _VenueMenuItemEditPageState extends State<VenueMenuItemEditPage> {
  final _repo = VenueMenuRepository();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();

  late VenueMenuCategory _category;
  String _currency = 'AED';
  List<String> _photoUrls = [];
  bool _uploading = false;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _category = e?.category ?? VenueMenuCategory.main;
    _currency = e?.currency ?? 'AED';
    _titleCtrl.text = e?.title ?? '';
    _descCtrl.text = e?.description ?? '';
    if (e?.price != null) {
      final p = e!.price!;
      _priceCtrl.text = p == p.roundToDouble()
          ? p.toStringAsFixed(0)
          : p.toStringAsFixed(2);
    }
    _photoUrls = List.of(e?.photos ?? const []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'heic', 'heif'};

  Future<void> _addPhotos() async {
    if (_uploading || _photoUrls.length >= 6) return;
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
      );
    } catch (_) {}
    final paths = (result?.files ?? [])
        .map((f) => f.path)
        .whereType<String>()
        .where((p) => _imageExts.contains(p.split('.').last.toLowerCase()))
        .take(6 - _photoUrls.length)
        .toList();
    if (paths.isEmpty || !mounted) return;

    setState(() => _uploading = true);
    var hadError = false;
    for (final path in paths) {
      try {
        final compressed = await MediaCompressor.compressImage(File(path));
        final url = await _repo.uploadPhoto(widget.venueId, compressed);
        if (!mounted) return;
        setState(() => _photoUrls = [..._photoUrls, url]);
      } catch (_) {
        hadError = true;
      }
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    if (hadError) {
      await showPremiumErrorDialog(
        context,
        message: 'Some photos could not be uploaded.',
      );
    }
  }

  void _removePhoto(String url) {
    setState(() => _photoUrls = _photoUrls.where((u) => u != url).toList());
  }

  Future<void> _save() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) {
      await showPremiumErrorDialog(
        context,
        title: 'Missing title',
        message: 'Please enter a name for this item.',
      );
      return;
    }
    final priceText = _priceCtrl.text.trim().replaceAll(',', '.');
    double? price;
    if (priceText.isNotEmpty) {
      price = double.tryParse(priceText);
      if (price == null || price < 0) {
        await showPremiumErrorDialog(
          context,
          title: 'Invalid price',
          message: 'Please enter a valid price, or leave it empty.',
        );
        return;
      }
    }

    setState(() => _saving = true);
    try {
      final desc = _descCtrl.text.trim();
      if (_isEditing) {
        await _repo.updateItem(
          widget.venueId,
          widget.existing!.id,
          category: _category,
          title: title,
          description: desc,
          price: price,
          clearPrice: price == null,
          currency: _currency,
          photoUrls: _photoUrls,
        );
      } else {
        await _repo.createItem(
          widget.venueId,
          category: _category,
          title: title,
          description: desc.isEmpty ? null : desc,
          price: price,
          currency: _currency,
          photoUrls: _photoUrls,
        );
      }
      if (!mounted) return;
      showSuccessSnackBar(
        context,
        message: _isEditing ? 'Item updated' : 'Item added to menu',
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        setState(() => _saving = false);
        await showPremiumErrorDialog(
          context,
          message: publicTextErrorMessage(
            error,
            fallback: 'Could not save the item. Please try again.',
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : const Color(0xFFF6F7F9);
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          _isEditing ? 'Edit item' : 'Add menu item',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
          child: ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              _label('Category', isDark),
              const SizedBox(height: 8),
              _buildCategoryChips(isDark),
              const SizedBox(height: 20),
              _label('Photos', isDark),
              const SizedBox(height: 8),
              _buildPhotos(isDark),
              const SizedBox(height: 20),
              _label('Title', isDark),
              const SizedBox(height: 8),
              _field(
                controller: _titleCtrl,
                hint: 'e.g. Margherita Pizza',
                isDark: isDark,
              ),
              const SizedBox(height: 20),
              _label('Description', isDark),
              const SizedBox(height: 8),
              _field(
                controller: _descCtrl,
                hint: 'Ingredients, portion, notes…',
                isDark: isDark,
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              _label('Price', isDark),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCurrencyPicker(isDark),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      controller: _priceCtrl,
                      hint: 'e.g. 120',
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      prefix: '${menuCurrencySymbol(_currency)} ',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Leave empty to hide the price.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
              ),
              const SizedBox(height: 28),
              PrimaryButton(
                label: _isEditing ? 'Save changes' : 'Add to menu',
                loading: _saving,
                onPressed: _saving ? null : _save,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text, bool isDark) => Text(
    text,
    style: TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: isDark
          ? AppColors.darkTextSecondary
          : AppColors.lightTextSecondary,
      letterSpacing: 0.2,
    ),
  );

  Widget _buildCurrencyPicker(bool isDark) {
    return Container(
      height: 50,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _currency,
          isDense: true,
          borderRadius: BorderRadius.circular(14),
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: isDark
                ? AppColors.darkTextPrimary
                : AppColors.lightTextPrimary,
          ),
          dropdownColor: isDark ? AppColors.darkSurface : Colors.white,
          items: kMenuCurrencies
              .map(
                (c) => DropdownMenuItem<String>(
                  value: c.code,
                  child: Text('${c.symbol}  ${c.code}'),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) setState(() => _currency = v);
          },
        ),
      ),
    );
  }

  Widget _buildCategoryChips(bool isDark) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: kVenueMenuCategoryOrder.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final c = kVenueMenuCategoryOrder[index];
          final selected = c == _category;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => setState(() => _category = c),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.blue
                      : (isDark ? AppColors.darkSurface : Colors.white),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? AppColors.blue
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : Colors.black.withValues(alpha: 0.08)),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      c.icon,
                      size: 15,
                      color: selected
                          ? Colors.white
                          : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      c.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? Colors.white
                            : (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPhotos(bool isDark) {
    return SizedBox(
      height: 92,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final url in _photoUrls)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      width: 92,
                      height: 92,
                      child: CachedImage(url, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    top: 4,
                    right: 4,
                    child: GestureDetector(
                      onTap: () => _removePhoto(url),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        padding: const EdgeInsets.all(3),
                        child: const Icon(
                          Icons.close_rounded,
                          size: 15,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (_photoUrls.length < 6)
            GestureDetector(
              onTap: _uploading ? null : _addPhotos,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkSurface : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.10),
                  ),
                ),
                child: _uploading
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_a_photo_outlined,
                            color: AppColors.blue,
                            size: 22,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Add',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.blue,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required bool isDark,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    String? prefix,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        prefixText: prefix,
        filled: true,
        fillColor: isDark ? AppColors.darkSurface : Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
      ),
    );
  }
}
