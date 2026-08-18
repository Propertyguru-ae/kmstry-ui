import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'add_venue_event_page.dart';
import '../data/venue_event_repository.dart';

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi    = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed     = Color(0xFFEF4444);

class VenueEventDetailPage extends StatefulWidget {
  final VenueUpcomingEvent event;
  final String venueId;
  final VoidCallback? onChanged;

  const VenueEventDetailPage({
    super.key,
    required this.event,
    required this.venueId,
    this.onChanged,
  });

  @override
  State<VenueEventDetailPage> createState() => _VenueEventDetailPageState();
}

class _VenueEventDetailPageState extends State<VenueEventDetailPage> {
  late VenueUpcomingEvent _event;

  /// EVENT_ATTENDEES_VIEW yetkisi olan kullanıcılar için katılımcı listesi.
  List<Map<String, dynamic>>? _attendees;
  bool _loadingAttendees = false;

  bool get _canViewAttendees =>
      VenueSession.instance.can(VenuePermission.eventAttendeesView);

  @override
  void initState() {
    super.initState();
    _event = widget.event;
    if (_canViewAttendees) _loadAttendees();
  }

  Future<void> _loadAttendees() async {
    if (_loadingAttendees) return;
    setState(() => _loadingAttendees = true);
    try {
      final list = await VenueEventRepository().getEventRsvps(
        venueId: widget.venueId,
        eventId: _event.id,
      );
      if (mounted) setState(() => _attendees = list);
    } catch (_) {
      if (mounted) setState(() => _attendees = const []);
    } finally {
      if (mounted) setState(() => _loadingAttendees = false);
    }
  }

  Future<void> _reloadEvent() async {
    try {
      // Tek event'i dedike endpoint'ten çekiyoruz — getVenueById listesi
      // is_published+end_at>now+take:5 ile filtreli olduğundan güncel event'i kaçırabilir.
      final updated = await VenueEventRepository().getEventDetail(
        venueId: widget.venueId,
        eventId: _event.id,
      );
      if (mounted) setState(() => _event = updated);
    } catch (_) {}
    if (_canViewAttendees) _loadAttendees();
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final event    = _event;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final kBg      = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard    = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder  = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText    = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    // Açıklama gövde metni için okunaklı, daha yüksek kontrastlı renk.
    final kBody    = isDark ? const Color(0xFFB8C4DA) : const Color(0xFF334155);
    final kDim     = isDark ? const Color(0xFF9AA8C2) : const Color(0xFF5D6B7B);
    final kLabel   = isDark ? const Color(0xFF44597A) : const Color(0xFF8794A6);
    final kFaint   = isDark ? const Color(0xFF3A5070) : const Color(0xFF9AA6B6);
    final canManage = VenueSession.instance.can(VenuePermission.eventManage);

    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);
    final coverPhoto = photos.isNotEmpty ? photos.first : null;
    final isFree = event.priceAed == null || event.priceAed == 0;
    final isFull = event.capacity != null && event.rsvpCount >= event.capacity!;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: kBg,
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── COVER HERO ─────────────────────────────────────────────
                _EventCover(photo: coverPhoto, pageBg: kBg),

