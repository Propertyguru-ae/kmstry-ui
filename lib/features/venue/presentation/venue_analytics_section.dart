import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:kmstry_frontend/features/venue/data/venue_analytics_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_owner_repository.dart';

// ── Brand colors ────────────────────────────────────────────────────────────
const _kMagenta = Color(0xFFE020D8);
const _kTeal = Color(0xFF1FD9A8);
const _kBlue = Color(0xFF1A9FE8);
const _kOrange = Color(0xFFF08838);
const _kPurple = Color(0xFF3D1F8C);

/// Dashboard içine gömülen, kendi verisini yükleyen analytics bloğu:
/// aralık seçici + özet + trend + peak hours + gender + age + intents + reports.
class VenueAnalyticsSection extends StatefulWidget {
  final String venueId;

  const VenueAnalyticsSection({super.key, required this.venueId});

  @override
  State<VenueAnalyticsSection> createState() => VenueAnalyticsSectionState();
}

class VenueAnalyticsSectionState extends State<VenueAnalyticsSection> {
  final _repo = VenueOwnerRepository();
  String _range = '7d';
  bool _loading = true;
  String? _error;
  VenueAnalytics? _data;
  List<WeeklyReport> _reports = [];
  DateTime? _customFrom;
  DateTime? _customTo;

  static const _ranges = {'7d': '7d', '30d': '30d', '90d': '90d'};

  bool get _isCustom => _customFrom != null && _customTo != null;

