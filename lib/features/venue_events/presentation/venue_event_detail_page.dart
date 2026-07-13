import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
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

  @override
  void initState() {
    super.initState();
    _event = widget.event;
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
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final event    = _event;
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final kBg       = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard     = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder   = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText     = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim      = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final canManage = VenueSession.instance.can(VenuePermission.eventManage);

    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);
    final isFree = event.priceAed == null || event.priceAed == 0;

    return Scaffold(
      backgroundColor: kBg,
      body: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────
          SliverAppBar(
            backgroundColor: kBg,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            pinned: true,
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.06)
                          : Colors.black.withValues(alpha: 0.05),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Icon(
                      Icons.chevron_left_rounded,
                      size: 22,
                      color: isDark ? const Color(0xFF607090) : const Color(0xFF6B7280),
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
            actions: canManage
                ? [
                    _AppBarBtn(
                      icon: Icons.edit_outlined,
                      color: _kTurkuaz,
                      isDark: isDark,
                      onTap: () => _openEdit(context, isDark, kBg, kCard, kBorder, kText, kDim),
                    ),
                    _AppBarBtn(
                      icon: Icons.delete_outline_rounded,
                      color: _kRed,
                      isDark: isDark,
                      onTap: () => _confirmDelete(context, isDark),
                    ),
                    const SizedBox(width: 6),
                  ]
                : null,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(
                height: 1,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 52),
            sliver: SliverList(
              delegate: SliverChildListDelegate([

                // ── 1. Title ─────────────────────────────────────────────
                Text(
                  event.title,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    color: kText,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 16),

                // ── 2. Date & price chips ─────────────────────────────────
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip(
                      icon: Icons.calendar_today_outlined,
                      label: event.formattedDate,
                      color: _kTurkuaz,
                      isDark: isDark,
                    ),
                    _InfoChip(
                      icon: isFree
                          ? Icons.card_giftcard_outlined
                          : Icons.confirmation_num_outlined,
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
                        color: (event.capacity != null && event.rsvpCount >= event.capacity!)
                            ? _kRed
                            : _kMavi,
                        isDark: isDark,
                      ),
                  ],
                ),

                // ── 3. Description ────────────────────────────────────────
                if (event.description != null && event.description!.isNotEmpty) ...[
                  _divider(isDark),
                  _SectionLabel(
                    icon: Icons.notes_rounded,
                    label: 'About',
                    color: _kMavi,
                    kText: kText,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    event.description!,
                    style: TextStyle(
                      fontSize: 14,
                      color: kDim,
                      height: 1.7,
                    ),
                  ),
                ],

                // ── 4. Kmstry Offers ──────────────────────────────────────
                if (event.offerType != null) ...[
                  _divider(isDark),
                  _SectionLabel(
                    icon: Icons.local_offer_outlined,
                    label: 'Kmstry Offer',
                    color: _kTuruncu,
                    kText: kText,
                  ),
                  const SizedBox(height: 10),
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

                // ── 5. Capacity & Attendees ───────────────────────────────
                if (canManage && (event.capacity != null || event.rsvpCount > 0)) ...[
                  _divider(isDark),
                  _SectionLabel(
                    icon: Icons.people_outline_rounded,
                    label: 'Attendees',
                    color: _kTurkuaz,
                    kText: kText,
                  ),
                  const SizedBox(height: 10),
                  _AttendeeBar(
                    rsvpCount: event.rsvpCount,
                    capacity: event.capacity,
                    isDark: isDark,
                    kCard: kCard,
                    kBorder: kBorder,
                    kText: kText,
                    kDim: kDim,
                  ),
                ],

                // ── 6. Partner Benefits ───────────────────────────────────
                if (event.partnershipBenefits.isNotEmpty) ...[
                  _divider(isDark),
                  _SectionLabel(
                    icon: Icons.handshake_outlined,
                    label: 'Partner Benefits',
                    color: _kMavi,
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

                // ── 7. Gallery ────────────────────────────────────────────
                if (photos.isNotEmpty) ...[
                  _divider(isDark),
                  _SectionLabel(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: _kMagenta,
                    kText: kText,
                  ),
                  const SizedBox(height: 10),
                  _Gallery(photos: photos),
                ],

              ]),
            ),
          ),
        ],
      ),
    );
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

  Widget _divider(bool isDark) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 20),
    child: Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          Colors.transparent,
          isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.09),
          Colors.transparent,
        ]),
      ),
    ),
  );
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

// ─── Section label ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final Color kText;

  const _SectionLabel({
    required this.icon,
    required this.label,
    required this.color,
    required this.kText,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 26, height: 26,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 12, color: color),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: color,
            )),
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

  String get _badge => price != null ? '${price!.toStringAsFixed(0)}' : '';

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

// ─── App bar button ───────────────────────────────────────────────────────────

class _AppBarBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _AppBarBtn({
    required this.icon,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8, top: 8, bottom: 8),
        width: 34, height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.12),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }
}

// ─── Attendee bar ─────────────────────────────────────────────────────────────

class _AttendeeBar extends StatelessWidget {
  final int rsvpCount;
  final int? capacity;
  final bool isDark;
  final Color kCard, kBorder, kText, kDim;

  const _AttendeeBar({
    required this.rsvpCount,
    required this.capacity,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  @override
  Widget build(BuildContext context) {
    final isFull = capacity != null && rsvpCount >= capacity!;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.people_outline_rounded, size: 16, color: _kTurkuaz),
              const SizedBox(width: 6),
              Text(
                capacity != null
                    ? '$rsvpCount / $capacity attending'
                    : '$rsvpCount attending',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kText),
              ),
              const Spacer(),
              if (isFull)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text('Full',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kRed)),
                ),
            ],
          ),
          if (capacity != null) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (rsvpCount / capacity!).clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA),
                valueColor: AlwaysStoppedAnimation<Color>(
                  isFull ? _kRed : _kTurkuaz,
                ),
              ),
            ),
          ],
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