                // ── TITLE + CHIPS (cover'a biner) ──────────────────────────
                Transform.translate(
                  offset: const Offset(0, -36),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: kText,
                            height: 1.15,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 7,
                          runSpacing: 7,
                          children: [
                            _InfoChip(
                              icon: isFree
                                  ? Icons.confirmation_num_outlined
                                  : Icons.local_activity_outlined,
                              label: isFree
                                  ? 'Free entry'
                                  : '${event.currency} ${event.priceAed} min.',
                              color: isFree ? _kTurkuaz : _kTuruncu,
                              isDark: isDark,
                            ),
                            if (event.isRecurring)
                              _InfoChip(
                                icon: Icons.repeat_rounded,
                                label: 'Recurring',
                                color: _kMagenta,
                                isDark: isDark,
                              ),
                            if (event.capacity != null || event.rsvpCount > 0)
                              _InfoChip(
                                icon: Icons.people_outline_rounded,
                                label: event.capacity != null
                                    ? '${event.rsvpCount} / ${event.capacity}'
                                    : '${event.rsvpCount} attending',
                                color: isFull ? _kRed : _kMavi,
                                isDark: isDark,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── CONTENT ────────────────────────────────────────────────
                Transform.translate(
                  offset: const Offset(0, -20),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // DATE & TIME
                        _InfoCard(
                          icon: Icons.calendar_month_rounded,
                          accent: _kTurkuaz,
                          label: 'Date & Time',
                          value: event.formattedDate,
                          sub: _durationLabel(
                            event.endAt.difference(event.startAt),
                          ),
                          kCard: kCard,
                          kBorder: kBorder,
                          kText: kText,
                          kLabel: kLabel,
                          kFaint: kFaint,
                        ),
                        const SizedBox(height: 10),

                        // ENTRY
                        _InfoCard(
                          icon: Icons.local_activity_rounded,
                          accent: _kTuruncu,
                          label: 'Entry',
                          value: isFree
                              ? 'Free · No ticket required'
                              : '${event.currency} ${event.priceAed} minimum spend',
                          kCard: kCard,
                          kBorder: kBorder,
                          kText: kText,
                          kLabel: kLabel,
                          kFaint: kFaint,
                        ),

                        // RECURRING BANNER
                        if (event.isRecurring) ...[
                          const SizedBox(height: 14),
                          _RecurringBanner(label: _recurrenceLabel(event)),
                        ],

                        // ABOUT
                        if (event.description != null &&
                            event.description!.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _DotTitle(color: _kMagenta, label: 'About', kText: kText),
                          const SizedBox(height: 8),
                          Text(
                            event.description!,
                            style: TextStyle(
                              fontSize: 14,
                              color: kBody,
                              height: 1.7,
                            ),
                          ),
                        ],

                        // KMSTRY OFFER
                        if (event.offerType != null) ...[
                          const SizedBox(height: 20),
                          _DotTitle(
                            color: _kTuruncu,
                            label: 'Kmstry Offer',
                            kText: kText,
                          ),
                          const SizedBox(height: 8),
                          _OfferCard(
                            conditions: event.offerTitle,
                            type: event.offerType,
                            price: event.offerPrice,
                            isDark: isDark,
                            kCard: kCard,
                            kBorder: kBorder,
                            kText: kText,
                            kDim: kDim,
                          ),
                        ],

                        // ATTENDEES
                        if (_canViewAttendees &&
                            (event.capacity != null ||
                                event.rsvpCount > 0)) ...[
                          const SizedBox(height: 20),
                          _DotTitle(
                            color: _kTurkuaz,
                            label: 'Attendees',
                            kText: kText,
                            count: _attendees?.length ?? event.rsvpCount,
                          ),
                          const SizedBox(height: 12),
                          _AttendeeList(
                            attendees: _attendees,
                            loading: _loadingAttendees,
                            isDark: isDark,
                            kCard: kCard,
                            kBorder: kBorder,
                            kText: kText,
                          ),
                        ],

                        // PARTNER BENEFITS
                        if (event.partnershipBenefits.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _DotTitle(
                            color: _kMavi,
                            label: 'Partner Benefits',
                            kText: kText,
                          ),
                          const SizedBox(height: 10),
                          ...event.partnershipBenefits.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _BenefitCard(
                                benefit: b,
                                isDark: isDark,
                                kCard: kCard,
                                kBorder: kBorder,
                                kText: kText,
                                kDim: kDim,
                              ),
                            ),
                          ),
                        ],

                        // GALLERY
                        if (photos.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          _DotTitle(
                            color: _kMagenta,
                            label: 'Gallery',
                            kText: kText,
                          ),
                          const SizedBox(height: 10),
                          _Gallery(photos: photos),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Floating back button ───────────────────────────────────────
          Positioned(
            top: topInset + 8,
            left: 14,
            child: AppBackButton.onCover(onTap: () => Navigator.pop(context)),
          ),

          // ── Edit / delete (owner) ──────────────────────────────────────
          if (canManage)
            Positioned(
              top: topInset + 8,
              right: 14,
              child: Row(
                children: [
                  _coverCircleButton(
                    Icons.edit_outlined,
                    _kTurkuaz,
                    () => _openEdit(
                      context, isDark, kBg, kCard, kBorder, kText, kDim,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _coverCircleButton(
                    Icons.delete_outline_rounded,
                    _kRed,
                    () => _confirmDelete(context, isDark),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _coverCircleButton(IconData icon, Color iconColor, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.38),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 16, color: iconColor),
        ),
      ),
    );
  }

  String _durationLabel(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h <= 0 && m <= 0) return '';
    if (h > 0 && m > 0) return 'Duration: ${h}h ${m}m';
    if (h > 0) return 'Duration: $h hour${h > 1 ? 's' : ''}';
    return 'Duration: ${m}m';
  }

  String _recurrenceLabel(VenueUpcomingEvent event) {
    final freq = event.recurrence?.frequency.toLowerCase();
    switch (freq) {
      case 'daily':
        return 'Repeats every day';
      case 'weekly':
        return 'Repeats every week';
      case 'monthly':
        return 'Repeats every month';
      default:
        return 'This is a recurring event';
    }
  }

  Future<void> _openEdit(
    BuildContext context, bool isDark,
    Color kBg, Color kCard, Color kBorder, Color kText, Color kDim,
  ) async {
    String? editScope;
    if (_event.isRecurring) {
      editScope = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditScopeSheet(
          event: _event, isDark: isDark,
          kBg: kBg, kCard: kCard, kBorder: kBorder, kText: kText, kDim: kDim,
        ),
      );
      if (editScope == null || !context.mounted) return;
    }
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddVenueEventPage(
          venueId: widget.venueId,
          existing: _event,
          editScope: editScope,
        ),
      ),
    );
    if (result == true && context.mounted) {
      await _reloadEvent();
    }
  }