  String _ymd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtShort(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = _isCustom
          ? await _repo.getAnalytics(
              widget.venueId,
              from: _ymd(_customFrom!),
              to: _ymd(_customTo!),
            )
          : await _repo.getAnalytics(widget.venueId, range: _range);
      List<WeeklyReport> reports = _reports;
      try {
        reports = await _repo.getWeeklyReports(widget.venueId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _data = data;
        _reports = reports;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> refresh() => _load();

  void _changeRange(String r) {
    if (r == _range && !_isCustom) return;
    setState(() {
      _range = r;
      _customFrom = null;
      _customTo = null;
    });
    _load();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialEntryMode:
          DatePickerEntryMode.calendarOnly, // takvimden seç, kalem yok
      initialDateRange: _isCustom
          ? DateTimeRange(start: _customFrom!, end: _customTo!)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 6)),
              end: now,
            ),
      helpText: 'Select date range',
      saveText: 'Apply',
      builder: (ctx, child) {
        final base = Theme.of(ctx);
        return Theme(
          data: base.copyWith(
            colorScheme: base.colorScheme.copyWith(
              primary: _kBlue,
              onPrimary: Colors.white,
            ),
            datePickerTheme: DatePickerThemeData(
              // Aralık bandı açık ton → altındaki gün sayıları okunur kalır
              rangeSelectionBackgroundColor: _kBlue.withValues(alpha: 0.14),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _customFrom = picked.start;
      _customTo = picked.end;
    });
    _load();
  }

  String? _downloadingId;

  Future<void> _openReport(WeeklyReport r) async {
    final url = r.pdfUrl;
    if (url == null || url.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF not ready yet')));
      return;
    }
    if (_downloadingId != null) return;
    setState(() => _downloadingId = r.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await getTemporaryDirectory();
      String d(DateTime x) =>
          '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
      final fileName =
          'KMSTRY Weekly Report (${d(r.periodStart)} - ${d(r.periodEnd)}).pdf';
      final path = '${dir.path}/$fileName';
      await Dio().download(url, path);
      final res = await OpenFilex.open(path);
      if (res.type != ResultType.done && mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Open failed: ${res.message}')),
        );
      }
    } catch (e) {
      debugPrint('[report] download error: $e');
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Download failed: $e', maxLines: 3),
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title + range shortcuts + custom calendar
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              ..._ranges.entries.map((e) {
                final selected = !_isCustom && e.key == _range;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => _changeRange(e.key),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? _kBlue
                            : colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        e.value,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? Colors.white
                              : colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: _pickCustomRange,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _isCustom
                          ? _kBlue
                          : colors.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.calendar_month_rounded,
                      size: 16,
                      color: _isCustom
                          ? Colors.white
                          : colors.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (_isCustom)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                const Icon(Icons.event_rounded, size: 13, color: _kBlue),
                const SizedBox(width: 4),
                Text(
                  '${_fmtShort(_customFrom!)} – ${_fmtShort(_customTo!)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _kBlue,
                  ),
                ),
              ],
            ),
          )
        else
          const SizedBox(height: 8),

        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          _ChartCard(
            title: 'Analytics',
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text('Failed to load', style: TextStyle(color: colors.error)),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        else
          ..._buildContent(colors, _data!),
      ],
    );
  }

  List<Widget> _buildContent(ColorScheme colors, VenueAnalytics d) {
    return [
      Row(
        children: [
          Expanded(
            child: _SummaryCard(
              label: 'Total Visits',
              value: d.totalCheckins.toString(),
              hint: 'check-ins',
              icon: Icons.login_rounded,
              color: _kBlue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _SummaryCard(
              label: 'Unique Visitors',
              value: d.uniqueVisitors.toString(),
              hint: 'distinct people',
              icon: Icons.people_alt_rounded,
              color: _kTeal,
            ),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        '${d.uniqueVisitors} people checked in ${d.totalCheckins} times in this period.',
        style: TextStyle(
          fontSize: 11.5,
          color: colors.onSurface.withValues(alpha: 0.6),
        ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'New vs Returning Visitors',
        subtitle: d.privacy.repeatMetricsAvailable
            ? 'of ${d.uniqueVisitors} unique people · ${d.repeat.repeatPercent}% visited before'
            : null,
        child: !d.privacy.repeatMetricsAvailable
            ? _PrivacyProtectedChart(
                minimumVisitors: d.privacy.minimumRepeatCohortSize,
                insightLabel: 'Returning visitor insights',
              )
            : d.repeat.total == 0
            ? const _EmptyChart()
            : SizedBox(height: 180, child: _RepeatDonut(repeat: d.repeat)),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Check-in Trend',
        subtitle: _isCustom
            ? 'Grouped by period (tap a bar)'
            : (_range == '7d'
                  ? 'Daily check-ins — tap a bar'
                  : 'Grouped by period (one bar = several days) — tap a bar'),
        child: d.checkinsByDay.isEmpty
            ? const _EmptyChart()
            : SizedBox(
                height: 180,
                child: _TrendChart(points: d.checkinsByDay, color: _kBlue),
              ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Peak Hours',
        subtitle: 'Check-ins by hour (UTC)',
        child: d.peakHours.every((h) => h.count == 0)
            ? const _EmptyChart()
            : SizedBox(
                height: 180,
                child: _PeakHoursChart(hours: d.peakHours, color: _kOrange),
              ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Gender',
        child: !d.privacy.demographicsAvailable
            ? _PrivacyProtectedChart(
                minimumVisitors: d.privacy.minimumDemographicCohortSize,
                insightLabel: 'Demographic insights',
              )
            : d.gender.total == 0
            ? const _EmptyChart()
            : Column(
                children: [
                  SizedBox(height: 180, child: _GenderDonut(gender: d.gender)),
                  _SmallGroupsNotice(
                    minimumCount: d.privacy.minimumVisibleCellCount,
                  ),
                ],
              ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Age',
        child: !d.privacy.demographicsAvailable
            ? _PrivacyProtectedChart(
                minimumVisitors: d.privacy.minimumDemographicCohortSize,
                insightLabel: 'Demographic insights',
              )
            : d.ageBreakdown.every((a) => a.count == 0)
            ? const _EmptyChart()
            : Column(
                children: [
                  SizedBox(
                    height: 180,
                    child: _AgeChart(buckets: d.ageBreakdown, color: _kPurple),
                  ),
                  _SmallGroupsNotice(
                    minimumCount: d.privacy.minimumVisibleCellCount,
                  ),
                ],
              ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Visit Intents',
        subtitle: 'What visitors selected at check-in',
        child: !d.privacy.demographicsAvailable
            ? _PrivacyProtectedChart(
                minimumVisitors: d.privacy.minimumDemographicCohortSize,
                insightLabel: 'Visit intent insights',
              )
            : Column(
                children: [
                  _IntentBars(intents: d.topIntents),
                  _SmallGroupsNotice(
                    minimumCount: d.privacy.minimumVisibleCellCount,
                  ),
                ],
              ),
      ),
      const SizedBox(height: 16),
      _ChartCard(
        title: 'Weekly Reports',
        subtitle: _reports.isEmpty
            ? 'Auto-generated every Monday'
            : 'Auto-generated every Monday · ${_reports.length} total',
        child: _reports.isEmpty
            ? const _EmptyChart()
            : SizedBox(
                height: _reports.length > 5 ? 280 : null,
                child: Scrollbar(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: _reports.length <= 5,
                    physics: _reports.length > 5
                        ? const ClampingScrollPhysics()
                        : const NeverScrollableScrollPhysics(),
                    itemCount: _reports.length,
                    itemBuilder: (_, i) => _ReportRow(
                      report: _reports[i],
                      downloading: _downloadingId == _reports[i].id,
                      onDownload: () => _openReport(_reports[i]),
                    ),
                  ),
                ),
              ),
      ),
    ];
  }
}

// ── Axis scaling — Y axis always integer steps ───────────────────────────────
class _Scale {
  final double maxY;
  final double step;
  const _Scale(this.maxY, this.step);
}

_Scale _axisScale(int rawMax) {
  final m = rawMax < 1 ? 1 : rawMax;
  final step = m <= 5 ? 1 : (m / 4).ceil();
  final maxY = ((m / step).ceil()) * step;
  return _Scale(maxY.toDouble(), step.toDouble());
}

AxisTitles _intLeftTitles(double step) => AxisTitles(
  sideTitles: SideTitles(
    showTitles: true,
    interval: step,
    reservedSize: 30,
    getTitlesWidget: (v, meta) {
      if ((v % step).abs() > 0.01) return const SizedBox.shrink();
      return Text(v.toInt().toString(), style: const TextStyle(fontSize: 9));
    },
  ),
);

// ── Trend chart — always bars; adaptive day/period grouping + tap tooltip ─────

String _shortDate(String date) =>
    date.length >= 10 ? date.substring(5) : date; // MM-DD

class _TrendBucket {
  final String start;
  final String end;
  final int count;
  const _TrendBucket(this.start, this.end, this.count);

  bool get isSingleDay => start == end;
  String get axisLabel => _shortDate(start);
  String get tooltipRange => isSingleDay
      ? _shortDate(start)
      : '${_shortDate(start)} → ${_shortDate(end)}';
}

class _TrendChart extends StatelessWidget {
  final List<AnalyticsDayCount> points;
  final Color color;
  const _TrendChart({required this.points, required this.color});

  List<_TrendBucket> _bucketize() {
    if (points.length <= 12) {
      return [for (final p in points) _TrendBucket(p.date, p.date, p.count)];
    }
    final size = (points.length / 12).ceil();
    final buckets = <_TrendBucket>[];
    for (var i = 0; i < points.length; i += size) {
      final chunk = points.sublist(i, math.min(i + size, points.length));
      final total = chunk.fold<int>(0, (a, b) => a + b.count);
      buckets.add(_TrendBucket(chunk.first.date, chunk.last.date, total));
    }
    return buckets;
  }

  @override
  Widget build(BuildContext context) {
    final buckets = _bucketize();
    final rawMax = buckets
        .map((b) => b.count)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final scale = _axisScale(rawMax);
    final labelEvery = (buckets.length / 6).ceil().clamp(1, buckets.length);
    final barWidth = buckets.length <= 7
        ? 16.0
        : (buckets.length <= 10 ? 12.0 : 9.0);

    return BarChart(
      BarChartData(
        maxY: scale.maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: scale.step,
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${buckets[group.x].tooltipRange}\n${rod.toY.toInt()} check-ins',
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: _intLeftTitles(scale.step),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= buckets.length) {
                  return const SizedBox.shrink();
                }
                if (i % labelEvery != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    buckets[i].axisLabel,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < buckets.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: buckets[i].count.toDouble(),
                  color: color,
                  width: barWidth,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(3),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Peak hours bar chart ──────────────────────────────────────────────────

class _PeakHoursChart extends StatelessWidget {
  final List<AnalyticsHourCount> hours;
  final Color color;
  const _PeakHoursChart({required this.hours, required this.color});

  @override
  Widget build(BuildContext context) {
    final rawMax = hours
        .map((h) => h.count)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final scale = _axisScale(rawMax);
    return BarChart(
      BarChartData(
        maxY: scale.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: scale.step,
        ),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.black87,
            getTooltipItem: (group, gi, rod, ri) => BarTooltipItem(
              '${group.x}:00\n${rod.toY.toInt()} check-ins',
              const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: _intLeftTitles(scale.step),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 4,
              getTitlesWidget: (value, meta) {
                final h = value.toInt();
                if (h % 4 != 0) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('$h:00', style: const TextStyle(fontSize: 9)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (final h in hours)
            BarChartGroupData(
              x: h.hour,
              barRods: [
                BarChartRodData(
                  toY: h.count.toDouble(),
                  color: color,
                  width: 6,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── New vs returning donut (T22) ──────────────────────────────────────────

class _RepeatDonut extends StatelessWidget {
  final AnalyticsRepeat repeat;
  const _RepeatDonut({required this.repeat});

  @override
  Widget build(BuildContext context) {
    final total = repeat.total;
    final sections = <PieChartSectionData>[
      if (repeat.returningVisitors > 0)
        PieChartSectionData(
          value: repeat.returningVisitors.toDouble(),
          color: _kTeal,
          title: '${(repeat.returningVisitors / total * 100).round()}%',
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (repeat.newVisitors > 0)
        PieChartSectionData(
          value: repeat.newVisitors.toDouble(),
          color: _kBlue,
          title: '${(repeat.newVisitors / total * 100).round()}%',
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 34,
              sectionsSpace: 2,
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendDot(
              color: _kTeal,
              label: 'Returning',
              value: repeat.returningVisitors,
            ),
            const SizedBox(height: 8),
            _LegendDot(color: _kBlue, label: 'New', value: repeat.newVisitors),
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

// ── Gender donut ──────────────────────────────────────────────────────────

class _GenderDonut extends StatelessWidget {
  final AnalyticsGender gender;
  const _GenderDonut({required this.gender});

  @override
  Widget build(BuildContext context) {
    final total = gender.total;
    final sections = <PieChartSectionData>[
      if (gender.female > 0)
        PieChartSectionData(
          value: gender.female.toDouble(),
          color: _kMagenta,
          title: '${(gender.female / total * 100).round()}%',
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (gender.male > 0)
        PieChartSectionData(
          value: gender.male.toDouble(),
          color: _kBlue,
          title: '${(gender.male / total * 100).round()}%',
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      if (gender.other > 0)
        PieChartSectionData(
          value: gender.other.toDouble(),
          color: Colors.grey,
          title: '${(gender.other / total * 100).round()}%',
          radius: 48,
          titleStyle: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
    ];
    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 34,
              sectionsSpace: 2,
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendDot(color: _kMagenta, label: 'Female', value: gender.female),
            const SizedBox(height: 8),
            _LegendDot(color: _kBlue, label: 'Male', value: gender.male),
            if (gender.other > 0) ...[
              const SizedBox(height: 8),
              _LegendDot(
                color: Colors.grey,
                label: 'Other',
                value: gender.other,
              ),
            ],
          ],
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final int value;
  const _LegendDot({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label  $value',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// ── Age bar chart ─────────────────────────────────────────────────────────

class _AgeChart extends StatelessWidget {
  final List<AnalyticsAgeBucket> buckets;
  final Color color;
  const _AgeChart({required this.buckets, required this.color});

  @override
  Widget build(BuildContext context) {
    final visible = buckets
        .where((b) => b.bucket != 'unknown' || b.count > 0)
        .toList();
    final rawMax = visible
        .map((b) => b.count)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final scale = _axisScale(rawMax);
    return BarChart(
      BarChartData(
        maxY: scale.maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: scale.step,
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          leftTitles: _intLeftTitles(scale.step),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= visible.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    visible[i].bucket,
                    style: const TextStyle(fontSize: 9),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < visible.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: visible[i].count.toDouble(),
                  color: color,
                  width: 22,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

// ── Top intents (horizontal bars) ──────────────────────────────────────────

class _IntentBars extends StatelessWidget {
  final List<AnalyticsIntent> intents;
  const _IntentBars({required this.intents});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    // Tüm kanonik kategorileri kapsa; veride olmayanlar 0 gelir.
    final counts = {for (final k in AnalyticsIntent.allKeys) k: 0};
    for (final it in intents) {
      if (counts.containsKey(it.intent)) counts[it.intent] = it.count;
    }
    final all =
        counts.entries
            .map((e) => AnalyticsIntent(intent: e.key, count: e.value))
            .toList()
          ..sort((a, b) => b.count.compareTo(a.count));

    final maxCount = all
        .map((i) => i.count)
        .fold<int>(0, (a, b) => a > b ? a : b);
    final top = all.take(8).toList();
    return Column(
      children: top.map((it) {
        final frac = maxCount == 0 ? 0.0 : it.count / maxCount;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 120,
                child: Text(
                  it.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: frac,
                    minHeight: 14,
                    backgroundColor: colors.surfaceContainerHighest,
                    valueColor: const AlwaysStoppedAnimation(_kTeal),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 24,
                child: Text(
                  it.count.toString(),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ── Shared UI ─────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String? hint;
  final IconData icon;
  final Color color;
  const _SummaryCard({
    required this.label,
    required this.value,
    this.hint,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.onSurface.withValues(alpha: 0.7),
            ),
          ),
          if (hint != null)
            Text(
              hint!,
              style: TextStyle(
                fontSize: 10.5,
                color: colors.onSurface.withValues(alpha: 0.45),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  const _ChartCard({required this.title, this.subtitle, required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          'No data for this range',
          style: TextStyle(
            color: colors.onSurface.withValues(alpha: 0.4),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _PrivacyProtectedChart extends StatelessWidget {
  final int minimumVisitors;
  final String insightLabel;

  const _PrivacyProtectedChart({
    required this.minimumVisitors,
    required this.insightLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 120),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBlue.withValues(alpha: 0.18)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shield_outlined, color: _kBlue, size: 25),
          const SizedBox(height: 9),
          const Text(
            'Not enough visitor data',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 5),
          Text(
            '$insightLabel become available after at least $minimumVisitors unique visitors to help protect visitor privacy.',
            textAlign: TextAlign.center,
            style: TextStyle(
              height: 1.35,
              fontSize: 12,
              color: colors.onSurface.withValues(alpha: 0.62),
            ),
          ),
        ],
      ),
    );
  }
}

class _SmallGroupsNotice extends StatelessWidget {
  final int minimumCount;

  const _SmallGroupsNotice({required this.minimumCount});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.lock_outline_rounded,
            size: 13,
            color: colors.onSurface.withValues(alpha: 0.45),
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              'Groups smaller than $minimumCount are withheld for privacy.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 10.5,
                color: colors.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  final WeeklyReport report;
  final bool downloading;
  final VoidCallback onDownload;
  const _ReportRow({
    required this.report,
    required this.downloading,
    required this.onDownload,
  });

  String _fmt(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 20, color: _kBlue),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_fmt(report.periodStart)} – ${_fmt(report.periodEnd)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '${report.totalCheckins} check-ins · ${report.uniqueVisitors} visitors',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),
          downloading
              ? const SizedBox(
                  width: 40,
                  height: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(_kMagenta),
                    ),
                  ),
                )
              : IconButton(
                  icon: const Icon(Icons.download_rounded, size: 20),
                  onPressed: onDownload,
                  tooltip: 'Download PDF',
                ),
        ],
      ),
    );
  }
}
