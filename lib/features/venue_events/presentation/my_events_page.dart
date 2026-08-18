import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);
const _kRed = Color(0xFFEF4444);

class MyEventsPage extends StatefulWidget {
  const MyEventsPage({super.key, this.initialFilter = 'today'});

  final String initialFilter;

  @override
  State<MyEventsPage> createState() => _MyEventsPageState();
}

class _MyEventsPageState extends State<MyEventsPage> {
  final _repo = VenueEventRepository();
  List<TodayEvent> _events = const [];
  bool _loading = true;
  String? _error;

  late DateTime _selectedDay;
  DateTime? _rangeEnd;
  bool _rangeMode = false;
  late DateTime _viewMonth;
  bool _filterOffer = false;
  bool _filterPartner = false;

  final _stripController = ScrollController();

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = _initialSelectedDay(now);
    _viewMonth = DateTime(_selectedDay.year, _selectedDay.month);
    _load();
    _scrollToSelected();
  }

  @override
  void dispose() {
    _stripController.dispose();
    super.dispose();
  }

  DateTime _initialSelectedDay(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    switch (widget.initialFilter) {
      case 'upcoming':
        return today.add(const Duration(days: 1));
      case 'past':
        return today.subtract(const Duration(days: 1));
      case 'today':
      case 'all':
      default:
        return today;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final events = await _repo.getMyEvents(filter: 'all');
      if (!mounted) return;
      setState(() {
        _events = events;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _events = const [];
        _loading = false;
        _error = 'Events could not be loaded.';
      });
    }
  }

  void _openEvent(TodayEvent item) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            VenueEventDetailPage(event: item.event, venueId: item.venueId),
      ),
    );
  }

  List<DateTime> get _daysInMonth {
    final first = _viewMonth;
    final last = DateTime(first.year, first.month + 1, 0);
    return List.generate(
      last.day,
      (i) => DateTime(first.year, first.month, i + 1),
    );
  }

  List<TodayEvent> get _filtered {
    final from = DateTime(
      _selectedDay.year,
      _selectedDay.month,
      _selectedDay.day,
    );
    final to = _rangeEnd ?? _selectedDay;
    final toDay = DateTime(to.year, to.month, to.day);
    var result = _events.where((item) {
      final d = item.event.startAt.toLocal();
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(from) && !day.isAfter(toDay);
    }).toList()..sort((a, b) => a.event.startAt.compareTo(b.event.startAt));
    if (_filterOffer) {
      result = result.where((item) => item.event.hasOffer).toList();
    }
    if (_filterPartner) {
      result = result.where((item) => item.event.partnershipCount > 0).toList();
    }
    return result;
  }

  Set<String> get _daysWithEvents {
    return _events.map((item) {
      final d = item.event.startAt.toLocal();
      return '${d.year}-${d.month}-${d.day}';
    }).toSet();
  }

  bool _dayHasEvent(DateTime d) =>
      _daysWithEvents.contains('${d.year}-${d.month}-${d.day}');

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripController.hasClients) return;
      final idx = _daysInMonth.indexWhere(
        (d) =>
            d.day == _selectedDay.day &&
            d.month == _selectedDay.month &&
            d.year == _selectedDay.year,
      );
      if (idx < 0) return;
      const itemW = 52.0;
      final offset =
          (idx * itemW) -
          (_stripController.position.viewportDimension / 2) +
          (itemW / 2);
      _stripController.animateTo(
        offset.clamp(0.0, _stripController.position.maxScrollExtent),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _pickMonth(
    BuildContext context,
    bool isDark,
    Color kBg,
    Color kCard,
    Color kBorder,
    Color kText,
    Color kDim,
  ) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (_) => _MonthPickerDialog(
        current: _viewMonth,
        isDark: isDark,
        kBg: kBg,
        kCard: kCard,
        kBorder: kBorder,
        kText: kText,
        kDim: kDim,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _viewMonth = picked;
      if (_selectedDay.year != picked.year ||
          _selectedDay.month != picked.month) {
        _selectedDay = picked;
        _rangeEnd = null;
      }
    });
    _scrollToSelected();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF0B0F17) : theme.scaffoldBackgroundColor;
    final kCard = isDark ? const Color(0xFF0D1525) : const Color(0xFFF3F6FA);
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFD9E1EA);
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF8EA0BA) : const Color(0xFF4F5D6D);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.06);
    final days = _daysInMonth;
    final filtered = _filtered;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    const monthNames = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.chevron_left_rounded,
            color: colors.onSurface,
            size: 28,
          ),
        ),
        title: Text(
          'My Events',
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: borderColor, height: 1),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                if (!_rangeMode) ...[
                  GestureDetector(
                    onTap: () => _pickMonth(
                      context,
                      isDark,
                      bg,
                      kCard,
                      kBorder,
                      kText,
                      kDim,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: kText,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: kDim,
                        ),
                      ],
                    ),
                  ),
                  if (_viewMonth.year != today.year ||
                      _viewMonth.month != today.month) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _viewMonth = DateTime(today.year, today.month);
                          _selectedDay = today;
                          _rangeEnd = null;
                        });
                        _scrollToSelected();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: _kTurkuaz.withValues(alpha: 0.10),
                          border: Border.all(
                            color: _kTurkuaz.withValues(alpha: 0.3),
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Today',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _kTurkuaz,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() {
                    _rangeMode = !_rangeMode;
                    if (!_rangeMode) _rangeEnd = null;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: _rangeMode
                          ? _kMagenta.withValues(alpha: 0.12)
                          : Colors.transparent,
                      border: Border.all(
                        color: _rangeMode ? _kMagenta : kBorder,
                        width: _rangeMode ? 1.5 : 1,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.date_range_rounded,
                          size: 12,
                          color: _rangeMode ? _kMagenta : kDim,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Range',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: _rangeMode ? _kMagenta : kDim,
                          ),
                        ),
                        if (_rangeMode) ...[
                          const SizedBox(width: 5),
                          const Icon(
                            Icons.close_rounded,
                            size: 11,
                            color: _kMagenta,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!_rangeMode)
            SizedBox(
              height: 72,
              child: ListView.builder(
                controller: _stripController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: days.length,
                itemBuilder: (_, i) {
                  final d = days[i];
                  final isSelected =
                      d.year == _selectedDay.year &&
                      d.month == _selectedDay.month &&
                      d.day == _selectedDay.day;
                  final isToday =
                      d.year == today.year &&
                      d.month == today.month &&
                      d.day == today.day;
                  final hasEvent = _dayHasEvent(d);
                  const dayLabels = [
                    'Mon',
                    'Tue',
                    'Wed',
                    'Thu',
                    'Fri',
                    'Sat',
                    'Sun',
                  ];
                  final label = dayLabels[(d.weekday - 1) % 7];

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
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : kDim,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${d.day}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isSelected ? Colors.white : kText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: hasEvent
                                  ? (isSelected
                                        ? Colors.white.withValues(alpha: 0.7)
                                        : _kTurkuaz)
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _DateField(
                      label: 'Start date',
                      date: _selectedDay,
                      color: _kMagenta,
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
                            kBg: bg,
                            kCard: kCard,
                            kBorder: kBorder,
                            kText: kText,
                            kDim: kDim,
                          ),
                        );
                        if (picked != null && mounted) {
                          setState(() {
                            _selectedDay = picked;
                            _viewMonth = DateTime(picked.year, picked.month);
                            if (_rangeEnd != null &&
                                !_rangeEnd!.isAfter(picked)) {
                              _rangeEnd = null;
                            }
                          });
                        }
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      size: 16,
                      color: kDim,
                    ),
                  ),
                  Expanded(
                    child: _DateField(
                      label: 'End date',
                      date: _rangeEnd,
                      color: _kMavi,
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
                            kBg: bg,
                            kCard: kCard,
                            kBorder: kBorder,
                            kText: kText,
                            kDim: kDim,
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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _FilterChip(
                  label: 'Kmstry Offer',
                  icon: Icons.local_offer_outlined,
                  active: _filterOffer,
                  color: _kTuruncu,
                  kBorder: kBorder,
                  kDim: kDim,
                  onTap: () => setState(() => _filterOffer = !_filterOffer),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Partner Benefits',
                  icon: Icons.handshake_outlined,
                  active: _filterPartner,
                  color: _kMavi,
                  kBorder: kBorder,
                  kDim: kDim,
                  onTap: () => setState(() => _filterPartner = !_filterPartner),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: borderColor),
          if (!_loading && filtered.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Text(
                    'Total: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kDim,
                    ),
                  ),
                  Text(
                    '${filtered.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _kMagenta,
                    ),
                  ),
                  Text(
                    filtered.length == 1 ? ' event' : ' events',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: kDim,
                    ),
                  ),
                ],
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 80),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    )
                  : _error != null
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _EmptyEventsState(
                          message: _error!,
                          icon: Icons.error_outline,
                        ),
                      ],
                    )
                  : filtered.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _EmptyEventsState(
                          message: _rangeEnd != null
                              ? 'No events in this range.'
                              : 'No events on this day.',
                          icon: Icons.event_busy_outlined,
                        ),
                        if (_filterOffer || _filterPartner)
                          Center(
                            child: TextButton(
                              onPressed: () => setState(() {
                                _filterOffer = false;
                                _filterPartner = false;
                              }),
                              child: const Text('Clear filters'),
                            ),
                          ),
                      ],
                    )
                  : ListView.builder(
                      physics: const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) {
                        final event = filtered[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MyEventRow(
                            item: event,
                            onTap: () => _openEvent(event),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.icon,
    required this.active,
    required this.color,
    required this.kBorder,
    required this.kDim,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool active;
  final Color color;
  final Color kBorder;
  final Color kDim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(color: active ? color : kBorder),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: active ? color : kDim),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: active ? color : kDim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthPickerDialog extends StatefulWidget {
  const _MonthPickerDialog({
    required this.current,
    required this.isDark,
    required this.kBg,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  final DateTime current;
  final bool isDark;
  final Color kBg;
  final Color kCard;
  final Color kBorder;
  final Color kText;
  final Color kDim;

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
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final now = DateTime.now();

    return Dialog(
      backgroundColor: widget.kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _year--),
                  child: Icon(Icons.chevron_left_rounded, color: widget.kDim),
                ),
                Text(
                  '$_year',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: widget.kText,
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _year++),
                  child: Icon(Icons.chevron_right_rounded, color: widget.kDim),
                ),
              ],
            ),
            const SizedBox(height: 16),
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
                final isSelected =
                    _year == widget.current.year &&
                    i + 1 == widget.current.month;
                final isNow = _year == now.year && i + 1 == now.month;
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
                    child: Text(
                      months[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: isSelected ? Colors.white : widget.kText,
                      ),
                    ),
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

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.color,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
    required this.onTap,
  });

  final String label;
  final DateTime? date;
  final Color color;
  final Color kCard;
  final Color kBorder;
  final Color kText;
  final Color kDim;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final value = date == null ? 'Select' : _formatDate(date!);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kCard,
          border: Border.all(color: kBorder),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: kDim,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: kText,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.calendar_month_rounded, size: 14, color: kDim),
          ],
        ),
      ),
    );
  }

  static String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _CalendarSheet extends StatefulWidget {
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

  final DateTime initial;
  final DateTime? minDate;
  final Set<String> daysWithEvents;
  final bool isDark;
  final Color kBg;
  final Color kCard;
  final Color kBorder;
  final Color kText;
  final Color kDim;

  @override
  State<_CalendarSheet> createState() => _CalendarSheetState();
}

