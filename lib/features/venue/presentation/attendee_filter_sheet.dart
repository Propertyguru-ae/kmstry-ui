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
  static const _kBlue = Color(0xFF1A9FE8);
  static const _kTeal = Color(0xFF1FD9A8);
  static const _kMagenta = Color(0xFFE020D8);
  static const _kDeepPurple = Color(0xFF3D1F8C);
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
  late Set<String> _selectedIntents;
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
    _selectedIntents = widget.initial.effectiveIntents.toSet();
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
      _selectedIntents.clear();
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
        intents: _selectedIntents.toList(growable: false),
        vibe: vibe.isEmpty ? null : vibe,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final sheetBg = isDark ? const Color(0xFF07101C) : colors.surface;
    final panelBg = isDark
        ? const Color(0xFF101A28)
        : colors.surfaceContainerHighest.withValues(alpha: 0.55);
    final borderColor = colors.onSurface.withValues(
      alpha: isDark ? 0.10 : 0.08,
    );
    final mutedText = colors.onSurface.withValues(alpha: isDark ? 0.66 : 0.58);
    final resetBg = isDark ? const Color(0xFF101A28) : const Color(0xFFF4F7FB);
    final resetFg = isDark ? Colors.white : const Color(0xFF08111F);
    final resetBorder = isDark
        ? colors.onSurface.withValues(alpha: 0.16)
        : const Color(0xFFD7E1EE);

    return DraggableScrollableSheet(
      initialChildSize: 0.90,
      minChildSize: 0.66,
      maxChildSize: 0.96,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(
              top: BorderSide(color: colors.onSurface.withValues(alpha: 0.08)),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.42 : 0.16),
                blurRadius: 34,
                offset: const Offset(0, -18),
              ),
            ],
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: colors.onSurface.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                child: _HeaderCard(
                  activeCount: _previewFilter().activeCount,
                  mutedText: mutedText,
                  onClear: _clearAll,
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 2, 20, 18),
                  children: [
                    _FilterPanel(
                      title: 'Gender',
                      subtitle: 'Choose who you want to see right now.',
                      icon: Icons.person_search_rounded,
                      panelBg: panelBg,
                      borderColor: borderColor,
                      mutedText: mutedText,
                      child: Row(
                        children: [
                          _genderChip('Everyone', null, colors),
                          const SizedBox(width: 8),
                          _genderChip('Men', 'male', colors),
                          const SizedBox(width: 8),
                          _genderChip('Women', 'female', colors),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FilterPanel(
                      title: 'Age range',
                      subtitle: _ageEnabled
                          ? '${_ageRange.start.round()} – ${_ageRange.end.round()} years old'
                          : 'Any age within KMSTRY limits.',
                      icon: Icons.cake_outlined,
                      panelBg: panelBg,
                      borderColor: borderColor,
                      mutedText: mutedText,
                      trailing: _MiniPill(
                        label: _ageEnabled
                            ? '${_ageRange.start.round()}–${_ageRange.end.round()}'
                            : 'Any',
                        active: _ageEnabled,
                      ),
                      child: Column(
                        children: [
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              activeTrackColor: _kBlue,
                              inactiveTrackColor: colors.onSurface.withValues(
                                alpha: 0.10,
                              ),
                              thumbColor: _kTeal,
                              overlayColor: _kTeal.withValues(alpha: 0.16),
                              rangeThumbShape: const RoundRangeSliderThumbShape(
                                enabledThumbRadius: 9,
                              ),
                              trackHeight: 4,
                            ),
                            child: RangeSlider(
                              values: _ageRange,
                              min: _ageMin,
                              max: _ageMax,
                              divisions: (_ageMax - _ageMin).toInt(),
                              labels: RangeLabels(
                                '${_ageRange.start.round()}',
                                '${_ageRange.end.round()}',
                              ),
                              onChanged: (v) => setState(() {
                                _ageRange = v;
                                _ageEnabled = true;
                              }),
                            ),
                          ),
                          Row(
                            children: [
                              Text(
                                '${_ageMin.round()}',
                                style: TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${_ageMax.round()}',
                                style: TextStyle(
                                  color: mutedText,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    _FilterPanel(
                      title: 'Here for',
                      subtitle:
                          'Choose one or more vibes people selected at check-in.',
                      icon: Icons.auto_awesome_rounded,
                      panelBg: panelBg,
                      borderColor: borderColor,
                      mutedText: mutedText,
                      child: _intentList(colors),
                    ),
                    if (_showVibeFilter) ...[
                      const SizedBox(height: 14),
                      _FilterPanel(
                        title: 'Vibe',
                        subtitle:
                            'Search by a word people wrote in their vibe.',
                        icon: Icons.search_rounded,
                        panelBg: panelBg,
                        borderColor: borderColor,
                        mutedText: mutedText,
                        child: TextField(
                          controller: _vibeCtrl,
                          style: TextStyle(color: colors.onSurface),
                          decoration: InputDecoration(
                            hintText: 'wine, jazz, coffee...',
                            hintStyle: TextStyle(color: mutedText),
                            prefixIcon: Icon(
                              Icons.search_rounded,
                              size: 20,
                              color: mutedText,
                            ),
                            filled: true,
                            fillColor: colors.onSurface.withValues(alpha: 0.06),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: borderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(color: _kBlue),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
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
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _clearAll,
                          style:
                              OutlinedButton.styleFrom(
                                backgroundColor: resetBg,
                                foregroundColor: resetFg,
                                disabledBackgroundColor: resetBg.withValues(
                                  alpha: 0.55,
                                ),
                                disabledForegroundColor: resetFg.withValues(
                                  alpha: 0.45,
                                ),
                                side: BorderSide(color: resetBorder),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 13,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                ),
                              ).copyWith(
                                overlayColor: WidgetStatePropertyAll(
                                  _kBlue.withValues(
                                    alpha: isDark ? 0.14 : 0.08,
                                  ),
                                ),
                              ),
                          child: const Text('Reset'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [_kBlue, _kTeal],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: _kBlue.withValues(alpha: 0.26),
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _apply,
                            style: ElevatedButton.styleFrom(
                              elevation: 0,
                              shadowColor: Colors.transparent,
                              backgroundColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            child: const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('Show people'),
                                SizedBox(width: 8),
                                Icon(Icons.arrow_forward_rounded, size: 19),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  AttendeeFilter _previewFilter() {
    final vibe = _showVibeFilter ? _vibeCtrl.text.trim() : '';
    return AttendeeFilter(
      gender: _gender,
      minAge: _ageEnabled ? _ageRange.start.round() : null,
      maxAge: _ageEnabled ? _ageRange.end.round() : null,
      intents: _selectedIntents.toList(growable: false),
      vibe: vibe.isEmpty ? null : vibe,
    );
  }

  Widget _genderChip(String label, String? value, ColorScheme colors) {
    final selected = _gender == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _gender = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? _kBlue.withValues(alpha: 0.18)
                : colors.onSurface.withValues(alpha: 0.055),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? _kBlue.withValues(alpha: 0.85)
                  : colors.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? _kBlue : colors.onSurface,
              fontWeight: FontWeight.w800,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  /// Selectable "here for" options as a full list. Keep this scroll-free so no
  /// option can hide behind the bottom action bar.
  Widget _intentList(ColorScheme colors) {
    const rowHeight = 40.0;
    const rowGap = 6.0;
    final entries = _intents.entries.toList();
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          if (i > 0) const SizedBox(height: rowGap),
          Builder(
            builder: (_) {
              final e = entries[i];
              final selected = _selectedIntents.contains(e.key);
              return _intentRow(
                e.value,
                selected,
                colors,
                rowHeight,
                () => setState(() {
                  if (selected) {
                    _selectedIntents.remove(e.key);
                  } else {
                    _selectedIntents.add(e.key);
                  }
                }),
              );
            },
          ),
        ],
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? _kDeepPurple.withValues(alpha: 0.72)
              : colors.onSurface.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? _kMagenta.withValues(alpha: 0.70)
                : colors.onSurface.withValues(alpha: 0.08),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? _kMagenta.withValues(alpha: 0.22)
                    : colors.onSurface.withValues(alpha: 0.06),
              ),
              child: Icon(
                selected ? Icons.check_rounded : Icons.add_rounded,
                color: selected
                    ? _kMagenta
                    : colors.onSurface.withValues(alpha: 0.55),
                size: 15,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : colors.onSurface,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final int activeCount;
  final Color mutedText;
  final VoidCallback onClear;

  const _HeaderCard({
    required this.activeCount,
    required this.mutedText,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _AttendeeFilterSheetState._kBlue.withValues(alpha: 0.16),
            _AttendeeFilterSheetState._kDeepPurple.withValues(alpha: 0.24),
            colors.onSurface.withValues(alpha: 0.035),
          ],
        ),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [
                  _AttendeeFilterSheetState._kBlue,
                  _AttendeeFilterSheetState._kTeal,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _AttendeeFilterSheetState._kBlue.withValues(
                    alpha: 0.22,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: const Icon(
              Icons.tune_rounded,
              color: Colors.white,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Refine your crowd',
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  activeCount == 0
                      ? 'Refine the room without losing the vibe.'
                      : '$activeCount filter${activeCount == 1 ? '' : 's'} selected',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mutedText,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (activeCount > 0)
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                foregroundColor: _AttendeeFilterSheetState._kBlue,
                textStyle: const TextStyle(fontWeight: FontWeight.w800),
              ),
              child: const Text('Clear'),
            ),
        ],
      ),
    );
  }
}

class _FilterPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color panelBg;
  final Color borderColor;
  final Color mutedText;
  final Widget child;
  final Widget? trailing;

  const _FilterPanel({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.panelBg,
    required this.borderColor,
    required this.mutedText,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: _AttendeeFilterSheetState._kBlue.withValues(
                    alpha: 0.13,
                  ),
                ),
                child: Icon(
                  icon,
                  color: _AttendeeFilterSheetState._kBlue,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: mutedText,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 10), trailing!],
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _MiniPill extends StatelessWidget {
  final String label;
  final bool active;

  const _MiniPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: active
            ? _AttendeeFilterSheetState._kTeal.withValues(alpha: 0.13)
            : colors.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: active
              ? _AttendeeFilterSheetState._kTeal.withValues(alpha: 0.45)
              : colors.onSurface.withValues(alpha: 0.08),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: active ? _AttendeeFilterSheetState._kTeal : colors.onSurface,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}
