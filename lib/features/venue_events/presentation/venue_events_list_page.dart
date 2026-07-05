import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'add_venue_event_page.dart';
import 'venue_event_detail_page.dart';
import '../data/venue_event_repository.dart';

// ─── Brand colors ─────────────────────────────────────────────────────────────

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi    = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed     = Color(0xFFEF4444);

// ─── Page ─────────────────────────────────────────────────────────────────────

class VenueEventsListPage extends StatefulWidget {
  final String venueId;
  final List<VenueUpcomingEvent> events;
  final VoidCallback onRefresh;

  const VenueEventsListPage({
    super.key,
    required this.venueId,
    required this.events,
    required this.onRefresh,
  });

  @override
  State<VenueEventsListPage> createState() => _VenueEventsListPageState();
}

class _VenueEventsListPageState extends State<VenueEventsListPage> {
  late List<VenueUpcomingEvent> _events;
  final _repo      = VenueEventRepository();
  final _venueRepo = VenueOwnerRepository();

  // Day strip state
  late DateTime _selectedDay;   // single-day OR range start
  DateTime?     _rangeEnd;      // null = single day mode
  bool          _rangeMode = false; // toggled by user
  late DateTime _viewMonth;

  // Chip filters
  bool _filterOffer   = false;
  bool _filterPartner = false;

