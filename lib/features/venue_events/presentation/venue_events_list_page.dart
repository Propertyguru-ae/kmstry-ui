import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'add_venue_event_page.dart';
import '../data/venue_event_repository.dart';

enum _DateFilter { all, today, thisWeek, custom }

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
  final _repo = VenueEventRepository();

  _DateFilter _filter     = _DateFilter.all;
  DateTime?   _customFrom;
  DateTime?   _customTo;

  static const _kRed = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    _events = List.from(widget.events);
  }

  List<VenueUpcomingEvent> get _filtered {
    final now  = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (_filter) {
      case _DateFilter.all:
        return _events;
      case _DateFilter.today:
        return _events.where((e) {
          final d = e.startAt.toLocal();
          return d.year == today.year && d.month == today.month && d.day == today.day;
        }).toList();
      case _DateFilter.thisWeek:
        final weekEnd = today.add(const Duration(days: 7));
        return _events.where((e) {
          final d = e.startAt.toLocal();
          return !d.isBefore(today) && d.isBefore(weekEnd);
        }).toList();
      case _DateFilter.custom:
        final from = _customFrom != null ? DateTime(_customFrom!.year, _customFrom!.month, _customFrom!.day) : null;
        final to   = _customTo   != null ? DateTime(_customTo!.year,   _customTo!.month,   _customTo!.day, 23, 59, 59) : null;
        return _events.where((e) {
          final d = e.startAt.toLocal();
          if (from != null && d.isBefore(from)) return false;
          if (to   != null && d.isAfter(to))   return false;
          return true;
        }).toList();
    }
  }

  String get _filterLabel {
    switch (_filter) {
      case _DateFilter.all:      return 'All';
      case _DateFilter.today:    return 'Today';
      case _DateFilter.thisWeek: return 'This week';
      case _DateFilter.custom:
        final fmt = (DateTime d) {
          const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          return '${d.day} ${m[d.month - 1]}';
        };
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
        onApply: (filter, from, to) {
          setState(() {
            _filter     = filter;
            _customFrom = from;
            _customTo   = to;
          });
        },
      ),
    );
  }

  Future<void> _openEdit(VenueUpcomingEvent event) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddVenueEventPage(venueId: widget.venueId, existing: event),
      ),
    );
    if (result == true && mounted) {
      widget.onRefresh();
      Navigator.pop(context, true);
    }
  }

  Future<void> _delete(VenueUpcomingEvent event) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0B1322) : Colors.white,
        title: Text('Delete Event',
            style: TextStyle(color: isDark ? const Color(0xFFC8D8F0) : const Color(0xFF111827))),
        content: Text('"${event.title}" will be permanently deleted.',
            style: TextStyle(color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B))),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: _kRed)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteEvent(venueId: widget.venueId, eventId: event.id);
      setState(() => _events.removeWhere((e) => e.id == event.id));
      widget.onRefresh();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete event'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final colors   = theme.colorScheme;
    final kBg      = isDark ? const Color(0xFF06091A) : Colors.white;
    final kAppBar  = isDark ? const Color(0xFF06091A) : Colors.white;
    final kBorder  = isDark ? Colors.white.withValues(alpha: 0.05) : const Color(0xFFD9E1EA);
    final kDim     = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kText    = colors.onSurface;
    final filtered = _filtered;
    final filterActive = _filter != _DateFilter.all;

    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kAppBar,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('All Events',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kText)),
        actions: [
          GestureDetector(
            onTap: _showFilterSheet,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune_rounded, size: 18,
                      color: filterActive ? colors.primary : kDim),
                  const SizedBox(width: 5),
                  Text(
                    _filterLabel,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: filterActive ? colors.primary : kDim,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: kBorder),
        ),
      ),
      body: filtered.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.event_outlined, size: 52, color: kDim),
                  const SizedBox(height: 12),
                  Text(
                    _filter == _DateFilter.all ? 'No events yet' : 'No events for this period',
                    style: TextStyle(color: kDim, fontSize: 14),
                  ),
                  if (_filter != _DateFilter.all) ...[
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () => setState(() { _filter = _DateFilter.all; _customFrom = null; _customTo = null; }),
                      child: Text('Clear filter',
                          style: TextStyle(color: colors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
              itemCount: filtered.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _EventListCard(
                  event:    filtered[i],
                  onEdit:   () => _openEdit(filtered[i]),
                  onDelete: () => _delete(filtered[i]),
                ),
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
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final kCard    = isDark ? const Color(0xFF0D1A30) : Colors.white;
    final kPrimary = Theme.of(context).colorScheme.primary;
    final now      = DateTime.now();
    final initial  = isFrom ? (_from ?? now) : (_to ?? now);
    final picked   = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate:  now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: isDark
              ? ColorScheme.dark(primary: kPrimary, surface: kCard)
              : ColorScheme.light(primary: kPrimary, surface: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) _from = picked; else _to = picked;
      _selected = _DateFilter.custom;
    });
  }

  String _fmt(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
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
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    final colors   = theme.colorScheme;
    final kSheet   = isDark ? const Color(0xFF0B1322) : Colors.white;
    final kCard    = isDark ? const Color(0xFF0D1A30) : const Color(0xFFF7F8FA);
    final kBorder  = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kDim     = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kText    = colors.onSurface;
    final kHandle  = isDark ? Colors.white.withValues(alpha: 0.15) : const Color(0xFFD9E1EA);

    return Container(
      decoration: BoxDecoration(
        color: kSheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 38, height: 4,
              decoration: BoxDecoration(color: kHandle, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Filter by date',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kText)),
          const SizedBox(height: 14),

          ...[
            (_DateFilter.all,      'All events',  Icons.list_outlined),
            (_DateFilter.today,    'Today',       Icons.today_outlined),
            (_DateFilter.thisWeek, 'This week',   Icons.date_range_outlined),
          ].map((item) {
            final (filter, label, icon) = item;
            final active = _selected == filter;
            return GestureDetector(
              onTap: () => setState(() => _selected = filter),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: active ? colors.primary.withValues(alpha: 0.10) : kCard,
                  border: Border.all(color: active ? colors.primary : kBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(icon, size: 16, color: active ? colors.primary : kDim),
                  const SizedBox(width: 10),
                  Text(label,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                          color: active ? colors.primary : kText)),
                  if (active) ...[
                    const Spacer(),
                    Icon(Icons.check_circle, size: 16, color: colors.primary),
                  ],
                ]),
              ),
            );
          }),

          const SizedBox(height: 4),
          Text('Custom range',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: kDim)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _DatePicker(
              label: 'From',
              value: _from != null ? _fmt(_from!) : null,
              onTap: () => _pickDate(isFrom: true),
              active: _selected == _DateFilter.custom && _from != null,
            )),
            const SizedBox(width: 10),
            Expanded(child: _DatePicker(
              label: 'To',
              value: _to != null ? _fmt(_to!) : null,
              onTap: () => _pickDate(isFrom: false),
              active: _selected == _DateFilter.custom && _to != null,
            )),
          ]),

          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _apply,
              style: FilledButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Apply',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}