class _CalendarSheetState extends State<_CalendarSheet> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.initial.year, widget.initial.month);
  }

  bool _hasEvent(DateTime d) =>
      widget.daysWithEvents.contains('${d.year}-${d.month}-${d.day}');

  @override
  Widget build(BuildContext context) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const week = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final first = DateTime(_month.year, _month.month, 1);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final leading = first.weekday - 1;
    final cells = leading + last.day;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 20),
      decoration: BoxDecoration(
        color: widget.kBg,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: widget.kBorder),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: widget.kDim.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month - 1),
                  ),
                  icon: Icon(Icons.chevron_left_rounded, color: widget.kDim),
                ),
                Expanded(
                  child: Center(
                    child: Text(
                      '${months[_month.month - 1]} ${_month.year}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: widget.kText,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _month = DateTime(_month.year, _month.month + 1),
                  ),
                  icon: Icon(Icons.chevron_right_rounded, color: widget.kDim),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: week
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: widget.kDim,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 8),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: cells,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 8,
                crossAxisSpacing: 6,
              ),
              itemBuilder: (_, i) {
                if (i < leading) return const SizedBox.shrink();
                final day = i - leading + 1;
                final d = DateTime(_month.year, _month.month, day);
                final selected =
                    d.year == widget.initial.year &&
                    d.month == widget.initial.month &&
                    d.day == widget.initial.day;
                final disabled =
                    widget.minDate != null &&
                    !d.isAfter(
                      DateTime(
                        widget.minDate!.year,
                        widget.minDate!.month,
                        widget.minDate!.day,
                      ).subtract(const Duration(days: 1)),
                    );
                final hasEvent = _hasEvent(d);

                return GestureDetector(
                  onTap: disabled ? null : () => Navigator.pop(context, d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? _kMagenta : Colors.transparent,
                      border: Border.all(
                        color: selected
                            ? _kMagenta
                            : hasEvent
                            ? _kTurkuaz.withValues(alpha: 0.45)
                            : widget.kBorder,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: disabled
                                ? widget.kDim.withValues(alpha: 0.35)
                                : selected
                                ? Colors.white
                                : widget.kText,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: hasEvent
                                ? selected
                                      ? Colors.white.withValues(alpha: 0.75)
                                      : _kTurkuaz
                                : Colors.transparent,
                          ),
                        ),
                      ],
                    ),
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

