import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_model.dart';
import 'package:kmstry_frontend/features/venue/data/external_partnership_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_offer_repository.dart';
import '../data/venue_event_repository.dart';

// ─── Brand colors ─────────────────────────────────────────────────────────────

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi    = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);

// ─── Page ─────────────────────────────────────────────────────────────────────

class AddVenueEventPage extends StatefulWidget {
  final String venueId;
  final VenueUpcomingEvent? existing;
  final String? editScope; // 'this' | 'thisAndFollowing' | 'all'

  const AddVenueEventPage({super.key, required this.venueId, this.existing, this.editScope});

  @override
  State<AddVenueEventPage> createState() => _AddVenueEventPageState();
}

class _AddVenueEventPageState extends State<AddVenueEventPage> {
  final _repo    = VenueEventRepository();
  final _partnershipRepo = ExternalPartnershipRepository();
  final _offerRepo = VenueOfferRepository();
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _capacityCtrl;

  DateTime? _startAt;
  DateTime? _endAt;
  List<String> _existingPhotos = [];
  final List<File> _newPhotos  = [];
  bool _saving = false;
  String _currency = 'TRY';

  // Partner Benefits
  List<ExternalPartnershipModel> _activePartnerships = [];
  final Set<String> _selectedPartnershipIds = {};
  bool _loadingPartnerships = true;

  // Event Offer
  bool _createOffer = false;
  VenueOfferType _offerType = VenueOfferType.BUFFET;
  late final TextEditingController _offerTitleCtrl;
  late final TextEditingController _offerDiscountCtrl;
  String? _existingOfferId; // for update in edit mode

  // Recurrence
  bool _repeatEnabled = false;
  String _repeatFreq  = 'weekly'; // 'weekly' | 'monthly' | 'yearly'
  int _repeatInterval = 1;
  String _repeatEndMode = 'date'; // 'date' | 'count'
  DateTime? _repeatEndsOn;
  int _repeatCount = 10;

  static const _currencies = ['TRY', 'USD', 'EUR', 'GBP', 'AED', 'SAR', 'AZN'];

  bool get _isEdit => widget.existing != null;
  int get _totalPhotos => _existingPhotos.length + _newPhotos.length;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleCtrl         = TextEditingController(text: e?.title ?? '');
    _descCtrl          = TextEditingController(text: e?.description ?? '');
    _priceCtrl         = TextEditingController(text: e?.priceAed != null ? '${e!.priceAed}' : '');
    _capacityCtrl      = TextEditingController(text: e?.capacity != null ? '${e!.capacity}' : '');
    _startAt           = e?.startAt;
    _endAt             = e?.endAt;
    _existingPhotos    = List.from(e?.photos ?? []);
    _currency          = e?.currency ?? 'TRY';

    // Pre-fill partner benefits (IDs from existing event)
    if (e != null) {
      for (final b in e.partnershipBenefits) {
        if (b.id.isNotEmpty) _selectedPartnershipIds.add(b.id);
      }
    }

    // Pre-fill offer (offerId/offerType olan event'te offer var — conditions opsiyonel)
    if (e != null && (e.offerId != null || e.offerType != null)) {
      _createOffer      = true;
      _existingOfferId  = e.offerId;
      _offerTitleCtrl   = TextEditingController(text: e.offerTitle ?? '');
      _offerType        = _parseOfferType(e.offerType);
      _offerDiscountCtrl = TextEditingController(
        text: e.offerPrice != null ? '${e.offerPrice!.toStringAsFixed(0)}' : '',
      );
    } else {
      _offerTitleCtrl    = TextEditingController();
      _offerDiscountCtrl = TextEditingController();
    }

    // Pre-fill recurrence
    if (e?.recurrence != null) {
      _repeatEnabled  = true;
      _repeatFreq     = e!.recurrence!.frequency;
      _repeatInterval = e.recurrence!.interval;
      if (e.recurrence!.endsOn != null) {
        _repeatEndMode = 'date';
        _repeatEndsOn  = e.recurrence!.endsOn;
      } else if (e.recurrence!.maxOccurrences != null) {
        _repeatEndMode = 'count';
        _repeatCount   = e.recurrence!.maxOccurrences!;
      }
    }

