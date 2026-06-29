import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/venue/venue_session.dart';
import 'package:kmstry_frontend/features/venue/data/venue_member_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';
import 'add_venue_event_page.dart';
import '../data/venue_event_repository.dart';

// ─── Brand colors ─────────────────────────────────────────────────────────────

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi    = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed     = Color(0xFFEF4444);

// ─── Filter enum ──────────────────────────────────────────────────────────────

enum _DateFilter { all, today, thisWeek, custom }

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
  final _repo        = VenueEventRepository();
  final _venueRepo   = VenueOwnerRepository();

  _DateFilter _filter     = _DateFilter.today;
  DateTime?   _customFrom;
  DateTime?   _customTo;

  String? _statFilter;
  String? _seriesFilter;

  // Cached filtered list — recomputed only when inputs change
  List<VenueUpcomingEvent> _cachedFiltered = [];
  Object? _lastFilterKey;

  @override
  void initState() {
    super.initState();
    _events = List.from(widget.events);
  }

  @override
  void didUpdateWidget(VenueEventsListPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.events != widget.events) {
      setState(() {
        _events = List.from(widget.events);
        if (_seriesFilter != null && !widget.events.any((e) => e.recurringRuleId == _seriesFilter)) {
          _seriesFilter = null;
        }
      });
    }
  }

  Future<void> _refreshEvents() async {
    widget.onRefresh();
    try {
      final stats = await _venueRepo.getOwnerStats(widget.venueId);
      if (!mounted) return;
      setState(() {
        _events = stats.venue.upcomingEvents;
        if (_seriesFilter != null && !_events.any((e) => e.recurringRuleId == _seriesFilter)) {
          _seriesFilter = null;
        }
      });
    } catch (_) {}
  }

  List<VenueUpcomingEvent> get _filtered {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final key   = (_events, _filter, _customFrom, _customTo, _statFilter, _seriesFilter, today);
    if (identical(key, _lastFilterKey)) return _cachedFiltered;
    _lastFilterKey = key;

    List<VenueUpcomingEvent> result;
    switch (_filter) {
      case _DateFilter.all:
        result = _events;
      case _DateFilter.today:
        result = _events.where((e) {
          final d = e.startAt.toLocal();
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }).toList();
      case _DateFilter.thisWeek:
        final weekEnd = today.add(const Duration(days: 7));
        result = _events.where((e) {
          final d = e.startAt.toLocal();
          return !d.isBefore(today) && d.isBefore(weekEnd);
        }).toList();
      case _DateFilter.custom:
        final from = _customFrom != null
            ? DateTime(_customFrom!.year, _customFrom!.month, _customFrom!.day)
            : null;
        final to = _customTo != null
            ? DateTime(_customTo!.year, _customTo!.month, _customTo!.day, 23, 59, 59)
            : null;
        result = _events.where((e) {
          final d = e.startAt.toLocal();
          if (from != null && d.isBefore(from)) return false;
          if (to   != null && d.isAfter(to))   return false;
          return true;
        }).toList();
    }

    if (_statFilter == 'upcoming') {
      result = result.where((e) => e.startAt.isAfter(now)).toList();
    } else if (_statFilter == 'past') {
      result = result.where((e) => !e.startAt.isAfter(now)).toList();
    } else if (_statFilter == 'recurring') {
      result = result.where((e) => e.isRecurring).toList();
    }

    if (_seriesFilter != null) {
      result = result.where((e) => e.recurringRuleId == _seriesFilter).toList();
    }

    _cachedFiltered = result;
    return result;
  }

  /// Recurring series grouped by recurring_rule_id, sorted by next occurrence.
  List<_RecurringSeries> get _recurringSeries {
    final map = <String, List<VenueUpcomingEvent>>{};
    for (final e in _events) {
      if (e.recurringRuleId != null) {
        map.putIfAbsent(e.recurringRuleId!, () => []).add(e);
      }
    }
    final now = DateTime.now();
    return map.entries.map((entry) {
      final events = entry.value..sort((a, b) => a.startAt.compareTo(b.startAt));
      final next = events.firstWhere((e) => e.startAt.isAfter(now), orElse: () => events.last);
      return _RecurringSeries(ruleId: entry.key, title: events.first.title, count: events.length, next: next);
    }).toList()
      ..sort((a, b) => a.next.startAt.compareTo(b.next.startAt));
  }

  String get _filterChipLabel {
    switch (_filter) {
      case _DateFilter.all:      return 'All events';
      case _DateFilter.today:    return 'Today';
      case _DateFilter.thisWeek: return 'This week';
      case _DateFilter.custom:
        String fmt(DateTime d) {
          const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          return '${d.day} ${m[d.month - 1]}';
        }
        if (_customFrom != null && _customTo != null) return '${fmt(_customFrom!)} – ${fmt(_customTo!)}';
        if (_customFrom != null) return 'From ${fmt(_customFrom!)}';
        if (_customTo   != null) return 'Until ${fmt(_customTo!)}';
        return 'Custom';
    }
  }

  Future<void> _showFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(
        current:    _filter,
        customFrom: _customFrom,
        customTo:   _customTo,
        onApply: (filter, from, to) => setState(() {
          _filter     = filter;
          _customFrom = from;
          _customTo   = to;
        }),
      ),
    );
  }

  Future<void> _openEdit(VenueUpcomingEvent event) async {
    String? editScope;
    if (event.isRecurring) {
      editScope = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: Colors.transparent,
        builder: (_) => _EditScopeSheet(event: event),
      );
      if (editScope == null || !mounted) return;
    }

    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddVenueEventPage(
          venueId: widget.venueId,
          existing: event,
          editScope: editScope,
        ),
      ),
    );
    if (result == true && mounted) {
      _refreshEvents();
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          duration: const Duration(seconds: 3),
          content: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1525),
              border: Border.all(color: _kTurkuaz.withValues(alpha: 0.4), width: 1.5),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 20, offset: const Offset(0, 6))],
            ),
            child: const Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: _kTurkuaz),
                SizedBox(width: 10),
                Text('Event updated successfully',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFFEEF2FF))),
              ],
            ),
          ),
        ));
    }
  }

  Future<void> _delete(VenueUpcomingEvent event) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // For recurring events, ask scope first
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
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w800,
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
            child: Text('Cancel',
                style: TextStyle(
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

    final filtered  = _filtered;
    final now       = DateTime.now();
    // Stats computed on date-filtered list (before stat filter) for accurate counts
    final dateFiltOnly = (() {
      final all = _filtered;
      if (_statFilter == null) return all;
      // recompute without statFilter
      final now2 = DateTime.now();
      final today = DateTime(now2.year, now2.month, now2.day);
      List<VenueUpcomingEvent> r;
      switch (_filter) {
        case _DateFilter.all: r = _events;
        case _DateFilter.today:
          r = _events.where((e) { final d = e.startAt.toLocal(); return d.year==today.year&&d.month==today.month&&d.day==today.day; }).toList();
        case _DateFilter.thisWeek:
          final we = today.add(const Duration(days: 7));
          r = _events.where((e) { final d = e.startAt.toLocal(); return !d.isBefore(today)&&d.isBefore(we); }).toList();
        case _DateFilter.custom:
          final from = _customFrom != null ? DateTime(_customFrom!.year,_customFrom!.month,_customFrom!.day) : null;
          final to   = _customTo   != null ? DateTime(_customTo!.year,  _customTo!.month,  _customTo!.day,23,59,59) : null;
          r = _events.where((e) { final d=e.startAt.toLocal(); if(from!=null&&d.isBefore(from))return false; if(to!=null&&d.isAfter(to))return false; return true; }).toList();
      }
      return r;
    })();
    final totalCount     = dateFiltOnly.length;
    final upcomingCount  = dateFiltOnly.where((e) => e.startAt.isAfter(now)).length;
    final pastCount      = dateFiltOnly.where((e) => !e.startAt.isAfter(now)).length;
    final recurringCount = dateFiltOnly.where((e) => e.isRecurring).length;

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
        title: Text('All Events',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
        centerTitle: true,
        actions: [
          GestureDetector(
            onTap: _showFilterSheet,
            child: Container(
              margin: const EdgeInsets.only(right: 14),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _kMagenta.withValues(alpha: 0.10),
                border: Border.all(color: _kMagenta.withValues(alpha: 0.25)),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 14, color: _kMagenta),
                  SizedBox(width: 5),
                  Text('Filter', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _kMagenta)),
                ],
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1,
              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.06)),
        ),
      ),
      body: Column(
        children: [
          // ── Stats strip ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(children: [
              _StatPill(
                num: '$totalCount', label: 'Total', color: _kMagenta,
                kCard: kCard, kBorder: kBorder,
                active: _statFilter == null,
                onTap: () => setState(() => _statFilter = null),
              ),
              const SizedBox(width: 8),
              _StatPill(
                num: '$upcomingCount', label: 'Upcoming', color: _kTurkuaz,
                kCard: kCard, kBorder: kBorder,
                active: _statFilter == 'upcoming',
                onTap: () => setState(() => _statFilter = _statFilter == 'upcoming' ? null : 'upcoming'),
              ),
              const SizedBox(width: 8),
              _StatPill(
                num: '$pastCount', label: 'Past', color: _kTuruncu,
                kCard: kCard, kBorder: kBorder,
                active: _statFilter == 'past',
                onTap: () => setState(() => _statFilter = _statFilter == 'past' ? null : 'past'),
              ),
              const SizedBox(width: 8),
              _StatPill(
                num: '$recurringCount', label: 'Recurring', color: _kMavi,
                kCard: kCard, kBorder: kBorder,
                active: _statFilter == 'recurring',
                onTap: () => setState(() => _statFilter = _statFilter == 'recurring' ? null : 'recurring'),
              ),
            ]),
          ),

          // ── Active filter chip ───────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _kTurkuaz.withValues(alpha: 0.10),
                    border: Border.all(color: _kTurkuaz.withValues(alpha: 0.25)),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_rounded, size: 12, color: _kTurkuaz),
                      const SizedBox(width: 5),
                      Text(_filterChipLabel,
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kTurkuaz)),
                    ],
                  ),
                ),
                if (_filter != _DateFilter.all) ...[
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => setState(() {
                      _filter     = _DateFilter.all;
                      _customFrom = null;
                      _customTo   = null;
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _kRed.withValues(alpha: 0.08),
                        border: Border.all(color: _kRed.withValues(alpha: 0.25)),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.close_rounded, size: 11, color: _kRed),
                          SizedBox(width: 4),
                          Text('Clear filter',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _kRed)),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 10),

          // ── Events list ──────────────────────────────────────────────
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.event_outlined, size: 48,
                            color: isDark ? const Color(0xFF1E3050) : const Color(0xFFD1D5DB)),
                        const SizedBox(height: 12),
                        Text(
                          _filter == _DateFilter.all ? 'No events yet' : 'No events for this period',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: kDim),
                        ),
                        if (_filter != _DateFilter.all) ...[
                          const SizedBox(height: 10),
                          GestureDetector(
                            onTap: () => setState(() { _filter = _DateFilter.all; _customFrom = null; _customTo = null; }),
                            child: const Text('Clear filter',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _kTurkuaz)),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 32),
                    itemCount: filtered.length,
                    addRepaintBoundaries: false,
                    itemBuilder: (_, i) {
                      final event = filtered[i];
                      return RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _EventCard(
                            key: ValueKey(event.id),
                            event: event,
                            accentColor: _accentFor(i),
                            canManage: canManage,
                            onEdit:   canManage ? () => _openEdit(event) : null,
                            onDelete: canManage ? () => _delete(event) : null,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Color _accentFor(int i) {
    const colors = [_kTurkuaz, _kTuruncu, _kMagenta, _kMavi];
    return colors[i % colors.length];
  }
}

// ─── Stat pill ────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String num;
  final String label;
  final Color  color;
  final Color  kCard;
  final Color  kBorder;
  final bool   active;
  final VoidCallback onTap;

  const _StatPill({
    required this.num, required this.label,
    required this.color, required this.kCard, required this.kBorder,
    required this.active, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.10) : kCard,
            border: Border.all(color: active ? color : kBorder, width: active ? 1.5 : 1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(children: [
            Text(num, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
            const SizedBox(height: 1),
            Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                color: active ? color.withValues(alpha: 0.7) : const Color(0xFF2E4560))),
          ]),
        ),
      ),
    );
  }
}