class _DatePicker extends StatelessWidget {
  final String  label;
  final String? value;
  final VoidCallback onTap;
  final bool active;

  const _DatePicker({required this.label, required this.value, required this.onTap, required this.active});

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final colors  = theme.colorScheme;
    final kCard   = isDark ? const Color(0xFF0D1A30) : const Color(0xFFF7F8FA);
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kDim    = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kText   = colors.onSurface;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: active ? colors.primary : kBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          Icon(Icons.calendar_today_outlined, size: 13,
              color: active ? colors.primary : kDim),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              value ?? label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
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

// ─── Event list card ──────────────────────────────────────────────────────────

class _EventListCard extends StatelessWidget {
  final VenueUpcomingEvent event;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _EventListCard({required this.event, required this.onEdit, required this.onDelete});

  static const _kRed = Color(0xFFEF4444);

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isDark  = theme.brightness == Brightness.dark;
    final colors  = theme.colorScheme;
    final kCard   = isDark ? const Color(0xFF0D1A30) : Colors.white;
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kDim    = isDark ? const Color(0xFF3A5070) : const Color(0xFF5D6B7B);
    final kText   = colors.onSurface;

    final photos = event.photos.isNotEmpty
        ? event.photos
        : (event.photo != null ? [event.photo!] : <String>[]);

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
        boxShadow: isDark ? null : [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(event.title,
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kText),
                    maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
              GestureDetector(
                onTap: onEdit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Icon(Icons.edit_outlined, size: 18, color: colors.primary),
                ),
              ),
              GestureDetector(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.only(left: 2, right: 4, top: 2, bottom: 2),
                  child: const Icon(Icons.delete_outline, size: 18, color: _kRed),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.calendar_today_outlined, size: 11, color: colors.primary),
            const SizedBox(width: 4),
            Expanded(child: Text(event.formattedDate,
                style: TextStyle(fontSize: 11.5, color: kDim))),
            if (event.priceAed != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: event.priceAed == 0
                      ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                      : colors.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  event.priceAed == 0 ? 'Free' : 'AED ${event.priceAed}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                      color: event.priceAed == 0 ? const Color(0xFF22C55E) : colors.primary),
                ),
              ),
          ]),
          if (event.description != null && event.description!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(event.description!,
                style: TextStyle(fontSize: 12.5, color: kDim, height: 1.4),
                maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(
              children: photos.map((url) => Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(url, width: 64, height: 64, fit: BoxFit.cover),
                ),
              )).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