  final _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    _events      = List.from(widget.events);
    final now    = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _viewMonth   = DateTime(now.year, now.month);
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VenueEventsListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) {
      setState(() => _events = List.from(widget.events));
    }
  }

  Future<void> _refreshEvents() async {
    widget.onRefresh();
    try {
      final stats = await _venueRepo.getOwnerStats(widget.venueId);
      if (!mounted) return;
      setState(() => _events = stats.venue.upcomingEvents);
    } catch (_) {}
  }

  // All days in the currently viewed month
  List<DateTime> get _daysInMonth {
    final first = _viewMonth;
    final last  = DateTime(first.year, first.month + 1, 0);
    return List.generate(last.day, (i) => DateTime(first.year, first.month, i + 1));
  }

  // Events for the selected day or range, filtered by chips
  List<VenueUpcomingEvent> get _filtered {
    final from = _selectedDay;
    final to   = _rangeEnd ?? _selectedDay;
    final toDay = DateTime(to.year, to.month, to.day);
    var result = _events.where((e) {
      final d   = e.startAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(from) && !day.isAfter(toDay);
    }).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt));
    if (_filterOffer)   result = result.where((e) => e.offerTitle != null).toList();
    if (_filterPartner) result = result.where((e) => e.partnershipCount > 0).toList();
    return result;
  }

  // Days in current month that have events
  Set<String> get _daysWithEvents {
    return _events.map((e) {
      final d = e.startAt.toLocal();
      return '${d.year}-${d.month}-${d.day}';
    }).toSet();
  }

  bool _dayHasEvent(DateTime d) =>
      _daysWithEvents.contains('${d.year}-${d.month}-${d.day}');

  void _goToPrevMonth() {
    final prev = DateTime(_viewMonth.year, _viewMonth.month - 1);
    setState(() {
      _viewMonth = prev;
      if (_selectedDay.year != prev.year || _selectedDay.month != prev.month) {
        _selectedDay = prev;
        _rangeEnd    = null;
      }
    });
    _scrollToSelected();
  }

  void _goToNextMonth() {
    final next = DateTime(_viewMonth.year, _viewMonth.month + 1);
    setState(() {
      _viewMonth = next;
      if (_selectedDay.year != next.year || _selectedDay.month != next.month) {
        _selectedDay = next;
        _rangeEnd    = null;
      }
    });
    _scrollToSelected();
  }

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripController.hasClients) return;
      final idx = _daysInMonth.indexWhere(
        (d) => d.day == _selectedDay.day &&
               d.month == _selectedDay.month &&
               d.year == _selectedDay.year,
      );
      if (idx < 0) return;
      const itemW = 52.0 + 8.0; // width + gap
      final offset = (idx * itemW) - (_stripController.position.viewportDimension / 2) + (itemW / 2);
      _stripController.animateTo(
        offset.clamp(0.0, _stripController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickMonth(BuildContext context, bool isDark, Color kBg, Color kCard, Color kBorder, Color kText, Color kDim) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(
        current: _viewMonth,
        isDark: isDark, kBg: kBg, kCard: kCard, kBorder: kBorder, kText: kText, kDim: kDim,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _viewMonth = picked;
      if (_selectedDay.year != picked.year || _selectedDay.month != picked.month) {
        _selectedDay = picked;
        _rangeEnd    = null;
      }
    });
    _scrollToSelected();
  }

  Future<void> _delete(VenueUpcomingEvent event) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String? deleteScope;
    if (event.isRecurring) {
      deleteScope = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _DeleteScopeSheet(event: event),
      );
      if (deleteScope == null || !mounted) return;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0B1322) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Delete Event',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800,
                color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827))),
        content: Text(
          deleteScope == 'series'
              ? 'All events in this series will be permanently deleted.'
              : '"${event.title}" will be permanently deleted.',
          style: TextStyle(fontSize: 13,
              color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(
                color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: _kRed, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      if (deleteScope == 'series' && event.recurringRuleId != null) {
        await _repo.deleteRecurringSeries(venueId: widget.venueId, ruleId: event.recurringRuleId!);
        setState(() => _events.removeWhere((e) => e.recurringRuleId == event.recurringRuleId));
      } else {
        await _repo.deleteEvent(venueId: widget.venueId, eventId: event.id);
        setState(() => _events.removeWhere((e) => e.id == event.id));
      }
      _refreshEvents();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete event'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final canManage = VenueSession.instance.can(VenuePermission.eventManage);
    final kBg       = isDark ? const Color(0xFF06091A) : Colors.white;
    final kCard     = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder   = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText     = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim      = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    final filtered   = _filtered;
    final days       = _daysInMonth;
    final now        = DateTime.now();
    final today      = DateTime(now.year, now.month, now.day);

    final monthNames = ['January','February','March','April','May','June',
                        'July','August','September','October','November','December'];

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.only(left: 14),
            width: 38, height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.0),
              border: Border.all(color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.0)),
            ),
            child: Icon(Icons.chevron_left_rounded, size: 22,
                color: isDark ? const Color(0xFF607090) : const Color(0xFF6B7280)),
          ),
        ),
        title: Text('Events',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      body: Column(
        children: [

          // ── Header row: month label (single mode) or range toggle ───
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                if (!_rangeMode) ...[
                  // Month + year — tappable
                  GestureDetector(
                    onTap: () => _pickMonth(context, isDark, kBg, kCard, kBorder, kText, kDim),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800,
                              color: kText, letterSpacing: -0.2),
                        ),
                        const SizedBox(width: 2),
                        Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: kDim),
                      ],
                    ),
                  ),
                  // Today shortcut
                  if (_viewMonth.year != today.year || _viewMonth.month != today.month) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _viewMonth   = DateTime(today.year, today.month);
                          _selectedDay = today;
                        });
                        _scrollToSelected();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _kTurkuaz.withValues(alpha: 0.10),
                          border: Border.all(color: _kTurkuaz.withValues(alpha: 0.3)),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Today',
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kTurkuaz)),
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                // Range mode toggle
                GestureDetector(
                  onTap: () => setState(() {
                    _rangeMode = !_rangeMode;
                    if (!_rangeMode) _rangeEnd = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _rangeMode ? _kMagenta.withValues(alpha: 0.12) : Colors.transparent,
                      border: Border.all(
                        color: _rangeMode
                            ? _kMagenta
                            : (isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA)),
                        width: _rangeMode ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.date_range_rounded, size: 12,
                            color: _rangeMode ? _kMagenta : kDim),
                        const SizedBox(width: 5),
                        Text('Range',
                            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700,
                                color: _rangeMode ? _kMagenta : kDim)),
                        if (_rangeMode) ...[
                          const SizedBox(width: 5),
                          const Icon(Icons.close_rounded, size: 11, color: _kMagenta),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Day strip (single mode) OR date range fields (range mode) ─
          if (!_rangeMode)
            SizedBox(
              height: 72,
              child: ListView.builder(
                controller: _stripController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: days.length,
                itemBuilder: (_, i) {
                  final d          = days[i];
                  final isSelected = d.year == _selectedDay.year &&
                                     d.month == _selectedDay.month &&
                                     d.day == _selectedDay.day;
                  final isToday    = d.year == today.year &&
                                     d.month == today.month &&
                                     d.day == today.day;
                  final hasEvent   = _dayHasEvent(d);
                  const dayLabels  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
                  final label      = dayLabels[(d.weekday - 1) % 7];

                  return GestureDetector(
                    onTap: () => setState(() => _selectedDay = d),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 44,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? _kMagenta
                            : isToday
                                ? _kMagenta.withValues(alpha: 0.08)
                                : Colors.transparent,
                        border: Border.all(
                          color: isSelected
                              ? _kMagenta
                              : isToday
                                  ? _kMagenta.withValues(alpha: 0.4)
                                  : kBorder,
                          width: isSelected ? 1.5 : 1,
                        ),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(label,
                              style: TextStyle(
                                fontSize: 10, fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white.withValues(alpha: 0.75) : kDim,
                              )),
                          const SizedBox(height: 4),
                          Text('${d.day}',
                              style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800,
                                color: isSelected ? Colors.white : kText,
                              )),
                          const SizedBox(height: 4),
                          Container(
                            width: 4, height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasEvent
                                  ? (isSelected ? Colors.white.withValues(alpha: 0.7) : _kTurkuaz)
                                  : Colors.transparent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            // ── Range date pickers ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Start date',
                      date: _selectedDay,
                      color: _kMagenta,
                      isDark: isDark,
                      kCard: kCard,
                      kBorder: kBorder,
                      kText: kText,
                      kDim: kDim,
                      onTap: () async {
                        final picked = await showModalBottomSheet<DateTime>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _CalendarSheet(
                            initial: _selectedDay,
                            minDate: null,
                            daysWithEvents: _daysWithEvents,
                            isDark: isDark,
                            kBg: kBg, kCard: kCard, kBorder: kBorder,
                            kText: kText, kDim: kDim,
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _selectedDay = picked;
                            // Reset end if it's before new start
                            if (_rangeEnd != null && !_rangeEnd!.isAfter(picked)) {
                              _rangeEnd = null;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(Icons.arrow_forward_rounded, size: 16, color: kDim),
                  ),
                  Expanded(
                    child: _DateField(
                      label: 'End date',
                      date: _rangeEnd,
                      color: _kMavi,
                      isDark: isDark,
                      kCard: kCard,
                      kBorder: kBorder,
                      kText: kText,
                      kDim: kDim,
                      onTap: () async {
                        final picked = await showModalBottomSheet<DateTime>(
                          context: context,
                          backgroundColor: Colors.transparent,
                          isScrollControlled: true,
                          builder: (_) => _CalendarSheet(
                            initial: _rangeEnd ?? _selectedDay,
                            minDate: _selectedDay.add(const Duration(days: 1)),
                            daysWithEvents: _daysWithEvents,
                            isDark: isDark,
                            kBg: kBg, kCard: kCard, kBorder: kBorder,
                            kText: kText, kDim: kDim,
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() => _rangeEnd = picked);
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 10),

          // ── Chip filters ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _Chip(
                  label: 'Kmstry Offer',
                  icon: Icons.local_offer_outlined,
                  active: _filterOffer,
                  color: _kTuruncu,
                  isDark: isDark,
                  onTap: () => setState(() => _filterOffer = !_filterOffer),
                ),
                const SizedBox(width: 8),
                _Chip(
                  label: 'Partner Benefits',
                  icon: Icons.handshake_outlined,
                  active: _filterPartner,
                  color: _kMavi,
                  isDark: isDark,
                  onTap: () => setState(() => _filterPartner = !_filterPartner),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Divider ──────────────────────────────────────────────────
          Container(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.05)
                : Colors.black.withValues(alpha: 0.06),
          ),

          // ── Events list ──────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF0D1525)
                                : const Color(0xFFF3F6FA),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.event_outlined, size: 24,
                              color: isDark ? const Color(0xFF1E3050) : const Color(0xFFD1D5DB)),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _rangeEnd != null ? 'No events in this range' : 'No events on this day',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kDim),
                        ),
                        if (_filterOffer || _filterPartner) ...[
                          const SizedBox(height: 8),
                          GestureDetector(
                            onTap: () => setState(() { _filterOffer = false; _filterPartner = false; }),
                            child: const Text('Clear filters',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kTurkuaz)),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final event = filtered[i];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _EventRow(
                          key: ValueKey(event.id),
                          event: event,
                          venueId: widget.venueId,
                          canManage: canManage,
                          isDark: isDark,
                          kCard: kCard,
                          kBorder: kBorder,
                          kText: kText,
                          kDim: kDim,
                          showDate: _rangeEnd != null,
                          onChanged: _refreshEvents,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Nav button ───────────────────────────────────────────────────────────────

class _NavBtn extends StatelessWidget {
  final IconData icon;
  final bool isDark;
  final VoidCallback onTap;

  const _NavBtn({required this.icon, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.04),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.08),
          ),
        ),
        child: Icon(icon, size: 20,
            color: isDark ? const Color(0xFF607090) : const Color(0xFF6B7280)),
      ),
    );
  }
}

// ─── Chip ─────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final bool isDark;
  final VoidCallback onTap;

  const _Chip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kDim = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(
            color: active ? color : (isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA)),
            width: active ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? color : kDim),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? color : kDim,
                )),
          ],
        ),
      ),
    );
  }
}