// ─── Event card ───────────────────────────────────────────────────────────────

class _EventCard extends StatelessWidget {
  final VenueUpcomingEvent event;
  final Color       accentColor;
  final bool        canManage;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _EventCard({
    super.key,
    required this.event,
    required this.accentColor,
    required this.canManage,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final kCard   = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kDim    = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kText   = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);

    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);

    final isFree = event.priceAed == null || event.priceAed == 0;

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(18),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent bar
            Container(
              width: 3,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [accentColor, accentColor.withValues(alpha: 0.3)],
                ),
              ),
            ),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(13, 13, 13, 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(event.title,
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 5),
                              Row(children: [
                                const Icon(Icons.calendar_today_outlined, size: 12, color: _kTurkuaz),
                                const SizedBox(width: 5),
                                Expanded(
                                  child: Text(event.formattedDate,
                                      style: TextStyle(fontSize: 11, color: kDim)),
                                ),
                              ]),
                              if (event.description != null && event.description!.isNotEmpty) ...[
                                const SizedBox(height: 5),
                                Text(event.description!,
                                    style: TextStyle(fontSize: 11.5, color: kDim, height: 1.45),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        // Actions column
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (onEdit != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (event.isRecurring)
                                    Container(
                                      margin: const EdgeInsets.only(right: 5),
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
                                          Text('Recurring', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: _kMagenta)),
                                        ],
                                      ),
                                    ),
                                  GestureDetector(
                                    onTap: onEdit,
                                    child: Container(
                                      width: 28, height: 28,
                                      decoration: BoxDecoration(
                                        color: _kTurkuaz.withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.edit_outlined, size: 14, color: _kTurkuaz),
                                    ),
                                  ),
                                ],
                              ),
                            if (onDelete != null) ...[
                              const SizedBox(height: 6),
                              GestureDetector(
                                onTap: onDelete,
                                child: Container(
                                  width: 28, height: 28,
                                  decoration: BoxDecoration(
                                    color: _kRed.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.delete_outline, size: 14, color: _kRed),
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            // Price badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: isFree
                                    ? _kTurkuaz.withValues(alpha: 0.15)
                                    : _kTuruncu.withValues(alpha: 0.15),
                                border: Border.all(
                                  color: isFree
                                      ? _kTurkuaz.withValues(alpha: 0.25)
                                      : _kTuruncu.withValues(alpha: 0.25),
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isFree
                                    ? 'Free'
                                    : '${event.currency} ${event.priceAed}',
                                style: TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w800,
                                  color: isFree ? _kTurkuaz : _kTuruncu,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Photos
                  if (photos.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(13, 0, 13, 12),
                      child: Row(
                        children: photos.take(3).map((url) => Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(9),
                            child: Image.network(url, width: 64, height: 48, fit: BoxFit.cover),
                          ),
                        )).toList(),
                      ),
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

// ─── Filter bottom sheet ──────────────────────────────────────────────────────

class _FilterSheet extends StatefulWidget {
  final _DateFilter current;
  final DateTime?   customFrom;
  final DateTime?   customTo;
  final void Function(_DateFilter, DateTime?, DateTime?) onApply;

  const _FilterSheet({
    required this.current,
    required this.customFrom,
    required this.customTo,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late _DateFilter _selected;
  DateTime? _from;
  DateTime? _to;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _from     = widget.customFrom;
    _to       = widget.customTo;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? (_from ?? now) : (_to ?? now),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate:  now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? const ColorScheme.dark(primary: _kTurkuaz, surface: Color(0xFF0D1A30))
              : ColorScheme.light(primary: _kTurkuaz),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) { _from = picked; } else { _to = picked; }
      _selected = _DateFilter.custom;
    });
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }

  String _todayLabel() {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final n = DateTime.now();
    return '${n.day} ${m[n.month - 1]} ${n.year}';
  }

  String _weekLabel() {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final n = DateTime.now();
    final start = n.subtract(Duration(days: n.weekday - 1));
    final end   = start.add(const Duration(days: 6));
    return '${start.day} – ${end.day} ${m[end.month - 1]} ${end.year}';
  }

  void _apply() {
    widget.onApply(
      _selected,
      _selected == _DateFilter.custom ? _from : null,
      _selected == _DateFilter.custom ? _to   : null,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final kSheet   = isDark ? const Color(0xFF0B1322) : Colors.white;
    final kCard    = isDark ? const Color(0xFF0D1A30) : const Color(0xFFF3F6FA);
    final kBorder  = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kHandle  = isDark ? Colors.white.withValues(alpha: 0.10) : const Color(0xFFD9E1EA);
    final kText    = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim     = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);

    final options = [
      (
        filter: _DateFilter.all,
        icon: Icons.format_list_bulleted_rounded,
        iconBg: _kTurkuaz.withValues(alpha: 0.12),
        iconColor: _kTurkuaz,
        label: 'All events',
        sub: 'Show everything',
      ),
      (
        filter: _DateFilter.today,
        icon: Icons.calendar_today_rounded,
        iconBg: _kMagenta.withValues(alpha: 0.12),
        iconColor: _kMagenta,
        label: 'Today',
        sub: _todayLabel(),
      ),
      (
        filter: _DateFilter.thisWeek,
        icon: Icons.date_range_rounded,
        iconBg: _kMavi.withValues(alpha: 0.12),
        iconColor: _kMavi,
        label: 'This week',
        sub: _weekLabel(),
      ),
      (
        filter: _DateFilter.custom,
        icon: Icons.tune_rounded,
        iconBg: _kTuruncu.withValues(alpha: 0.12),
        iconColor: _kTuruncu,
        label: 'Custom range',
        sub: (_from != null && _to != null)
            ? '${_fmt(_from!)} – ${_fmt(_to!)}'
            : (_from != null)
                ? 'From ${_fmt(_from!)}'
                : 'Pick your own dates',
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: kSheet,
        border: Border(top: BorderSide(color: isDark ? const Color(0xFF1E3060) : const Color(0xFFE5E7EB))),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 32, height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(color: kHandle, borderRadius: BorderRadius.circular(2)),
            ),
          ),

          Row(children: [
            const Icon(Icons.tune_rounded, size: 18, color: _kMagenta),
            const SizedBox(width: 8),
            Text('Filter by date',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: kText)),
          ]),
          const SizedBox(height: 16),

          // Options
          ...options.map((o) {
            final isActive = _selected == o.filter;
            return GestureDetector(
              onTap: () => setState(() => _selected = o.filter),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  color: isActive ? _kTurkuaz.withValues(alpha: 0.08) : kCard,
                  border: Border.all(
                    color: isActive ? _kTurkuaz : kBorder,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: o.iconBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(o.icon, size: 17, color: o.iconColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(o.label,
                            style: TextStyle(
                              fontSize: 13.5, fontWeight: FontWeight.w700,
                              color: isActive ? kText : kText,
                            )),
                        Text(o.sub,
                            style: TextStyle(fontSize: 11, color: kDim, height: 1.3)),
                      ],
                    ),
                  ),
                  if (isActive)
                    Container(
                      width: 20, height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _kTurkuaz.withValues(alpha: 0.12),
                        border: Border.all(color: _kTurkuaz, width: 1.5),
                      ),
                      child: const Icon(Icons.check_rounded, size: 11, color: _kTurkuaz),
                    ),
                ]),
              ),
            );
          }),

          // Custom range date pickers — only visible when custom is selected
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _selected == _DateFilter.custom
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                Expanded(child: _RangePicker(
                  label: 'From',
                  value: _from != null ? _fmt(_from!) : null,
                  active: _from != null,
                  kCard: kCard, kBorder: kBorder, kDim: kDim,
                  onTap: () => _pickDate(isFrom: true),
                )),
                const SizedBox(width: 8),
                Expanded(child: _RangePicker(
                  label: 'To',
                  value: _to != null ? _fmt(_to!) : null,
                  active: _to != null,
                  kCard: kCard, kBorder: kBorder, kDim: kDim,
                  onTap: () => _pickDate(isFrom: false),
                )),
              ]),
            ),
            secondChild: const SizedBox(width: double.infinity, height: 14),
          ),

          // Apply button
          SizedBox(
            width: double.infinity,
            child: GestureDetector(
              onTap: _apply,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _kTurkuaz,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(color: _kTurkuaz.withValues(alpha: 0.25),
                        blurRadius: 20, offset: const Offset(0, 6)),
                  ],
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_rounded, size: 16, color: Color(0xFF06091A)),
                    SizedBox(width: 8),
                    Text('Apply Filter',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800,
                            color: Color(0xFF06091A))),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Range date picker ────────────────────────────────────────────────────────

