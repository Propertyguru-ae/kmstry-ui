import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import 'package:kmstry_frontend/core/permissions/location_permission_service.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue_events/data/venue_event_repository.dart';
import 'package:kmstry_frontend/features/venue_events/presentation/venue_event_detail_page.dart';

const _kMagenta = Color(0xFFE020D8);
const _kTurkuaz = Color(0xFF1FD9A8);
const _kMavi = Color(0xFF1A9FE8);
const _kTuruncu = Color(0xFFF08838);

/// "Happening Nearby" → See more: takip edilmeyen mekanların yaklaşan tüm
/// event'leri. My Events sayfasıyla aynı takvim/filtre dilini kullanır.
class DiscoverEventsPage extends StatefulWidget {
  const DiscoverEventsPage({
    super.key,
    this.latitude,
    this.longitude,
    this.scope = 'others',
    this.title = 'Happening Nearby',
  });

  final double? latitude;
  final double? longitude;

  /// 'others' → takip edilmeyen mekanlar (Happening Nearby).
  /// 'followed' → takip edilen mekanlar (Up Next at Your Spots).
  final String scope;
  final String title;

  @override
  State<DiscoverEventsPage> createState() => _DiscoverEventsPageState();
}

class _DiscoverEventsPageState extends State<DiscoverEventsPage> {
  final _repo = VenueEventRepository();
  final _scroll = ScrollController();
  final _stripController = ScrollController();
  static const int _pageSize = 20;

  double? _lat;
  double? _lng;

  final List<TodayEvent> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  Set<String> _calendarEventDays = <String>{};

  late DateTime _selectedDay;
  DateTime? _rangeEnd;
  bool _rangeMode = false;
  late DateTime _viewMonth;
  bool _filterOffer = false;
  bool _filterPartner = false;

  static const _monthNames = [
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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedDay = DateTime(now.year, now.month, now.day);
    _viewMonth = DateTime(now.year, now.month);
    _lat = widget.latitude;
    _lng = widget.longitude;
    _scroll.addListener(_onScroll);
    _bootstrap();
    _scrollToSelected();
  }

  @override
  void dispose() {
    _scroll.dispose();
    _stripController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    if (_lat == null || _lng == null) {
      try {
        if (await LocationPermissionService().isGranted()) {
          final pos = await Geolocator.getLastKnownPosition();
          _lat ??= pos?.latitude;
          _lng ??= pos?.longitude;
        }
      } catch (_) {}
    }
    await _loadCalendarSummary();
    await _reload();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    if (_scroll.position.pixels >=
            _scroll.position.maxScrollExtent - 400 &&
        !_loadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  String get _serverWhen {
    if (_rangeMode) return 'all';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(_selectedDay, today)) return 'today';
    if (_selectedDay.year == today.year && _selectedDay.month == today.month) {
      return 'month';
    }
    return 'all';
  }

  String? get _platform => null;

  String? get _calendarPlatform => null;

  DateTime get _queryFrom => DateTime(
    _selectedDay.year,
    _selectedDay.month,
    _selectedDay.day,
  );

  DateTime get _queryTo {
    final end = _rangeEnd ?? _selectedDay;
    return DateTime(end.year, end.month, end.day).add(const Duration(days: 1));
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
      _items.clear();
      _hasMore = true;
    });
    try {
      final events = await _repo.getDiscoverEvents(
        latitude: _lat,
        longitude: _lng,
        limit: _pageSize,
        offset: 0,
        platform: _platform,
        when: _serverWhen,
        from: _queryFrom,
        to: _queryTo,
        scope: widget.scope,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(events);
        _loading = false;
        _hasMore = events.length == _pageSize;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items.clear();
        _loading = false;
        _error = 'Events could not be loaded.';
      });
    }
  }

  Future<void> _loadCalendarSummary() async {
    try {
      final days = await _repo.getDiscoverEventsCalendarDays(
        year: _viewMonth.year,
        month: _viewMonth.month,
        platform: _calendarPlatform,
        scope: widget.scope,
      );
      if (!mounted) return;
      setState(() => _calendarEventDays = days);
    } catch (_) {
      if (mounted) setState(() => _calendarEventDays = <String>{});
    }
  }

  Future<void> _loadMore() async {
    setState(() => _loadingMore = true);
    try {
      final events = await _repo.getDiscoverEvents(
        latitude: _lat,
        longitude: _lng,
        limit: _pageSize,
        offset: _items.length,
        platform: _platform,
        when: _serverWhen,
        from: _queryFrom,
        to: _queryTo,
        scope: widget.scope,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(events);
        _loadingMore = false;
        _hasMore = events.length == _pageSize;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
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
    var result = _items.where((item) {
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
    return _calendarEventDays;
  }

  String _dayKey(DateTime d) {
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  bool _dayHasEvent(DateTime d) => _daysWithEvents.contains(_dayKey(d));

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _scrollToSelected() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_stripController.hasClients) return;
      final idx = _daysInMonth.indexWhere((d) => _sameDay(d, _selectedDay));
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
    _loadCalendarSummary();
    _reload();
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
          widget.title,
          style: TextStyle(
            color: colors.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
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
                          '${_monthNames[_viewMonth.month - 1]} ${_viewMonth.year}',
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
                        _loadCalendarSummary();
                        _reload();
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
                  onTap: () {
                    setState(() {
                      _rangeMode = !_rangeMode;
                      if (!_rangeMode) _rangeEnd = null;
                    });
                    _reload();
                  },
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
                  final isSelected = _sameDay(d, _selectedDay);
                  final isToday = _sameDay(d, today);
                  final isPast = d.isBefore(today);
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
                    onTap: isPast
                        ? null
                        : () {
                      setState(() => _selectedDay = d);
                      _reload();
                    },
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
                          color: isPast
                              ? kBorder.withValues(alpha: 0.22)
                              : isSelected
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
                              color: isPast
                                  ? kDim.withValues(alpha: 0.34)
                                  : isSelected
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
                              color: isPast
                                  ? kDim.withValues(alpha: 0.42)
                                  : isSelected
                                  ? Colors.white
                                  : kText,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 4,
                            height: 4,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: !isPast && hasEvent
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
                      onTap: () => _pickDate(isStart: true),
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
                      onTap: () => _pickDate(isStart: false),
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
                  onTap: () {
                    setState(() => _filterOffer = !_filterOffer);
                    _reload();
                  },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Partner Benefits',
                  icon: Icons.handshake_outlined,
                  active: _filterPartner,
                  color: _kMavi,
                  kBorder: kBorder,
                  kDim: kDim,
                  onTap: () {
                    setState(() => _filterPartner = !_filterPartner);
                    _reload();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: borderColor),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _reload,
              child: _buildBody(colors, filtered),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate({required bool isStart}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _selectedDay : (_rangeEnd ?? _selectedDay),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _selectedDay = DateTime(picked.year, picked.month, picked.day);
        _viewMonth = DateTime(picked.year, picked.month);
        if (_rangeEnd != null && !_rangeEnd!.isAfter(_selectedDay)) {
          _rangeEnd = null;
        }
      } else {
        _rangeEnd = DateTime(picked.year, picked.month, picked.day);
      }
    });
    _reload();
  }

  Widget _buildBody(ColorScheme colors, List<TodayEvent> filtered) {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 80),
            child: Center(child: CircularProgressIndicator(color: colors.primary)),
          ),
        ],
      );
    }
    if (_error != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _EmptyEventsState(message: _error!, icon: Icons.error_outline),
        ],
      );
    }
    if (filtered.isEmpty) {
      return ListView(
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
                onPressed: () {
                  setState(() {
                    _filterOffer = false;
                    _filterPartner = false;
                  });
                  _reload();
                },
                child: const Text('Clear filters'),
              ),
            ),
        ],
      );
    }

    return ListView.builder(
      controller: _scroll,
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      itemCount: filtered.length + (_loadingMore ? 1 : 0),
      itemBuilder: (_, i) {
        if (i == filtered.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        final event = filtered[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _NearbyEventRow(item: event, onTap: () => _openEvent(event)),
        );
      },
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
    required this.kBg,
    required this.kCard,
    required this.kBorder,
    required this.kText,
    required this.kDim,
  });

  final DateTime current;
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

