import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

/// Compact check-in counts next to rating: total + ♂ / ♀ when API provides them.
class VenueCheckinStatsRow extends StatelessWidget {
  final Venue venue;
  final bool isDark;
  final double iconSize;
  final double fontSize;

  /// When true (e.g. type search), show the first-check-in prompt if the API sent no counts
  /// (avoids an empty row for [isInDb] venues with null aggregates).
  final bool treatMissingStatsAsCheckInPrompt;

  const VenueCheckinStatsRow({
    super.key,
    required this.venue,
    required this.isDark,
    this.iconSize = 14,
    this.fontSize = 12,
    this.treatMissingStatsAsCheckInPrompt = false,
  });

  /// Prefer server total; else sum of gender counts when both exist.
  int? get _displayTotal {
    final t = venue.checkinCountActive;
    if (t != null) return t;
    final m = venue.checkinCountMale;
    final f = venue.checkinCountFemale;
    if (m != null && f != null) return m + f;
    return null;
  }

  bool get _showTotal => _displayTotal != null;

  bool get _showGender =>
      venue.checkinCountMale != null || venue.checkinCountFemale != null;

  /// Show friendly CTA instead of "0" when API says nobody is checked in.
  bool get _showFirstCheckInCta {
    final male = venue.checkinCountMale;
    final female = venue.checkinCountFemale;
    final hasPositiveGender =
        (male != null && male > 0) || (female != null && female > 0);
    if (hasPositiveGender) return false;
    if (venue.checkinCountActive == 0) return true;
    final dt = _displayTotal;
    if (dt != null && dt == 0) return true;
    if (venue.checkinCountActive == null &&
        male != null &&
        female != null &&
        male == 0 &&
        female == 0) {
      return true;
    }
    return false;
  }

  /// Not in our DB yet, or Google/community row with no aggregates (API may set isInDb true wrongly).
  bool get _showNotInDbNoStatsCta {
    final noStats =
        venue.checkinCountActive == null &&
        venue.checkinCountMale == null &&
        venue.checkinCountFemale == null;
    if (!noStats) return false;
    if (!venue.isInDb) return true;
    if (venue.source == 'google') return true;
    return false;
  }

  bool get _showCheckInPrompt => _showFirstCheckInCta || _showNotInDbNoStatsCta;

  Widget _buildCheckInPromptRow(BuildContext context) {
    final promptColor = isDark
        ? Colors.white70
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.72);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.waving_hand_rounded,
          size: iconSize,
          color: isDark ? Colors.amber.shade200 : Colors.amber.shade800,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'Want to be the first to check in?',
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w500,
              fontStyle: FontStyle.italic,
              color: promptColor,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_showCheckInPrompt) {
      return _buildCheckInPromptRow(context);
    }

    if (!_showTotal && !_showGender) {
      if (treatMissingStatsAsCheckInPrompt) {
        return _buildCheckInPromptRow(context);
      }
      return const SizedBox.shrink();
    }

    final muted = isDark ? Colors.white54 : Colors.grey;
    final strong = isDark ? Colors.white70 : Colors.black87;

    TextStyle countStyle([bool emphasize = true]) => TextStyle(
      fontSize: fontSize,
      fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
      color: emphasize ? strong : muted,
    );

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_showTotal && (_displayTotal ?? 0) > 0) ...[
          Icon(
            Icons.people_outline_rounded,
            size: iconSize,
            color: isDark ? const Color(0xFF88A9FF) : const Color(0xFF5D8CFF),
          ),
          Text('$_displayTotal', style: countStyle()),
        ],
        if (_showGender) ...[
          if (venue.checkinCountMale != null &&
              venue.checkinCountMale! > 0) ...[
            Icon(
              Icons.man_rounded,
              size: iconSize,
              color: isDark ? Colors.lightBlue.shade200 : Colors.blue.shade700,
            ),
            Text('${venue.checkinCountMale}', style: countStyle()),
          ],
          if (venue.checkinCountFemale != null &&
              venue.checkinCountFemale! > 0) ...[
            Icon(
              Icons.woman_rounded,
              size: iconSize,
              color: isDark ? const Color(0xFF88A9FF) : const Color(0xFF5D8CFF),
            ),
            Text('${venue.checkinCountFemale}', style: countStyle()),
          ],
        ],
      ],
    );
  }
}