class _RangePicker extends StatelessWidget {
  final String  label;
  final String? value;
  final bool    active;
  final Color   kCard;
  final Color   kBorder;
  final Color   kDim;
  final VoidCallback onTap;

  const _RangePicker({
    required this.label, required this.value, required this.active,
    required this.kCard, required this.kBorder, required this.kDim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final kText = Theme.of(context).brightness == Brightness.dark
        ? const Color(0xFFEEF2FF) : const Color(0xFF111827);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: active ? _kTurkuaz : kBorder, width: 1.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 14,
              color: active ? _kTurkuaz : kDim),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value ?? label,
              style: TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w500,
                color: value != null ? kText : kDim,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Edit scope sheet ─────────────────────────────────────────────────────────

class _EditScopeSheet extends StatelessWidget {
  final VenueUpcomingEvent event;
  const _EditScopeSheet({required this.event});

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
                decoration: BoxDecoration(color: _kTurkuaz.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.edit_outlined, size: 15, color: _kTurkuaz),
              ),
              const SizedBox(width: 10),
              Text('Edit recurring event', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
            ]),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text('Which events do you want to edit?',
                style: TextStyle(fontSize: 13, color: kDim)),
          ),
          _ScopeOption(label: 'Only this event', sublabel: 'Just this occurrence', icon: Icons.event_outlined,
              color: _kTurkuaz, onTap: () => Navigator.pop(context, 'this')),
          _ScopeOption(label: 'This and all following', sublabel: 'This and future occurrences', icon: Icons.event_repeat_outlined,
              color: _kMavi, onTap: () => Navigator.pop(context, 'thisAndFollowing')),
          _ScopeOption(label: 'All events in series', sublabel: 'Every occurrence', icon: Icons.repeat_rounded,
              color: _kMagenta, onTap: () => Navigator.pop(context, 'all')),
          const SizedBox(height: 8),
        ],
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