class _MyEventRow extends StatelessWidget {
  const _MyEventRow({required this.item, required this.onTap});

  final TodayEvent item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final event = item.event;
    final isFree = event.priceAed == null || event.priceAed == 0;
    final local = event.startAt.toLocal();
    final dateLabel = _dateLabel(local);
    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
    final cardColor = isDark ? const Color(0xFF0D1525) : Colors.white;
    final borderColor = isDark
        ? const Color(0xFF162040)
        : const Color(0xFFD9E1EA);
    final textColor = isDark
        ? const Color(0xFFEEF2FF)
        : const Color(0xFF111827);
    final dimColor = isDark ? const Color(0xFF7F90AA) : const Color(0xFF4F5D6D);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cardColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? null
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 52,
              alignment: Alignment.center,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: dimColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    time,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: _kMagenta,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isFree
                          ? _kTurkuaz.withValues(alpha: 0.12)
                          : _kTuruncu.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      isFree ? 'Free' : '${event.currency} ${event.priceAed}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: isFree ? _kTurkuaz : _kTuruncu,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 1,
              height: 44,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.08),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    item.venueName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: dimColor,
                      fontSize: 11.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (event.description != null &&
                      event.description!.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      event.description!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: dimColor,
                        fontSize: 11.5,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (event.hasOffer ||
                      event.partnershipCount > 0 ||
                      event.capacity != null ||
                      event.rsvpCount > 0) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: [
                        if (event.hasOffer)
                          _EventBadge(
                            icon: Icons.local_offer_outlined,
                            label: event.offerTypeLabel!,
                            color: _kTuruncu,
                          ),
                        if (event.partnershipCount > 0)
                          _EventBadge(
                            icon: Icons.handshake_outlined,
                            label:
                                '${event.partnershipCount} partner${event.partnershipCount > 1 ? 's' : ''}',
                            color: _kMavi,
                          ),
                        if (event.capacity != null || event.rsvpCount > 0)
                          _EventBadge(
                            icon: Icons.people_outline_rounded,
                            label: event.capacity != null
                                ? '${event.rsvpCount}/${event.capacity}'
                                : '${event.rsvpCount}',
                            color:
                                (event.capacity != null &&
                                    event.rsvpCount >= event.capacity!)
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
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (event.isRecurring)
                  Container(
                    margin: const EdgeInsets.only(bottom: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _kMagenta.withValues(alpha: 0.10),
                      border: Border.all(
                        color: _kMagenta.withValues(alpha: 0.25),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.repeat_rounded, size: 9, color: _kMagenta),
                        SizedBox(width: 3),
                        Text(
                          'Repeat',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: _kMagenta,
                          ),
                        ),
                      ],
                    ),
                  ),
                Icon(Icons.chevron_right_rounded, size: 16, color: dimColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    if (date.year == now.year &&
        date.month == now.month &&
        date.day == now.day) {
      return 'Today';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (date.year == tomorrow.year &&
        date.month == tomorrow.month &&
        date.day == tomorrow.day) {
      return 'Tomorrow';
    }
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }
}

class _EventBadge extends StatelessWidget {
  const _EventBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyEventsState extends StatelessWidget {
  const _EmptyEventsState({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 96),
      child: Column(
        children: [
          Icon(icon, size: 38, color: colors.onSurface.withValues(alpha: 0.32)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: colors.onSurface.withValues(alpha: 0.72),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