class _EmptyEventsState extends StatelessWidget {
  const _EmptyEventsState({required this.message, required this.icon});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final kDim = isDark ? const Color(0xFF8EA0BA) : const Color(0xFF4F5D6D);
    return Padding(
      padding: const EdgeInsets.only(top: 86),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 30, color: kDim.withValues(alpha: 0.65)),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: kDim,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NearbyEventRow extends StatelessWidget {
  const _NearbyEventRow({required this.item, required this.onTap});

  final TodayEvent item;
  final VoidCallback onTap;

  static const _months = [
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

  String _dateLabel(DateTime dt) {
    final l = dt.toLocal();
    final time =
        '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
    return '${l.day} ${_months[l.month - 1]} · $time';
  }

  String? _distanceLabel(int? m) {
    if (m == null) return null;
    if (m < 1000) return '${m}m away';
    return '${(m / 1000).toStringAsFixed(m < 10000 ? 1 : 0)}km away';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final kCard = isDark ? const Color(0xFF0D1525) : Colors.white;
    final kBorder = isDark ? const Color(0xFF162040) : const Color(0xFFE1E7EF);
    final kText = isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827);
    final kDim = isDark ? const Color(0xFF8EA0BA) : const Color(0xFF4F5D6D);
    final event = item.event;
    final photo = (event.photo != null && event.photo!.isNotEmpty)
        ? event.photo!
        : (event.photos.isNotEmpty ? event.photos.first : (item.venuePhoto ?? ''));
    final distance = _distanceLabel(item.distanceMeters);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: kCard,
            border: Border.all(color: kBorder),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: photo.isNotEmpty
                      ? CachedImage(photo, fit: BoxFit.cover)
                      : Container(
                          color: colors.primary.withValues(alpha: 0.12),
                          child: Icon(Icons.event, color: colors.primary),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kText,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.venueName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: kDim,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _meta(Icons.schedule_rounded, _dateLabel(event.startAt), kDim),
                        if (distance != null)
                          _meta(Icons.near_me_rounded, distance, _kMavi),
                        if (event.hasOffer)
                          _meta(Icons.local_offer_outlined, 'Offer', _kTuruncu),
                        if (event.partnershipCount > 0)
                          _meta(Icons.handshake_outlined, 'Partner', _kMavi),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: kDim, size: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _meta(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