  Future<void> _confirmDelete(BuildContext context, bool isDark) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0B1322) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Event',
            style: TextStyle(
              fontSize: 16, fontWeight: FontWeight.w800,
              color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827),
            )),
        content: Text(
          '"${_event.title}" will be permanently deleted.',
          style: TextStyle(
            fontSize: 13,
            color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(
                    color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete',
                style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await VenueEventRepository().deleteEvent(venueId: widget.venueId, eventId: _event.id);
      if (context.mounted) {
        widget.onChanged?.call();
        Navigator.pop(context, true);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not delete event'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

}

// ─── Info chip ────────────────────────────────────────────────────────────────

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              )),
        ],
      ),
    );
  }
}

// ─── Cover hero ─────────────────────────────────────────────────────────────

class _EventCover extends StatelessWidget {
  final String? photo;
  final Color pageBg;
  const _EventCover({required this.photo, required this.pageBg});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 210,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo != null && photo!.isNotEmpty)
            CachedImage(photo!, fit: BoxFit.cover)
          else ...[
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1A0828), Color(0xFF0A1840), Color(0xFF0A2010)],
                ),
              ),
            ),
            Align(
              alignment: const Alignment(-0.5, -0.2),
              child: _glow(_kMagenta.withValues(alpha: 0.22), 240),
            ),
            Align(
              alignment: const Alignment(0.6, 0.4),
              child: _glow(_kTurkuaz.withValues(alpha: 0.16), 220),
            ),
          ],
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, pageBg],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glow(Color color, double size) => IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color, color.withValues(alpha: 0)],
            ),
          ),
        ),
      );
}