// ─── Event row ────────────────────────────────────────────────────────────────

class _EventRow extends StatelessWidget {
  final VenueUpcomingEvent event;
  final String venueId;
  final bool canManage;
  final bool isDark;
  final bool showDate;
  final Color kCard, kBorder, kText, kDim;
  final VoidCallback? onChanged;

  const _EventRow({
    super.key,
    required this.event,
    required this.venueId,
    required this.canManage,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
    this.showDate = false,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isFree = event.priceAed == null || event.priceAed == 0;

    final local = event.startAt.toLocal();
    final h     = local.hour.toString().padLeft(2, '0');
    final m     = local.minute.toString().padLeft(2, '0');
    final time  = '$h:$m';
    const shortMonths = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateLabel = showDate ? '${local.day} ${shortMonths[local.month - 1]}' : null;

    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => VenueEventDetailPage(
              event: event,
              venueId: venueId,
              onChanged: onChanged,
            ),
          ),
        );
        if (result == true) onChanged?.call();
      },
      child: Container(
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark ? null : [
            BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Time column
            Container(
              width: 52,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (dateLabel != null) ...[
                    Text(dateLabel,
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: kDim,
                        )),
                    const SizedBox(height: 2),
                  ],
                  Text(time,
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: _kMagenta,
                      )),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: isFree
                          ? _kTurkuaz.withValues(alpha: 0.12)
                          : _kTuruncu.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isFree ? 'Free' : '${event.currency} ${event.priceAed}',
                      style: TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w700,
                        color: isFree ? _kTurkuaz : _kTuruncu,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Vertical divider
            Container(
              width: 1, height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  if (event.description != null && event.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(event.description!,
                        style: TextStyle(fontSize: 11.5, color: kDim, height: 1.4),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  if (event.offerTitle != null || event.partnershipCount > 0 || event.capacity != null || event.rsvpCount > 0) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (event.offerTitle != null)
                          _Badge(icon: Icons.local_offer_outlined,
                              label: event.offerTitle!, color: _kTuruncu),
                        if (event.partnershipCount > 0)
                          _Badge(
                            icon: Icons.handshake_outlined,
                            label: '${event.partnershipCount} partner${event.partnershipCount > 1 ? 's' : ''}',
                            color: _kMavi,
                          ),
                        if (event.capacity != null || event.rsvpCount > 0)
                          _Badge(
                            icon: Icons.people_outline_rounded,
                            label: event.capacity != null
                                ? '${event.rsvpCount}/${event.capacity}'
                                : '${event.rsvpCount} attending',
                            color: (event.capacity != null && event.rsvpCount >= event.capacity!)
                                ? _kRed
                                : _kMavi,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Badges + chevron
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (event.isRecurring)
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kMagenta.withValues(alpha: 0.10),
                      border: Border.all(color: _kMagenta.withValues(alpha: 0.25)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.repeat_rounded, size: 9, color: _kMagenta),
                        SizedBox(width: 3),
                        Text('Repeat', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _kMagenta)),
                      ],
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, size: 16, color: kDim),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Month picker dialog ──────────────────────────────────────────────────────

class _MonthPickerDialog extends StatefulWidget {
  final DateTime current;
  final bool isDark;
  final Color kBg, kCard, kBorder, kText, kDim;

  const _MonthPickerDialog({
    required this.current,
    required this.isDark,
    required this.kBg,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  @override
  State<_MonthPickerDialog> createState() => _MonthPickerDialogState();
}

class _MonthPickerDialogState extends State<_MonthPickerDialog> {
  late int _year;

  @override
  void initState() {
    super.initState();
    _year = widget.current.year;
  }

  @override
  Widget build(BuildContext context) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun',
                    'Jul','Aug','Sep','Oct','Nov','Dec'];
    final now    = DateTime.now();

    return Dialog(
      backgroundColor: widget.kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Year nav
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _year--),
                  child: Icon(Icons.chevron_left_rounded, color: widget.kDim),
                ),
                Text('$_year',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: widget.kText)),
                GestureDetector(
                  onTap: () => setState(() => _year++),
                  child: Icon(Icons.chevron_right_rounded, color: widget.kDim),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Month grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.6,
              ),
              itemCount: 12,
              itemBuilder: (_, i) {
                final isSelected = _year == widget.current.year &&
                    (i + 1) == widget.current.month;
                final isNow     = _year == now.year && (i + 1) == now.month;

                return GestureDetector(
                  onTap: () => Navigator.pop(context, DateTime(_year, i + 1)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? _kMagenta
                          : isNow
                              ? _kMagenta.withValues(alpha: 0.10)
                              : widget.kCard,
                      border: Border.all(
                        color: isSelected
                            ? _kMagenta
                            : isNow
                                ? _kMagenta.withValues(alpha: 0.4)
                                : widget.kBorder,
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(months[i],
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isSelected ? Colors.white : widget.kText,
                        )),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Delete scope sheet ───────────────────────────────────────────────────────

class _DeleteScopeSheet extends StatelessWidget {
  final VenueUpcomingEvent event;
  const _DeleteScopeSheet({required this.event});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kCard  = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kText  = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(20)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4,
              decoration: BoxDecoration(color: kDim.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: _kRed.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.delete_outline, size: 15, color: _kRed),
              ),
              const SizedBox(width: 10),
              Text('Delete recurring event', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
            ]),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Which events do you want to delete?',
                style: TextStyle(fontSize: 13, color: kDim)),
          ),
          _ScopeOption(label: 'Only this event', sublabel: 'Just this occurrence', icon: Icons.event_outlined,
              color: _kTuruncu, onTap: () => Navigator.pop(context, 'single')),
          _ScopeOption(label: 'All events in series', sublabel: 'Delete entire series', icon: Icons.repeat_rounded,
              color: _kRed, onTap: () => Navigator.pop(context, 'series')),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Scope option row ─────────────────────────────────────────────────────────

class _ScopeOption extends StatelessWidget {
  final String label;
  final String sublabel;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ScopeOption({
    required this.label,
    required this.sublabel,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final kText  = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim   = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 17, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kText)),
              Text(sublabel, style: TextStyle(fontSize: 11.5, color: kDim)),
            ],
          ),
          const Spacer(),
          Icon(Icons.chevron_right_rounded, size: 18, color: kDim),
        ]),
      ),
    );
  }
}

