import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import '../data/venue_event_repository.dart';

class VenueEventDetailPage extends StatefulWidget {
  final String venueId;
  final VenueUpcomingEvent event;

  const VenueEventDetailPage({
    super.key,
    required this.venueId,
    required this.event,
  });

  @override
  State<VenueEventDetailPage> createState() => _VenueEventDetailPageState();
}

class _VenueEventDetailPageState extends State<VenueEventDetailPage> {
  final _repo = VenueEventRepository();

  // Edit state
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late DateTime _startAt;
  late DateTime _endAt;
  late List<String> _existingPhotos;
  final List<File> _newPhotos = [];

  static const _kBg     = Color(0xFF06091A);
  static const _kSheet  = Color(0xFF0B1322);
  static const _kCard   = Color(0xFF0D1A30);
  static const _kBlueLt = AppColors.blueDark;
  static const _kBorder = Color(0xFF162040);
  static const _kDim    = Color(0xFF3A5070);
  static const _kText   = Color(0xFFC8D8F0);
  static const _kRed    = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.event.title);
    _descCtrl  = TextEditingController(text: widget.event.description ?? '');
    _priceCtrl = TextEditingController(
      text: widget.event.priceAed != null ? '${widget.event.priceAed}' : '',
    );
    _startAt = widget.event.startAt;
    _endAt   = widget.event.endAt;
    _existingPhotos = List.from(widget.event.photos);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _formatDt(DateTime dt) {
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[(dt.weekday - 1) % 7]}, ${dt.day} ${months[dt.month - 1]} · $h:$m';
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now     = DateTime.now();
    final initial = isStart ? _startAt : _endAt;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: _kBlueLt, surface: _kCard),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(primary: _kBlueLt, surface: _kCard),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isStart) {
        _startAt = dt;
        if (_endAt.isBefore(dt)) _endAt = dt.add(const Duration(hours: 3));
      } else {
        _endAt = dt;
      }
    });
  }

  Future<void> _pickPhoto() async {
    if (_existingPhotos.length + _newPhotos.length >= 3) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _newPhotos.add(File(picked.path)));
  }

  Future<void> _save() async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      final priceText = _priceCtrl.text.trim();
      await _repo.updateEvent(
        venueId: widget.venueId,
        eventId: widget.event.id,
        title: _titleCtrl.text.trim(),
        description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
        startAt: _startAt,
        endAt: _endAt,
        priceAed: priceText.isEmpty ? null : int.tryParse(priceText),
        clearPrice: priceText.isEmpty,
      );
      for (final photo in _newPhotos) {
        await _repo.uploadPhoto(
          venueId: widget.venueId,
          eventId: widget.event.id,
          file: photo,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showPremiumErrorDialog(context, message: 'Could not save changes.');
    }
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _kSheet,
        title: const Text('Delete Event', style: TextStyle(color: _kText)),
        content: const Text('This event will be permanently deleted.',
            style: TextStyle(color: _kDim)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _kDim)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: _kRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _deleting = true);
    try {
      await _repo.deleteEvent(venueId: widget.venueId, eventId: widget.event.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deleting = false);
      await showPremiumErrorDialog(context, message: 'Could not delete event.');
    }
  }

  Future<void> _removeExistingPhoto(String url) async {
    try {
      await _repo.removePhoto(
        venueId: widget.venueId,
        eventId: widget.event.id,
        photoUrl: url,
      );
      setState(() => _existingPhotos.remove(url));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove photo'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: Text(
          _editing ? 'Edit Event' : 'Event',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kText),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_editing) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: _kBlueLt, size: 20),
              onPressed: () => setState(() => _editing = true),
              tooltip: 'Edit',
            ),
            IconButton(
              icon: _deleting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _kRed))
                  : const Icon(Icons.delete_outline, color: _kRed, size: 20),
              onPressed: _deleting ? null : _confirmDelete,
              tooltip: 'Delete',
            ),
          ] else ...[
            if (_saving)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueLt))),
              )
            else ...[
              TextButton(
                onPressed: () => setState(() => _editing = false),
                child: const Text('Cancel', style: TextStyle(color: _kDim)),
              ),
              TextButton(
                onPressed: _save,
                child: const Text('Save', style: TextStyle(color: _kBlueLt, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      body: _editing ? _buildEditBody() : _buildViewBody(),
    );
  }

  // ── View mode ──────────────────────────────────────────────────────────────

  Widget _buildViewBody() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Photos
        if (_existingPhotos.isNotEmpty) ...[
          SizedBox(
            height: 80,
            child: Row(
              children: _existingPhotos.map((url) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover),
                ),
              )).toList(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // Title
        Text(widget.event.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: _kText)),
        const SizedBox(height: 10),

        // Date
        _infoRow(Icons.calendar_today_outlined, _formatDt(widget.event.startAt)),
        const SizedBox(height: 6),
        _infoRow(Icons.flag_outlined, _formatDt(widget.event.endAt)),

        if (widget.event.priceAed != null) ...[
          const SizedBox(height: 6),
          _infoRow(
            Icons.payments_outlined,
            widget.event.priceAed == 0 ? 'Free' : 'AED ${widget.event.priceAed}',
          ),
        ],

        if (widget.event.description != null && widget.event.description!.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Divider(color: Color(0xFF0D1A30)),
          const SizedBox(height: 12),
          Text(widget.event.description!,
              style: const TextStyle(fontSize: 14, color: _kText, height: 1.6)),
        ],
      ],
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 15, color: _kBlueLt),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontSize: 13, color: _kDim, fontWeight: FontWeight.w500)),
      ],
    );
  }

  // ── Edit mode ──────────────────────────────────────────────────────────────

  Widget _buildEditBody() {
    final totalPhotos = _existingPhotos.length + _newPhotos.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _field(controller: _titleCtrl, label: 'Title', maxLength: 120),
        const SizedBox(height: 12),
        _field(controller: _descCtrl, label: 'Description (optional)', maxLines: 3, maxLength: 1000),
        const SizedBox(height: 12),
        _field(controller: _priceCtrl, label: 'Price AED (optional)', keyboardType: TextInputType.number),
        const SizedBox(height: 20),

        _DateRow(label: 'Start', value: _formatDt(_startAt), onTap: () => _pickDate(isStart: true)),
        const SizedBox(height: 10),
        _DateRow(label: 'End',   value: _formatDt(_endAt),   onTap: () => _pickDate(isStart: false)),

        const SizedBox(height: 24),
        const Text('Photos (up to 3)',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
        const SizedBox(height: 10),

        SizedBox(
          height: 110,
          child: Row(
            children: [
              // Existing photos
              ..._existingPhotos.map((url) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(url, width: 100, height: 110, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => _removeExistingPhoto(url),
                      child: _removeBtn(),
                    ),
                  ),
                ]),
              )),
              // New local photos
              ..._newPhotos.asMap().entries.map((e) => Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Stack(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(e.value, width: 100, height: 110, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: 4, right: 4,
                    child: GestureDetector(
                      onTap: () => setState(() => _newPhotos.removeAt(e.key)),
                      child: _removeBtn(),
                    ),
                  ),
                ]),
              )),
              // Add button
              if (totalPhotos < 3)
                GestureDetector(
                  onTap: _pickPhoto,
                  child: Container(
                    width: 100, height: 110,
                    decoration: BoxDecoration(
                      color: _kCard,
                      border: Border.all(color: _kBorder, width: 1.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined, size: 26, color: _kDim),
                        const SizedBox(height: 4),
                        Text('Add photo', style: TextStyle(fontSize: 11, color: _kDim)),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _removeBtn() => Container(
    width: 22, height: 22,
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), shape: BoxShape.circle),
    child: const Icon(Icons.close, size: 13, color: Colors.white),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _kDim)),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          style: const TextStyle(fontSize: 14, color: _kText),
          decoration: InputDecoration(
            counterStyle: const TextStyle(color: _kDim, fontSize: 11),
            filled: true,
            fillColor: _kCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _kBlueLt, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _DateRow({required this.label, required this.value, required this.onTap});

  static const _kCard   = Color(0xFF0D1A30);
  static const _kBorder = Color(0xFF162040);
  static const _kText   = Color(0xFFC8D8F0);
  static const _kBlueLt = AppColors.blueDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: _kCard,
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: _kBlueLt),
            const SizedBox(width: 10),
            Text('$label: $value',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: _kText)),
          ],
        ),
      ),
    );
  }
}