// ─── Recurring series bottom sheet ───────────────────────────────────────────

class _RecurringSeriesSheet extends StatelessWidget {
  final List<_RecurringSeries> series;
  final ValueChanged<String> onSelect;
  final Color kCard;
  final Color kText;
  final Color kDim;
  final Color kBorder;

  const _RecurringSeriesSheet({
    required this.series,
    required this.onSelect,
    required this.kCard,
    required this.kText,
    required this.kDim,
    required this.kBorder,
  });

  @override
  Widget build(BuildContext context) {
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
                width: 30, height: 30,
                decoration: BoxDecoration(color: _kMagenta.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(9)),
                child: const Icon(Icons.repeat_rounded, size: 14, color: _kMagenta),
              ),
              const SizedBox(width: 10),
              Text('Recurring Series', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: kText)),
            ]),
          ),
          const SizedBox(height: 8),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: series.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: kBorder.withValues(alpha: 0.5)),
              itemBuilder: (_, i) {
                final s = series[i];
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  leading: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: _kMagenta.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.repeat_rounded, size: 16, color: _kMagenta),
                  ),
                  title: Text(s.title, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: kText),
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${s.count} events · Next: ${s.next.formattedDate}',
                      style: TextStyle(fontSize: 11, color: kDim)),
                  trailing: const Icon(Icons.chevron_right_rounded, size: 18, color: _kMagenta),
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(s.ruleId);
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ─── Recurring series data ────────────────────────────────────────────────────

class _RecurringSeries {
  final String ruleId;
  final String title;
  final int count;
  final VenueUpcomingEvent next;

  const _RecurringSeries({
    required this.ruleId,
    required this.title,
    required this.count,
    required this.next,
  });
}