    _loadPartnerships();
  }

  VenueOfferType _parseOfferType(String? raw) {
    switch (raw) {
      case 'SET_MENU':   return VenueOfferType.SET_MENU;
      case 'OPEN_DRINK': return VenueOfferType.OPEN_DRINK;
      case 'OPEN_FOOD':  return VenueOfferType.OPEN_FOOD;
      case 'BUFFET':     return VenueOfferType.BUFFET;
      // Eski tipler (geriye dönük) — yeni event'lerde kullanılmıyor.
      case 'PERCENT_OFF':    return VenueOfferType.PERCENT_OFF;
      case 'FIXED_DISCOUNT': return VenueOfferType.FIXED_DISCOUNT;
      case 'FREE_ITEM':      return VenueOfferType.FREE_ITEM;
      case 'BUNDLE':         return VenueOfferType.BUNDLE;
      default:               return VenueOfferType.BUFFET;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _capacityCtrl.dispose();
    _offerTitleCtrl.dispose();
    _offerDiscountCtrl.dispose();
    super.dispose();
  }

  ThemeData _pickerTheme(BuildContext ctx, bool isDark) => Theme.of(ctx).copyWith(
        colorScheme: isDark
            ? const ColorScheme.dark(primary: _kTurkuaz, surface: Color(0xFF0D1A30))
            : ColorScheme.light(primary: _kTurkuaz),
      );

  /// Google Calendar tarzı: tek gün + start/end saat. End ≤ Start ise gece
  /// yarısını aşar (ertesi gün) — start ve end DateTime'larını buna göre kurar.
  void _applyDateTimes({DateTime? date, TimeOfDay? startTime, TimeOfDay? endTime}) {
    final base = date ?? _startAt ?? DateTime.now();
    final st = startTime ??
        (_startAt != null ? TimeOfDay.fromDateTime(_startAt!) : const TimeOfDay(hour: 20, minute: 0));
    final et = endTime ??
        (_endAt != null ? TimeOfDay.fromDateTime(_endAt!) : const TimeOfDay(hour: 23, minute: 0));

    var start = DateTime(base.year, base.month, base.day, st.hour, st.minute);
    var end = DateTime(base.year, base.month, base.day, et.hour, et.minute);
    if (!end.isAfter(start)) end = end.add(const Duration(days: 1)); // gece yarısını aşar
    setState(() {
      _startAt = start;
      _endAt = end;
    });
  }

  Future<void> _pickEventDate() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: _startAt ?? now,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(data: _pickerTheme(ctx, isDark), child: child!),
    );
    if (date == null || !mounted) return;
    _applyDateTimes(date: date);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final current = isStart ? _startAt : _endAt;
    final time = await showTimePicker(
      context: context,
      initialTime: current != null ? TimeOfDay.fromDateTime(current) : const TimeOfDay(hour: 20, minute: 0),
      builder: (ctx, child) => Theme(data: _pickerTheme(ctx, isDark), child: child!),
    );
    if (time == null || !mounted) return;
    if (isStart) {
      _applyDateTimes(startTime: time);
    } else {
      _applyDateTimes(endTime: time);
    }
  }

  Future<void> _pickPhoto() async {
    if (_totalPhotos >= 3) return;
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    setState(() => _newPhotos.add(File(picked.path)));
  }

  Future<void> _removeExistingPhoto(String url) async {
    try {
      await _repo.removePhoto(venueId: widget.venueId, eventId: widget.existing!.id, photoUrl: url);
      setState(() => _existingPhotos.remove(url));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not remove photo'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _showPartnershipSheet(
    Color kCard, Color kBorder, Color kText, Color kLabel, bool isDark,
  ) async {
    final selected = Set<String>.from(_selectedPartnershipIds);
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1525) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white12 : Colors.black12,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Icon(Icons.handshake_outlined, size: 18, color: _kMavi),
                    const SizedBox(width: 8),
                    Text('Deals and discounts',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
                    const Spacer(),
                    if (_activePartnerships.isNotEmpty &&
                        selected.length < _activePartnerships.length)
                      GestureDetector(
                        onTap: () => setSheet(() {
                          selected.addAll(_activePartnerships.map((p) => p.id));
                        }),
                        child: Text('Select all',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _kMavi)),
                      ),
                    if (selected.isNotEmpty) ...[
                      const SizedBox(width: 14),
                      GestureDetector(
                        onTap: () => setSheet(() => selected.clear()),
                        child: Text('Clear',
                            style: TextStyle(fontSize: 13, color: kLabel)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.55,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: _activePartnerships.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final p = _activePartnerships[i];
                    final isSelected = selected.contains(p.id);
                    return GestureDetector(
                      onTap: () => setSheet(() {
                        if (isSelected) selected.remove(p.id);
                        else selected.add(p.id);
                      }),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 130),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? _kMavi.withValues(alpha: 0.08) : kCard,
                          border: Border.all(
                            color: isSelected ? _kMavi : kBorder,
                            width: isSelected ? 1.5 : 1,
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 30, height: 30,
                              decoration: BoxDecoration(
                                color: _kMavi.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.handshake_outlined, size: 14, color: _kMavi),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.platformDisplayName,
                                      style: TextStyle(
                                        fontSize: 12, fontWeight: FontWeight.w700,
                                        color: isSelected ? _kMavi : kText,
                                      )),
                                  const SizedBox(height: 2),
                                  Text('${p.offerTypeDisplayName} · ${p.offerLabel}',
                                      style: TextStyle(fontSize: 11, color: kLabel),
                                      maxLines: 1, overflow: TextOverflow.ellipsis),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 130),
                              width: 20, height: 20,
                              decoration: BoxDecoration(
                                color: isSelected ? _kMavi : Colors.transparent,
                                border: Border.all(
                                  color: isSelected ? _kMavi : kBorder,
                                  width: 1.5,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      setState(() {
                        _selectedPartnershipIds
                          ..clear()
                          ..addAll(selected);
                      });
                      Navigator.pop(ctx);
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: _kMavi,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? 'None selected'
                          : 'Apply (${selected.length})',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadPartnerships() async {
    try {
      final all = await _partnershipRepo.getPartnerships(widget.venueId);
      if (!mounted) return;
      setState(() {
        _activePartnerships = all
            .where((p) => p.status == ExternalPartnershipStatus.ACTIVE)
            .toList();
        _loadingPartnerships = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingPartnerships = false);
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
      final priceText    = _priceCtrl.text.trim();
      final price        = priceText.isEmpty ? null : int.tryParse(priceText);
      final capacityText = _capacityCtrl.text.trim();
      final capacity     = capacityText.isEmpty ? null : int.tryParse(capacityText);
      String eventId;

      if (_isEdit) {
        Map<String, dynamic>? recurrencePayload;
        if (_repeatEnabled && widget.editScope != 'this') {
          recurrencePayload = {
            'frequency': _repeatFreq,
            'interval': _repeatInterval,
            if (_repeatEndMode == 'date' && _repeatEndsOn != null)
              'endsOn': _repeatEndsOn!.toUtc().toIso8601String(),
            if (_repeatEndMode == 'count')
              'maxOccurrences': _repeatCount,
          };
        }
        await _repo.updateEvent(
          venueId:      widget.venueId,
          eventId:      widget.existing!.id,
          title:        _titleCtrl.text.trim(),
          description:  _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          startAt:      _startAt,
          endAt:        _endAt,
          priceAed:     price,
          clearPrice:   priceText.isEmpty,
          currency:     _currency,
          capacity:     capacity,
          clearCapacity: capacityText.isEmpty,
          editScope:    widget.editScope,
          recurrence:   recurrencePayload,
        );
        eventId = widget.existing!.id;
        for (final photo in _newPhotos) {
          await _repo.uploadPhoto(venueId: widget.venueId, eventId: eventId, file: photo);
        }
      } else if (_repeatEnabled) {
        final recurrence = <String, dynamic>{
          'frequency': _repeatFreq,
          'interval': _repeatInterval,
          if (_repeatEndMode == 'date' && _repeatEndsOn != null)
            'endsOn': _repeatEndsOn!.toUtc().toIso8601String(),
          if (_repeatEndMode == 'count')
            'maxOccurrences': _repeatCount,
        };
        // Recurring: partnership/offer'ı backend tüm occurrence'lara uygular.
        // Conditions (title) opsiyonel — offer, _createOffer açıksa gönderilir.
        final recurringOffer = _createOffer
            ? <String, dynamic>{
                if (_offerTitleCtrl.text.trim().isNotEmpty)
                  'title': _offerTitleCtrl.text.trim(),
                'type': _offerType.name,
                if (_offerDiscountCtrl.text.isNotEmpty)
                  'price': double.tryParse(_offerDiscountCtrl.text),
              }
            : null;
        final createdSeries = await _repo.createEvent(
          venueId:    widget.venueId,
          title:      _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          startAt:    _startAt!,
          endAt:      _endAt!,
          priceAed:   price,
          currency:   _currency,
          capacity:   capacity,
          recurrence: recurrence,
          partnershipIds: _selectedPartnershipIds.isNotEmpty ? _selectedPartnershipIds.toList() : null,
          offer: recurringOffer,
        );
        // Foto'ları seriye yükle — backend tüm occurrence'lara uygular
        final ruleId = createdSeries['recurringRuleId']?.toString();
        if (ruleId != null && ruleId.isNotEmpty) {
          for (final photo in _newPhotos) {
            await _repo.uploadRecurringPhoto(venueId: widget.venueId, ruleId: ruleId, file: photo);
          }
        }
        eventId = ''; // recurring: occurrence'lar backend'de bağlandı, client-side attach yok
      } else {
        final created = await _repo.createEvent(
          venueId:     widget.venueId,
          title:       _titleCtrl.text.trim(),
          description: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
          startAt:     _startAt!,
          endAt:       _endAt!,
          priceAed:    price,
          currency:    _currency,
          capacity:    capacity,
        );
        eventId = created['id']?.toString() ?? '';
        for (final photo in _newPhotos) {
          await _repo.uploadPhoto(venueId: widget.venueId, eventId: eventId, file: photo);
        }
      }
      if (eventId.isNotEmpty && (_selectedPartnershipIds.isNotEmpty || _isEdit)) {
        try {
          await _partnershipRepo.setEventPartnerships(
            widget.venueId,
            eventId,
            _selectedPartnershipIds.toList(),
          );
        } catch (error) {
          if (isPublicTextRejection(error)) rethrow;
        }
      }
      if (eventId.isNotEmpty && _createOffer) {
        try {
          final body = {
            if (_offerTitleCtrl.text.trim().isNotEmpty)
              'title': _offerTitleCtrl.text.trim(),
            'type': _offerType.name,
            'event_id': eventId,
            if (_offerDiscountCtrl.text.isNotEmpty)
              'price': double.tryParse(_offerDiscountCtrl.text),
          };
          if (_existingOfferId != null) {
            await _offerRepo.update(widget.venueId, _existingOfferId!, body);
          } else {
            await _offerRepo.create(widget.venueId, body);
          }
        } catch (error) {
          if (isPublicTextRejection(error)) rethrow;
        }
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      await showPremiumErrorDialog(
        context,
        message: publicTextErrorMessage(
          error,
          fallback: 'Could not save event. Please try again.',
        ),
      );
    }
  }

  void _showError(String msg) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0D1525) : Colors.white,
            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5), width: 1.5),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.1),
                  blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFEF4444)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(msg,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827),
                    )),
              ),
            ],
          ),
        ),
      ));
  }

  String _formatDt(DateTime dt) {
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${days[(dt.weekday - 1) % 7]}, ${dt.day} ${months[dt.month - 1]} · $h:$m';
  }

  String _formatDate(DateTime dt) {
    const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${days[(dt.weekday - 1) % 7]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  String _formatTime(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

  /// End, start'tan sonraki güne mi taşıyor (gece yarısını aştı mı)?
  bool get _crossesMidnight =>
      _startAt != null && _endAt != null && _endAt!.day != _startAt!.day;

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final kBg      = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard    = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder  = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kDim     = isDark ? const Color(0xFFB1B4BB) : const Color(0xFF9CA3AF);
    final kText    = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kLabel   = isDark ? const Color(0xFFB1B4BB) : const Color(0xFF6B7280);

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
        title: Text(
          _isEdit ? 'Edit Event' : 'New Event',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
              letterSpacing: -0.3, color: kText),
        ),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 40),
          children: [

            // ── Event Title ────────────────────────────────────────────
            _SectionLabel(icon: Icons.title_rounded, color: _kTurkuaz, label: 'Event Title', kLabel: kLabel),
            const SizedBox(height: 8),
            _EventField(
              controller: _titleCtrl,
              hint: 'e.g. Saturday Night Live',
              maxLength: 120,
              kCard: kCard, kBorder: kBorder, kDim: kDim, kText: kText,
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Title is required' : null,
            ),

            const SizedBox(height: 16),

            // ── Description ────────────────────────────────────────────
            _SectionLabel(
              icon: Icons.align_horizontal_left_rounded, color: _kMavi,
              label: 'Description', optional: true, kLabel: kLabel,
            ),
            const SizedBox(height: 8),
            _EventField(
              controller: _descCtrl,
              hint: 'Tell guests what to expect…',
              maxLines: 4,
              maxLength: 1000,
              kCard: kCard, kBorder: kBorder, kDim: kDim, kText: kText,
            ),

            _divider(isDark),

            // ── Date & Time ────────────────────────────────────────────
            _SectionLabel(icon: Icons.event_outlined, color: _kTurkuaz, label: 'Date & Time', kLabel: kLabel),
            const SizedBox(height: 8),
            // Tek gün seçimi
            _DateBtn(
              label: 'DATE',
              value: _startAt != null ? _formatDate(_startAt!) : null,
              iconBg: _kTurkuaz.withValues(alpha: 0.15),
              iconColor: _kTurkuaz,
              icon: Icons.calendar_today_rounded,
              kCard: kCard, kBorder: kBorder, kText: kText,
              onTap: _pickEventDate,
            ),
            const SizedBox(height: 10),
            // Başlangıç / bitiş saati
            Row(
              children: [
                Expanded(
                  child: _DateBtn(
                    label: 'START TIME',
                    value: _startAt != null ? _formatTime(_startAt!) : null,
                    iconBg: _kTurkuaz.withValues(alpha: 0.15),
                    iconColor: _kTurkuaz,
                    icon: Icons.play_arrow_rounded,
                    kCard: kCard, kBorder: kBorder, kText: kText,
                    onTap: () => _pickTime(isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _DateBtn(
                    label: 'END TIME',
                    value: _endAt != null ? _formatTime(_endAt!) : null,
                    iconBg: _kTuruncu.withValues(alpha: 0.15),
                    iconColor: _kTuruncu,
                    icon: Icons.stop_rounded,
                    kCard: kCard, kBorder: kBorder, kText: kText,
                    onTap: () => _pickTime(isStart: false),
                  ),
                ),
              ],
            ),
            if (_crossesMidnight) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.nightlight_round, size: 13, color: kLabel),
                  const SizedBox(width: 6),
                  Text('Ends next day (+1)',
                      style: TextStyle(fontSize: 11.5, color: kLabel, fontWeight: FontWeight.w600)),
                ],
              ),
            ],

            _divider(isDark),

            // ── Entry Price ────────────────────────────────────────────
            _SectionLabel(
              icon: Icons.confirmation_num_outlined, color: _kTuruncu,
              label: 'Min. Spend', optional: true, kLabel: kLabel,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _EventField(
                    controller: _priceCtrl,
                    hint: '0 for free',
                    keyboardType: TextInputType.number,
                    kCard: kCard, kBorder: kBorder, kDim: kDim, kText: kText,
                  ),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () async {
                    final picked = await showModalBottomSheet<String>(
                      context: context,
                      backgroundColor: Colors.transparent,
                      builder: (ctx) => _CurrencySheet(
                        currencies: _currencies,
                        selected: _currency,
                        kCard: kCard, kText: kText,
                      ),
                    );
                    if (picked != null) setState(() => _currency = picked);
                  },
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: kCard,
                      border: Border.all(color: _kMavi, width: 1.5),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_currency,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                                color: _kMavi)),
                        const SizedBox(width: 5),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: _kMavi),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            _divider(isDark),

            // ── Capacity ───────────────────────────────────────────────
            _SectionLabel(
              icon: Icons.people_outline_rounded, color: _kTurkuaz,
              label: 'Capacity', optional: true, kLabel: kLabel,
            ),
            const SizedBox(height: 8),
            _EventField(
              controller: _capacityCtrl,
              hint: 'Leave empty for unlimited',
              keyboardType: TextInputType.number,
              kCard: kCard, kBorder: kBorder, kDim: kDim, kText: kText,
            ),

            _divider(isDark),

            // ── Photos ─────────────────────────────────────────────────
            _SectionLabel(icon: Icons.add_photo_alternate_outlined, color: _kMagenta, label: 'Photos', kLabel: kLabel),
            const SizedBox(height: 8),
            Row(
              children: [
                // Existing photos
                ..._existingPhotos.map((url) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(url, width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => _removeExistingPhoto(url),
                        child: _closeCircle(),
                      ),
                    ),
                  ]),
                )),
                // New photos
                ..._newPhotos.asMap().entries.map((e) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Stack(children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.file(e.value, width: 80, height: 80, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 4, right: 4,
                      child: GestureDetector(
                        onTap: () => setState(() => _newPhotos.removeAt(e.key)),
                        child: _closeCircle(),
                      ),
                    ),
                  ]),
                )),
                // Empty slots
                ...List.generate(3 - _totalPhotos, (i) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: _pickPhoto,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        color: kCard,
                        border: Border.all(color: kBorder, width: 1.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_rounded, size: 22, color: kDim),
                          const SizedBox(height: 4),
                          Text('Add', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: kDim)),
                        ],
                      ),
                    ),
                  ),
                )),
              ],
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Text('Up to 3 photos',
                  style: TextStyle(fontSize: 10.5, color: isDark ? const Color(0xFFB1B4BB) : const Color(0xFFB0B8C8))),
            ),

            _divider(isDark),

            // ── Partner Benefits ────────────────────────────────────────
            _SectionLabel(
              icon: Icons.handshake_outlined,
              color: _kMavi,
              label: 'Deals and discounts',
              optional: true,
              kLabel: kLabel,
            ),
            const SizedBox(height: 4),
            Text(
              'Select the partnerships you want to offer at this event.',
              style: TextStyle(fontSize: 11.5, height: 1.35, color: kDim.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 8),
            if (_loadingPartnerships)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _kMavi),
                    ),
                    const SizedBox(width: 10),
                    Text('Loading partnerships…', style: TextStyle(fontSize: 12, color: kLabel)),
                  ],
                ),
              )
            else if (_activePartnerships.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                decoration: BoxDecoration(
                  color: kCard,
                  border: Border.all(color: kBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: kLabel),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'No active partnerships. Add them from Offers & Benefits.',
                        style: TextStyle(fontSize: 11.5, color: kLabel),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              // Tappable summary row → opens bottom sheet
              GestureDetector(
                onTap: () => _showPartnershipSheet(kCard, kBorder, kText, kLabel, isDark),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                  decoration: BoxDecoration(
                    color: _selectedPartnershipIds.isNotEmpty
                        ? _kMavi.withValues(alpha: 0.07)
                        : kCard,
                    border: Border.all(
                      color: _selectedPartnershipIds.isNotEmpty ? _kMavi : kBorder,
                      width: _selectedPartnershipIds.isNotEmpty ? 1.5 : 1,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _kMavi.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.handshake_outlined, size: 14, color: _kMavi),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _selectedPartnershipIds.isEmpty
                              ? 'Select partner benefits…'
                              : '${_selectedPartnershipIds.length} benefit${_selectedPartnershipIds.length > 1 ? 's' : ''} selected',
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600,
                            color: _selectedPartnershipIds.isNotEmpty ? _kMavi : kLabel,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded, size: 18, color: kLabel),
                    ],
                  ),
                ),
              ),
              // Selected badges
              if (_selectedPartnershipIds.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _activePartnerships
                      .where((p) => _selectedPartnershipIds.contains(p.id))
                      .map((p) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                            decoration: BoxDecoration(
                              color: _kMavi.withValues(alpha: 0.10),
                              border: Border.all(color: _kMavi.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(p.platformDisplayName,
                                    style: const TextStyle(
                                        fontSize: 11, fontWeight: FontWeight.w700, color: _kMavi)),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () => setState(() => _selectedPartnershipIds.remove(p.id)),
                                  child: const Icon(Icons.close_rounded, size: 12, color: _kMavi),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              ],
            ],

            _divider(isDark),

            // ── Event Offer ─────────────────────────────────────────────
            Row(
              children: [
                Container(
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    color: _kTuruncu.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: const Icon(Icons.local_offer_outlined, size: 15, color: _kTuruncu),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('EVENT OFFER',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                            letterSpacing: 1.2, color: _kTuruncu)),
                    Text('optional',
                        style: TextStyle(fontSize: 10, color: kLabel.withValues(alpha: 0.8))),
                  ],
                ),
                const Spacer(),
                Switch.adaptive(
                  value: _createOffer,
                  onChanged: (v) => setState(() => _createOffer = v),
                  activeColor: _kTuruncu,
                ),
              ],
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: _createOffer ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(height: 0),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF0D1525) : const Color(0xFFF0F4FA),
                      border: Border.all(color: _kTuruncu.withValues(alpha: 0.25), width: 1.5),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Offer type',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            (VenueOfferType.BUFFET, 'Buffet'),
                            (VenueOfferType.SET_MENU, 'Set Menu'),
                            (VenueOfferType.OPEN_DRINK, 'Open Drink'),
                            (VenueOfferType.OPEN_FOOD, 'Open Food'),
                          ].map((o) => GestureDetector(
                            onTap: () => setState(() => _offerType = o.$1),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: _offerType == o.$1 ? _kTuruncu.withValues(alpha: 0.12) : kCard,
                                border: Border.all(
                                  color: _offerType == o.$1 ? _kTuruncu : kBorder,
                                  width: _offerType == o.$1 ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(o.$2,
                                  style: TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w600,
                                    color: _offerType == o.$1 ? _kTuruncu : kLabel,
                                  )),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 14),
                        Text('Offer conditions',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
                        const SizedBox(height: 4),
                        Text('Optional — describe any conditions for this offer.',
                            style: TextStyle(fontSize: 11, color: kDim.withValues(alpha: 0.82))),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _offerTitleCtrl,
                          style: TextStyle(fontSize: 13, color: kText),
                          decoration: InputDecoration(
                            hintText: 'e.g. Valid until 22:00, min 2 guests',
                            hintStyle: TextStyle(fontSize: 13, color: kDim.withValues(alpha: 0.72)),
                            filled: true,
                            fillColor: kCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: kBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: kBorder),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('Price',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kText)),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _offerDiscountCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(fontSize: 13, color: kText),
                          decoration: InputDecoration(
                            hintText: 'e.g. 150',
                            hintStyle: TextStyle(fontSize: 13, color: kDim.withValues(alpha: 0.72)),
                            filled: true,
                            fillColor: kCard,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: kBorder),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(color: kBorder),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),

            // ── Recurring info (edit mode) ─────────────────────────────
            if (_isEdit && (widget.existing?.isRecurring ?? false)) ...[
              _divider(isDark),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _kMagenta.withValues(alpha: 0.06),
                  border: Border.all(color: _kMagenta.withValues(alpha: 0.22), width: 1.5),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: _kMagenta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(Icons.repeat_rounded, size: 16, color: _kMagenta),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Recurring Event',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kMagenta)),
                          const SizedBox(height: 2),
                          Text(
                            widget.editScope == 'this'
                                ? 'Editing only this occurrence'
                                : widget.editScope == 'thisAndFollowing'
                                    ? 'Editing this and future occurrences'
                                    : widget.editScope == 'all'
                                        ? 'Editing all occurrences'
                                        : 'Part of a recurring series',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500,
                                color: kLabel),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

            if (widget.editScope != 'this') ...[
              _divider(isDark),

              // ── Repeat section header ───────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: _kMagenta.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.repeat_rounded, size: 15, color: _kMagenta),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('REPEAT',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
                              letterSpacing: 1.2, color: _kMagenta)),
                      Text('optional',
                          style: TextStyle(fontSize: 10, color: kLabel.withValues(alpha: 0.8))),
                    ],
                  ),
                  const Spacer(),
                  Switch.adaptive(
                    value: _repeatEnabled,
                    onChanged: (v) => setState(() => _repeatEnabled = v),
                    activeColor: _kMagenta,
                  ),
                ],
              ),

              AnimatedCrossFade(
                duration: const Duration(milliseconds: 250),
                crossFadeState: _repeatEnabled ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(height: 0),
                secondChild: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 14),

                    // ── Repeat card ───────────────────────────────────────
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF0D1525) : const Color(0xFFF0F4FA),
                        border: Border.all(color: _kMagenta.withValues(alpha: 0.25), width: 1.5),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Column(
                        children: [
                          // Frequency buttons
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                            child: Row(
                              children: [
                                _FreqBtn(label: 'Weekly',  icon: Icons.view_week_rounded,     active: _repeatFreq == 'weekly',  onTap: () => setState(() => _repeatFreq = 'weekly'),  kCard: kCard, kBorder: kBorder),
                                const SizedBox(width: 8),
                                _FreqBtn(label: 'Monthly', icon: Icons.calendar_month_rounded, active: _repeatFreq == 'monthly', onTap: () => setState(() => _repeatFreq = 'monthly'), kCard: kCard, kBorder: kBorder),
                                const SizedBox(width: 8),
                                _FreqBtn(label: 'Yearly',  icon: Icons.calendar_today_rounded, active: _repeatFreq == 'yearly',  onTap: () => setState(() => _repeatFreq = 'yearly'),  kCard: kCard, kBorder: kBorder),
                              ],
                            ),
                          ),

                          _cardDiv(isDark),

                          // Interval row
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: const TextStyle(fontSize: 12.5),
                                      children: [
                                        TextSpan(text: 'Repeat every ',
                                            style: TextStyle(color: isDark ? const Color(0xFF8AA8CC) : const Color(0xFF6B7280), fontWeight: FontWeight.w500)),
                                        TextSpan(text: '$_repeatInterval',
                                            style: TextStyle(color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827), fontWeight: FontWeight.w800)),
                                        TextSpan(
                                          text: ' ${_repeatFreq == 'weekly' ? 'week' : _repeatFreq == 'monthly' ? 'month' : 'year'}(s)',
                                          style: TextStyle(color: isDark ? const Color(0xFF8AA8CC) : const Color(0xFF6B7280), fontWeight: FontWeight.w500),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                _InlineStepper(
                                  value: _repeatInterval,
                                  color: _kMagenta,
                                  onDecrement: () { if (_repeatInterval > 1) setState(() => _repeatInterval--); },
                                  onIncrement: () { if (_repeatInterval < 52) setState(() => _repeatInterval++); },
                                ),
                              ],
                            ),
                          ),

                          _cardDiv(isDark),

                          // End type section
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text('ENDS',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                                          letterSpacing: 0.8,
                                          color: isDark ? const Color(0xFFB1B4BB) : const Color(0xFF9CA3AF))),
                                ),

                                Row(
                                  children: [
                                    _EndModeBtn(
                                      label: 'Until date',
                                      icon: Icons.calendar_month_outlined,
                                      active: _repeatEndMode == 'date',
                                      activeColor: _kTurkuaz,
                                      onTap: () => setState(() => _repeatEndMode = 'date'),
                                      kCard: kCard, kBorder: kBorder,
                                    ),
                                    const SizedBox(width: 8),
                                    _EndModeBtn(
                                      label: 'After N times',
                                      icon: Icons.tag_rounded,
                                      active: _repeatEndMode == 'count',
                                      activeColor: _kMavi,
                                      onTap: () => setState(() => _repeatEndMode = 'count'),
                                      kCard: kCard, kBorder: kBorder,
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 10),

                                AnimatedCrossFade(
                                  duration: const Duration(milliseconds: 180),
                                  crossFadeState: _repeatEndMode == 'date' ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                                  firstChild: GestureDetector(
                                    onTap: () async {
                                      final now = DateTime.now();
                                      final date = await showDatePicker(
                                        context: context,
                                        initialDate: _repeatEndsOn ?? now.add(const Duration(days: 30)),
                                        firstDate: _startAt ?? now,
                                        lastDate: now.add(const Duration(days: 365 * 3)),
                                        builder: (ctx, child) => Theme(
                                          data: Theme.of(ctx).copyWith(
                                            colorScheme: isDark
                                                ? const ColorScheme.dark(primary: _kTurkuaz, surface: Color(0xFF0D1A30))
                                                : ColorScheme.light(primary: _kTurkuaz),
                                          ),
                                          child: child!,
                                        ),
                                      );
                                      if (date != null) setState(() => _repeatEndsOn = date);
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: _repeatEndsOn != null ? _kTurkuaz.withValues(alpha: 0.08) : kCard,
                                        border: Border.all(color: _repeatEndsOn != null ? _kTurkuaz : kBorder, width: 1.5),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(Icons.calendar_today_rounded, size: 14, color: _kTurkuaz),
                                          const SizedBox(width: 8),
                                          Text(
                                            _repeatEndsOn != null
                                                ? '${_repeatEndsOn!.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_repeatEndsOn!.month - 1]} ${_repeatEndsOn!.year}'
                                                : 'Select end date',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                                color: _repeatEndsOn != null
                                                    ? (isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827))
                                                    : (isDark ? const Color(0xFFB1B4BB) : const Color(0xFF9CA3AF))),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  secondChild: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                    decoration: BoxDecoration(
                                      color: _kMavi.withValues(alpha: 0.07),
                                      border: Border.all(color: _kMavi.withValues(alpha: 0.18), width: 1),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: RichText(
                                            text: TextSpan(
                                              style: const TextStyle(fontSize: 12.5),
                                              children: [
                                                TextSpan(text: 'After ',
                                                    style: TextStyle(color: isDark ? const Color(0xFF8AA8CC) : const Color(0xFF6B7280))),
                                                TextSpan(text: '$_repeatCount',
                                                    style: TextStyle(color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827), fontWeight: FontWeight.w800)),
                                                TextSpan(text: ' occurrences',
                                                    style: TextStyle(color: isDark ? const Color(0xFF8AA8CC) : const Color(0xFF6B7280))),
                                              ],
                                            ),
                                          ),
                                        ),
                                        _InlineStepper(
                                          value: _repeatCount,
                                          color: _kMavi,
                                          onDecrement: () { if (_repeatCount > 1) setState(() => _repeatCount--); },
                                          onIncrement: () { if (_repeatCount < 500) setState(() => _repeatCount++); },
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Summary pill
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                      decoration: BoxDecoration(
                        color: _kMagenta.withValues(alpha: 0.07),
                        border: Border.all(color: _kMagenta.withValues(alpha: 0.18), width: 1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 1),
                            child: Icon(Icons.info_outline_rounded, size: 15, color: _kMagenta),
                          ),
                          const SizedBox(width: 9),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(fontSize: 12, height: 1.5),
                                children: [
                                  const TextSpan(text: 'Repeats ',
                                      style: TextStyle(color: Color(0xFF7A3060))),
                                  TextSpan(
                                    text: 'every ${_repeatInterval > 1 ? '$_repeatInterval ' : ''}${_repeatFreq == 'weekly' ? 'week' : _repeatFreq == 'monthly' ? 'month' : 'year'}${_repeatInterval > 1 ? 's' : ''}',
                                    style: const TextStyle(color: _kMagenta, fontWeight: FontWeight.w700),
                                  ),
                                  if (_repeatEndMode == 'count') ...[
                                    const TextSpan(text: ' and ends after ',
                                        style: TextStyle(color: Color(0xFF7A3060))),
                                    TextSpan(text: '$_repeatCount occurrences',
                                        style: const TextStyle(color: _kMagenta, fontWeight: FontWeight.w700)),
                                    TextSpan(text: ' · $_repeatCount events will be created',
                                        style: const TextStyle(color: Color(0xFF7A3060))),
                                  ] else if (_repeatEndMode == 'date' && _repeatEndsOn != null) ...[
                                    const TextSpan(text: ' until ',
                                        style: TextStyle(color: Color(0xFF7A3060))),
                                    TextSpan(
                                      text: '${_repeatEndsOn!.day} ${['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'][_repeatEndsOn!.month - 1]} ${_repeatEndsOn!.year}',
                                      style: const TextStyle(color: _kMagenta, fontWeight: FontWeight.w700),
                                    ),
                                  ] else ...[
                                    const TextSpan(text: ' · set an end date or count',
                                        style: TextStyle(color: Color(0xFF7A3060))),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: PrimaryButton(
            label: _isEdit ? 'Save Changes' : 'Publish Event',
            onPressed: _saving ? null : () => _save(),
            loading: _saving,
          ),
        ),
      ),
    );
  }

  Widget _cardDiv(bool isDark) => Container(
    height: 1,
    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.05),
  );

  Widget _divider(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.transparent,
          isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.07),
          Colors.transparent,
        ]),
      ),
    ),
  );

  Widget _closeCircle() => Container(
    width: 20, height: 20,
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), shape: BoxShape.circle),
    child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
  );
}

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final bool optional;
  final Color kLabel;

  const _SectionLabel({
    required this.icon,
    required this.color,
    required this.label,
    required this.kLabel,
    this.optional = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800,
              letterSpacing: 1, color: kLabel),
        ),
        if (optional) ...[
          const SizedBox(width: 6),
          Text('optional',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w400,
                  letterSpacing: 0, color: kLabel.withValues(alpha: 0.8),
                  textBaseline: TextBaseline.alphabetic)),
        ],
      ],
    );
  }
}