// ─── Info card (Date & Time, Entry) ───────────────────────────────────────────

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? sub;
  final Color kCard, kBorder, kText, kLabel, kFaint;

  const _InfoCard({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.sub,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kLabel,
    required this.kFaint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 17, color: accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: kLabel,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
                if (sub != null && sub!.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(sub!, style: TextStyle(fontSize: 11, color: kFaint)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Recurring banner ─────────────────────────────────────────────────────────

class _RecurringBanner extends StatelessWidget {
  final String label;
  const _RecurringBanner({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _kMagenta.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kMagenta.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          const Icon(Icons.repeat_rounded, size: 16, color: _kMagenta),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: _kMagenta.withValues(alpha: 0.9),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Dot section title ────────────────────────────────────────────────────────

class _DotTitle extends StatelessWidget {
  final Color color;
  final String label;
  final Color kText;

  /// Başlığın yanında gösterilecek opsiyonel sayı (ör. katılımcı adedi).
  final int? count;

  const _DotTitle({
    required this.color,
    required this.label,
    required this.kText,
    this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
            color: kText,
          ),
        ),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─── Offer card ───────────────────────────────────────────────────────────────

class _OfferCard extends StatelessWidget {
  final String? conditions;
  final String? type;
  final double? price;
  final bool isDark;
  final Color kCard, kBorder, kText, kDim;

  const _OfferCard({
    required this.conditions,
    required this.type,
    required this.price,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  String get _typeLabel {
    switch (type) {
      case 'BUFFET':     return 'Buffet';
      case 'SET_MENU':   return 'Set Menu';
      case 'OPEN_DRINK': return 'Open Drink';
      case 'OPEN_FOOD':  return 'Open Food';
      // Eski tipler (geriye dönük)
      case 'BOGO':           return 'Buy 1 Get 1 Free';
      case 'PERCENT_OFF':    return 'Percentage discount';
      case 'FIXED_DISCOUNT': return 'Fixed discount';
      case 'FREE_ITEM':      return 'Free item included';
      case 'BUNDLE':         return 'Bundle deal';
      default:               return type ?? '';
    }
  }

  String get _badge => price != null ? price!.toStringAsFixed(0) : '';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: _kTuruncu.withValues(alpha: 0.3), width: 1.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: _kTuruncu.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: const Icon(Icons.local_offer_outlined, size: 17, color: _kTuruncu),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_typeLabel,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: kText,
                    )),
                if (conditions != null && conditions!.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(conditions!,
                      style: TextStyle(fontSize: 12, color: kDim)),
                ],
              ],
            ),
          ),
          if (price != null) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: _kTuruncu.withValues(alpha: 0.12),
                border: Border.all(color: _kTuruncu.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(_badge,
                  style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w800, color: _kTuruncu,
                  )),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Benefit card ─────────────────────────────────────────────────────────────

class _BenefitCard extends StatelessWidget {
  final EventPartnerBenefit benefit;
  final bool isDark;
  final Color kCard, kBorder, kText, kDim;

  const _BenefitCard({
    required this.benefit,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _kMavi.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.handshake_outlined, size: 16, color: _kMavi),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(benefit.platformDisplayName,
                    style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700, color: kText,
                    )),
                const SizedBox(height: 3),
                Text(benefit.offerLabel,
                    style: TextStyle(fontSize: 12, color: kDim)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _kMavi.withValues(alpha: 0.10),
              border: Border.all(color: _kMavi.withValues(alpha: 0.25)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(benefit.offerTypeDisplayName,
                style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w700, color: _kMavi,
                )),
          ),
        ],
      ),
    );
  }
}

// ─── Gallery ──────────────────────────────────────────────────────────────────

class _Gallery extends StatelessWidget {
  final List<String> photos;
  const _Gallery({required this.photos});

  @override
  Widget build(BuildContext context) {
    if (photos.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          photos.first,
          width: double.infinity,
          height: 200,
          fit: BoxFit.cover,
        ),
      );
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 1,
      ),
      itemCount: photos.length,
      itemBuilder: (_, i) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(photos[i], fit: BoxFit.cover),
      ),
    );
  }
}