// ─── Date field ───────────────────────────────────────────────────────────────

class _DateField extends StatelessWidget {
  final String label;
  final DateTime? date;
  final Color color;
  final bool isDark;
  final Color kCard, kBorder, kText, kDim;
  final VoidCallback onTap;

  const _DateField({
    required this.label,
    required this.date,
    required this.color,
    required this.isDark,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
    required this.onTap,
  });

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final hasDate = date != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: hasDate ? color.withValues(alpha: 0.08) : kCard,
          border: Border.all(
            color: hasDate ? color.withValues(alpha: 0.5) : kBorder,
            width: hasDate ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_outlined, size: 13,
                color: hasDate ? color : kDim),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                hasDate ? _fmt(date!) : label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: hasDate ? FontWeight.w700 : FontWeight.w500,
                  color: hasDate ? color : kDim,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Calendar bottom sheet ────────────────────────────────────────────────────

class _CalendarSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime? minDate;
  final Set<String> daysWithEvents;
  final bool isDark;
  final Color kBg, kCard, kBorder, kText, kDim;

  const _CalendarSheet({
    required this.initial,
    required this.minDate,
    required this.daysWithEvents,
    required this.isDark,
    required this.kBg,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _viewMonth;

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(widget.initial.year, widget.initial.month);
  }

  List<DateTime?> get _calendarDays {
    final first   = DateTime(_viewMonth.year, _viewMonth.month, 1);
    final lastDay = DateTime(_viewMonth.year, _viewMonth.month + 1, 0).day;
    final leadNulls = first.weekday - 1;
    final result  = <DateTime?>[];
    for (var i = 0; i < leadNulls; i++) result.add(null);
    for (var d = 1; d <= lastDay; d++) {
      result.add(DateTime(_viewMonth.year, _viewMonth.month, d));
    }
    return result;
  }

  bool _isDisabled(DateTime d) {
    if (widget.minDate == null) return false;
    final min = DateTime(widget.minDate!.year, widget.minDate!.month, widget.minDate!.day);
    return d.isBefore(min);
  }

  bool _hasEvent(DateTime d) =>
      widget.daysWithEvents.contains('${d.year}-${d.month}-${d.day}');

  @override
  Widget build(BuildContext context) {
    final monthNames = ['January','February','March','April','May','June',
                        'July','August','September','October','November','December'];
    const dayLabels  = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    final now        = DateTime.now();
    final today      = DateTime(now.year, now.month, now.day);
    final calDays    = _calendarDays;

    return Container(
      decoration: BoxDecoration(
        color: widget.kBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(16, 12, 16,
          MediaQuery.of(context).padding.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: widget.isDark ? Colors.white12 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Month nav
          Row(
            children: [
              GestureDetector(
                onTap: () => setState(() =>
                    _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1)),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    border: Border.all(color: widget.kBorder),
                  ),
                  child: Icon(Icons.chevron_left_rounded, size: 18, color: widget.kDim),
                ),
              ),
              Expanded(
                child: Text(
                  '${monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: widget.kText),
                ),
              ),
              GestureDetector(
                onTap: () => setState(() =>
                    _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1)),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.04),
                    border: Border.all(color: widget.kBorder),
                  ),
                  child: Icon(Icons.chevron_right_rounded, size: 18, color: widget.kDim),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Day labels
          Row(
            children: dayLabels.map((l) => Expanded(
              child: Center(
                child: Text(l,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: widget.kDim)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),
          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              childAspectRatio: 1.1,
            ),
            itemCount: calDays.length,
            itemBuilder: (_, i) {
              final d = calDays[i];
              if (d == null) return const SizedBox();
              final isToday  = d.year == today.year && d.month == today.month && d.day == today.day;
              final disabled = _isDisabled(d);
              final hasEvent = _hasEvent(d);

              return GestureDetector(
                onTap: disabled ? null : () {
                  Navigator.pop(context, d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  decoration: BoxDecoration(
                    color: isToday ? _kMagenta.withValues(alpha: 0.10) : Colors.transparent,
                    border: Border.all(
                      color: isToday ? _kMagenta.withValues(alpha: 0.4) : Colors.transparent,
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Opacity(
                    opacity: disabled ? 0.25 : 1.0,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${d.day}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: widget.kText,
                            )),
                        if (hasEvent)
                          Container(
                            width: 4, height: 4,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _kTurkuaz,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

// ─── Benefit badge ────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Badge({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color),
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}