// ─── Text field ───────────────────────────────────────────────────────────────

class _EventField extends StatelessWidget {
  final TextEditingController controller;
  final String? hint;
  final int maxLines;
  final int? maxLength;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final Color kCard;
  final Color kBorder;
  final Color kDim;
  final Color kText;

  const _EventField({
    required this.controller,
    required this.kCard,
    required this.kBorder,
    required this.kDim,
    required this.kText,
    this.hint,
    this.maxLines = 1,
    this.maxLength,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      maxLength: maxLength,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(fontSize: 14, color: kText),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: kDim.withValues(alpha: 0.72)),
        counterStyle: TextStyle(color: kDim.withValues(alpha: 0.78), fontSize: 10),
        filled: true,
        fillColor: kCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kBorder, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: kBorder, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: _kTurkuaz, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5)),
      ),
    );
  }
}

// ─── Date button ──────────────────────────────────────────────────────────────

class _DateBtn extends StatelessWidget {
  final String label;
  final String? value;
  final Color iconBg;
  final Color iconColor;
  final IconData icon;
  final Color kCard;
  final Color kBorder;
  final Color kText;
  final VoidCallback onTap;

  const _DateBtn({
    required this.label,
    required this.value,
    required this.iconBg,
    required this.iconColor,
    required this.icon,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasVal = value != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(
            color: hasVal ? _kTurkuaz : kBorder,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, size: 15, color: iconColor),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                          color: kBorder == const Color(0xFF162040)
                              ? const Color(0xFFB1B4BB)
                              : const Color(0xFF9CA3AF))),
                  const SizedBox(height: 1),
                  Text(
                    value ?? 'Tap to set',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: hasVal ? FontWeight.w600 : FontWeight.w400,
                      color: hasVal ? kText : const Color(0xFFB1B4BB),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Currency Sheet ───────────────────────────────────────────────────────────

class _CurrencySheet extends StatelessWidget {
  final List<String> currencies;
  final String selected;
  final Color kCard;
  final Color kText;

  const _CurrencySheet({
    required this.currencies,
    required this.selected,
    required this.kCard,
    required this.kText,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(
                  color: colors.outline.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text('Currency',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
          ),
          const SizedBox(height: 8),
          Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: currencies.length,
            separatorBuilder: (_, __) =>
                Divider(height: 1, color: colors.outline.withValues(alpha: 0.1)),
            itemBuilder: (_, i) {
              final c = currencies[i];
              final isSelected = c == selected;
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                title: Text(c,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      color: isSelected ? AppColors.blue : kText,
                    )),
                trailing: isSelected
                    ? const Icon(Icons.check_rounded, color: AppColors.blue, size: 20)
                    : null,
                onTap: () => Navigator.pop(context, c),
              );
            },
          )),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Frequency button ─────────────────────────────────────────────────────────

class _FreqBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  final Color kCard;
  final Color kBorder;

  const _FreqBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    required this.kCard,
    required this.kBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? _kMagenta.withValues(alpha: 0.12) : kCard,
            border: Border.all(color: active ? _kMagenta : kBorder, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: active ? _kMagenta : const Color(0xFFB1B4BB)),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: active ? _kMagenta : const Color(0xFFB1B4BB),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── End mode button ──────────────────────────────────────────────────────────

class _EndModeBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;
  final Color kCard;
  final Color kBorder;

  const _EndModeBtn({
    required this.label,
    required this.icon,
    required this.active,
    required this.activeColor,
    required this.onTap,
    required this.kCard,
    required this.kBorder,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? activeColor.withValues(alpha: 0.10) : kCard,
            border: Border.all(color: active ? activeColor : kBorder, width: 1.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? activeColor : const Color(0xFFB1B4BB)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                    fontSize: 11.5, fontWeight: FontWeight.w700,
                    color: active ? activeColor : const Color(0xFFB1B4BB),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Inline stepper (− value +) ───────────────────────────────────────────────

class _InlineStepper extends StatelessWidget {
  final int value;
  final Color color;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;

  const _InlineStepper({
    required this.value,
    required this.color,
    required this.onDecrement,
    required this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onDecrement,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.remove_rounded, size: 18, color: color),
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: Color(0xFFEEF2FF))),
        ),
        GestureDetector(
          onTap: onIncrement,
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.add_rounded, size: 18, color: color),
          ),
        ),
      ],
    );
  }
}

// ─── Counter button ───────────────────────────────────────────────────────────

class _CounterBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color kBorder;
  final Color kCard;

  const _CounterBtn({
    required this.icon,
    required this.onTap,
    required this.kBorder,
    required this.kCard,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: kBorder, width: 1.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: const Color(0xFF8DA0BD)),
      ),
    );
  }
}

// ─── Discount button ──────────────────────────────────────────────────────────

class _DiscountBtn extends StatelessWidget {
  final String value;
  final String selected;
  final IconData icon;
  final String label;
  final Color kCard;
  final Color kBorder;
  final VoidCallback onTap;

  const _DiscountBtn({
    required this.value,
    required this.selected,
    required this.icon,
    required this.label,
    required this.kCard,
    required this.kBorder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = value == selected;
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? _kTurkuaz.withValues(alpha: 0.08) : kCard,
            border: Border.all(
              color: isActive ? _kTurkuaz : kBorder,
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18,
                  color: isActive ? _kTurkuaz : const Color(0xFFB1B4BB)),
              const SizedBox(height: 5),
              Text(label,
                  style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: isActive ? _kTurkuaz : const Color(0xFFB1B4BB),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