// ─── Attendee list ────────────────────────────────────────────────────────────

class _AttendeeList extends StatelessWidget {
  final List<Map<String, dynamic>>? attendees;
  final bool loading;
  final bool isDark;
  final Color kCard, kBorder, kText;

  const _AttendeeList({
    required this.attendees,
    required this.loading,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
  });

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _joinedLabel(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return 'Joined ${dt.day} ${_months[dt.month - 1]} · $h:$m';
  }

  String _displayName(Map<String, dynamic> user) {
    final full = (user['full_name'] ?? user['fullName'])?.toString().trim();
    if (full != null && full.isNotEmpty) return full;
    final uname = user['username']?.toString().trim();
    if (uname != null && uname.isNotEmpty) return '@$uname';
    return 'Guest';
  }

  @override
  Widget build(BuildContext context) {
    final list = attendees;
    // "Joined ..." alt satırı ve boş durum metni için okunaklı, kontrastlı renk.
    final kSub = isDark ? const Color(0xFF8CA0BF) : const Color(0xFF64748B);

    if (loading && list == null) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        alignment: Alignment.center,
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: _kTurkuaz),
        ),
      );
    }

    if (list == null || list.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Text(
          'No attendees yet.',
          style: TextStyle(fontSize: 13, color: kSub),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          for (int i = 0; i < list.length; i++) ...[
            if (i > 0)
              Divider(
                height: 1,
                thickness: 1,
                color: kBorder.withValues(alpha: 0.6),
                indent: 14,
                endIndent: 14,
              ),
            _AttendeeRow(
              user: Map<String, dynamic>.from(
                (list[i]['user'] as Map?) ?? const {},
              ),
              subtitle: _joinedLabel(list[i]['createdAt']?.toString()),
              displayName: _displayName(
                Map<String, dynamic>.from(
                  (list[i]['user'] as Map?) ?? const {},
                ),
              ),
              kText: kText,
              kDim: kSub,
            ),
          ],
        ],
      ),
    );
  }
}

class _AttendeeRow extends StatelessWidget {
  final Map<String, dynamic> user;
  final String subtitle;
  final String displayName;
  final Color kText, kDim;

  const _AttendeeRow({
    required this.user,
    required this.subtitle,
    required this.displayName,
    required this.kText,
    required this.kDim,
  });

  @override
  Widget build(BuildContext context) {
    final photo = user['photo']?.toString();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: (photo != null && photo.trim().isNotEmpty)
                ? CachedImage(photo, width: 38, height: 38, fit: BoxFit.cover)
                : Container(
                    width: 38,
                    height: 38,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFF0F8060), _kTurkuaz],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      displayName.replaceAll('@', '').isNotEmpty
                          ? displayName.replaceAll('@', '')[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: kText,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: kDim),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Edit scope sheet ─────────────────────────────────────────────────────────

class _EditScopeSheet extends StatelessWidget {
  final VenueUpcomingEvent event;
  final bool isDark;
  final Color kBg, kCard, kBorder, kText, kDim;

  const _EditScopeSheet({
    required this.event,
    required this.isDark,
    required this.kBg,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white12 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 18),
          Text('Edit recurring event',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          const SizedBox(height: 6),
          Text('"${event.title}"',
              style: TextStyle(fontSize: 13, color: kDim),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 18),
          _option(context, 'this', 'This event only', Icons.looks_one_outlined),
          const SizedBox(height: 8),
          _option(context, 'thisAndFollowing', 'This and following events', Icons.arrow_forward_rounded),
          const SizedBox(height: 8),
          _option(context, 'all', 'All events in series', Icons.repeat_rounded),
        ],
      ),
    );
  }

  Widget _option(BuildContext ctx, String value, String label, IconData icon) {
    return GestureDetector(
      onTap: () => Navigator.pop(ctx, value),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: _kTurkuaz),
            const SizedBox(width: 12),
            Text(label,
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kText)),
          ],
        ),
      ),
    );
  }
}
