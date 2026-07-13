import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/attendee_filter.dart';

/// KMSTRY+ Advanced Filters editor for the "who's here" list. Returns the new
/// [AttendeeFilter] via Navigator.pop, or null if dismissed without applying.
class AttendeeFilterSheet extends StatefulWidget {
  final AttendeeFilter initial;

  const AttendeeFilterSheet({super.key, required this.initial});

  static Future<AttendeeFilter?> show(
    BuildContext context,
    AttendeeFilter initial,
  ) {
    return showModalBottomSheet<AttendeeFilter>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AttendeeFilterSheet(initial: initial),
    );
  }

  @override
  State<AttendeeFilterSheet> createState() => _AttendeeFilterSheetState();
}

class _AttendeeFilterSheetState extends State<AttendeeFilterSheet> {
  static const _kMagenta = Color(0xFFE020D8);
  static const _ageMin = 18.0;
  static const _ageMax = 65.0;
  // Vibe keyword filter is hidden from the UI for now (backend still supports it).
  static const _showVibeFilter = false;

  static const _intents = <String, String>{
    'NEW_PEOPLE': 'New people',
    'GOOD_CONVERSATION': 'Good conversation',
    'MEET_SOMEONE': 'Meet someone',
    'OPEN_TO_POSSIBILITIES': 'Open to possibilities',
    'JUST_CHILLING': 'Just chilling',
    'BUSINESS_NETWORKING': 'Networking',
    'CELEBRATING': 'Celebrating',
    'LOOKING_FOR_FUN': 'Looking for fun',
  };

  late String? _gender;
  late RangeValues _ageRange;
  late bool _ageEnabled;
  late String? _intent;
  late final TextEditingController _vibeCtrl;

  @override
  void initState() {
    super.initState();
    _gender = widget.initial.gender;
    _ageEnabled =
        widget.initial.minAge != null || widget.initial.maxAge != null;
    _ageRange = RangeValues(
      (widget.initial.minAge ?? _ageMin.toInt()).toDouble(),
      (widget.initial.maxAge ?? _ageMax.toInt()).toDouble(),
    );
    _intent = widget.initial.intent;
    _vibeCtrl = TextEditingController(text: widget.initial.vibe ?? '');
  }

  @override
  void dispose() {
    _vibeCtrl.dispose();
    super.dispose();
  }

  void _clearAll() {
    setState(() {
      _gender = null;
      _ageEnabled = false;
      _ageRange = const RangeValues(_ageMin, _ageMax);
      _intent = null;
      _vibeCtrl.clear();
    });
  }

  void _apply() {
    final vibe = _showVibeFilter ? _vibeCtrl.text.trim() : '';
    Navigator.of(context).pop(
      AttendeeFilter(
        gender: _gender,
        minAge: _ageEnabled ? _ageRange.start.round() : null,
        maxAge: _ageEnabled ? _ageRange.end.round() : null,
        intent: _intent,
        vibe: vibe.isEmpty ? null : vibe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    const Icon(Icons.tune_rounded, color: _kMagenta, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Filters',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _clearAll,
                      child: const Text('Clear all'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    _sectionTitle('Gender', colors),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        _genderChip('Everyone', null, colors),
                        const SizedBox(width: 8),
                        _genderChip('Men', 'male', colors),
                        const SizedBox(width: 8),
                        _genderChip('Women', 'female', colors),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        _sectionTitle('Age', colors),
                        const Spacer(),
                        if (_ageEnabled)
                          Text(
                            '${_ageRange.start.round()} – ${_ageRange.end.round()}',
                            style: const TextStyle(
                              color: _kMagenta,
                              fontWeight: FontWeight.w700,
                            ),
                          )
                        else
                          Text(
                            'Any',
                            style: TextStyle(
                              color: colors.onSurface.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                    RangeSlider(
                      values: _ageRange,
                      min: _ageMin,
                      max: _ageMax,
                      divisions: (_ageMax - _ageMin).toInt(),
                      activeColor: _kMagenta,
                      labels: RangeLabels(
                        '${_ageRange.start.round()}',
                        '${_ageRange.end.round()}',
                      ),
                      onChanged: (v) => setState(() {
                        _ageRange = v;
                        _ageEnabled = true;
                      }),
                    ),
                    const SizedBox(height: 16),
                    _sectionTitle('Here for', colors),
                    const SizedBox(height: 10),
                    _intentList(colors),
                    // Vibe keyword search — hidden for now (backend still
                    // supports it; re-enable by unwrapping this block).
                    if (_showVibeFilter) ...[
                      const SizedBox(height: 24),
                      _sectionTitle('Vibe', colors),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _vibeCtrl,
                        decoration: InputDecoration(
                          hintText: 'Search by keyword, e.g. wine, jazz…',
                          prefixIcon:
                              const Icon(Icons.search_rounded, size: 20),
                          filled: true,
                          fillColor: colors.surfaceContainerHighest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 4,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _apply,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kMagenta,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      child: const Text('Show results'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text, ColorScheme colors) => Text(
        text,
        style: TextStyle(
          color: colors.onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _genderChip(String label, String? value, ColorScheme colors) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? _kMagenta : colors.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : colors.onSurface,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Selectable "here for" options as a list. Shows 3 full rows plus a peek of
  /// the next one, with a bottom fade — both cue the user that it scrolls.
  Widget _intentList(ColorScheme colors) {
    const rowHeight = 52.0;
    const rowGap = 8.0;
    const visibleRows = 3;
    final entries = _intents.entries.toList();
    final scrolls = entries.length > visibleRows;
    // 3 full rows + gaps, plus a partial 4th row (peek) when there's overflow.
    final maxHeight = (rowHeight * visibleRows) +
        (rowGap * (visibleRows - 1)) +
        (scrolls ? rowGap + rowHeight * 0.45 : 0);

    final list = ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ListView.separated(
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: entries.length,
        physics: scrolls
            ? const ClampingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        separatorBuilder: (_, index) => const SizedBox(height: rowGap),
        itemBuilder: (_, i) {
          final e = entries[i];
          final selected = _intent == e.key;
          return _intentRow(
            e.value,
            selected,
            colors,
            rowHeight,
            () => setState(() => _intent = selected ? null : e.key),
          );
        },
      ),
    );

    if (!scrolls) return list;

    // Fade the bottom edge so the peeking row reads as "more below".
    return ShaderMask(
      shaderCallback: (rect) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: const [0.0, 0.80, 1.0],
        colors: [Colors.white, Colors.white, Colors.white.withValues(alpha: 0)],
      ).createShader(rect),
      blendMode: BlendMode.dstIn,
      child: list,
    );
  }

  Widget _intentRow(
    String label,
    bool selected,
    ColorScheme colors,
    double height,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected
              ? _kMagenta
              : colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: selected
              ? null
              : Border.all(color: colors.onSurface.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : colors.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: Colors.white, size: 20),
          ],
        ),
      ),
    );
  }
}
