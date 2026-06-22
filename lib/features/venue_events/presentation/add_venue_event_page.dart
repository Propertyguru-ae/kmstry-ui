import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import '../data/venue_event_repository.dart';

class AddVenueEventPage extends StatefulWidget {
  final String venueId;
  final VenueUpcomingEvent? existing; // null → create, non-null → edit

  const AddVenueEventPage({super.key, required this.venueId, this.existing});

  @override
  State<AddVenueEventPage> createState() => _AddVenueEventPageState();
}

class _AddVenueEventPageState extends State<AddVenueEventPage> {
  final _repo    = VenueEventRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;

  DateTime? _startAt;
  DateTime? _endAt;
  List<String> _existingPhotos = [];
  final List<File> _newPhotos  = [];
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  static const _kBg     = Color(0xFF06091A);
  static const _kCard   = Color(0xFF0D1A30);
  static const _kBlueLt = AppColors.blueDark;
  static const _kBorder = Color(0xFF162040);
  static const _kDim    = Color(0xFF3A5070);
  static const _kText   = Color(0xFFC8D8F0);

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _descCtrl  = TextEditingController(text: e?.description ?? '');
    _priceCtrl = TextEditingController(text: e?.priceAed != null ? '${e!.priceAed}' : '');
    _startAt        = e?.startAt;
    _endAt          = e?.endAt;
    _existingPhotos = List.from(e?.photos ?? []);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now     = DateTime.now();
    final initial = isStart ? (_startAt ?? now) : (_endAt ?? _startAt ?? now);
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
        if (_endAt != null && _endAt!.isBefore(dt)) _endAt = dt.add(const Duration(hours: 3));
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

  Future<void> _removeExistingPhoto(String url) async {
    try {
      await _repo.removePhoto(
        venueId: widget.venueId,
        eventId: widget.existing!.id,
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startAt == null || _endAt == null) {
      _showError('Please set start and end date.');
      return;
    }
    if (_endAt!.isBefore(_startAt!)) {
      _showError('End time must be after start time.');
      return;
    }
    setState(() => _saving = true);
    try {
      final priceText = _priceCtrl.text.trim();
      final price     = priceText.isEmpty ? null : int.tryParse(priceText);
      String eventId;

      if (_isEdit) {
        await _repo.updateEvent(
          venueId:    widget.venueId,
          eventId:    widget.existing!.id,
          title:      _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          startAt:    _startAt,
          endAt:      _endAt,
          priceAed:   price,
          clearPrice: priceText.isEmpty,
        );
        eventId = widget.existing!.id;
      } else {
        final created = await _repo.createEvent(
          venueId:     widget.venueId,
          title:       _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          startAt:     _startAt!,
          endAt:       _endAt!,
          priceAed:    price,
        );
        eventId = created['id']?.toString() ?? '';
      }

      for (final photo in _newPhotos) {
        await _repo.uploadPhoto(venueId: widget.venueId, eventId: eventId, file: photo);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showPremiumErrorDialog(context, message: 'Could not save event. Please try again.');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  String _formatDt(DateTime dt) {
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[(dt.weekday - 1) % 7]}, ${dt.day} ${months[dt.month - 1]} · $h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final totalPhotos = _existingPhotos.length + _newPhotos.length;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: Text(
          _isEdit ? 'Edit Event' : 'New Event',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: _kText),
        ),
        leading: IconButton(
          icon: const Icon(Icons.close, color: _kText),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _kBlueLt))),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                _isEdit ? 'Save' : 'Publish',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: _kBlueLt),
              ),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white.withValues(alpha: 0.05)),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _field(
              controller: _titleCtrl,
              label: 'Event Title',
              hint: 'e.g. Saturday Night Live',
              maxLength: 120,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _descCtrl,
              label: 'Description (optional)',
              hint: 'Tell guests what to expect…',
              maxLines: 3,
              maxLength: 1000,
            ),
            const SizedBox(height: 12),
            _field(
              controller: _priceCtrl,
              label: 'Entry Price (AED, optional)',
              hint: '0 for free',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),

            _DateRow(
              label: 'Start',
              value: _startAt != null ? _formatDt(_startAt!) : null,
              onTap: () => _pickDate(isStart: true),
            ),
            const SizedBox(height: 10),
            _DateRow(
              label: 'End',
              value: _endAt != null ? _formatDt(_endAt!) : null,
              onTap: () => _pickDate(isStart: false),
            ),

            const SizedBox(height: 24),

            const Text('Photos (up to 3)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kText)),
            const SizedBox(height: 10),
            SizedBox(
              height: 110,
              child: Row(
                children: [
                  // Existing remote photos
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
                          child: _closeBtn(),
                        ),
                      ),
                    ]),
                  )),
                  // New local photos
                  ..._newPhotos.asMap().entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Stack(children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(entry.value, width: 100, height: 110, fit: BoxFit.cover),
                      ),
                      Positioned(
                        top: 4, right: 4,
                        child: GestureDetector(
                          onTap: () => setState(() => _newPhotos.removeAt(entry.key)),
                          child: _closeBtn(),
                        ),
                      ),
                    ]),
                  )),
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
        ),
      ),
    );
  }

  Widget _closeBtn() => Container(
    width: 22, height: 22,
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.7), shape: BoxShape.circle),
    child: const Icon(Icons.close, size: 13, color: Colors.white),
  );

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
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
          validator: validator,
          style: const TextStyle(fontSize: 14, color: _kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: _kDim.withValues(alpha: 0.7)),
            counterStyle: const TextStyle(color: _kDim, fontSize: 11),
            filled: true,
            fillColor: _kCard,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _kBlueLt, width: 1.5)),
          ),
        ),
      ],
    );
  }
}

class _DateRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback onTap;

  const _DateRow({required this.label, required this.value, required this.onTap});

  static const _kCard   = Color(0xFF0D1A30);
  static const _kBorder = Color(0xFF162040);
  static const _kDim    = Color(0xFF3A5070);
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
            Icon(Icons.calendar_today_outlined, size: 16, color: value != null ? _kBlueLt : _kDim),
            const SizedBox(width: 10),
            Text(
              '$label: ${value ?? 'Tap to set'}',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500,
                  color: value != null ? _kText : _kDim),
            ),
          ],
        ),
      ),
    );
  }
}
