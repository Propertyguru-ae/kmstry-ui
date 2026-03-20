import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_checkin_stats_row.dart';
import '../data/venue_model.dart';

class VenueListItem extends StatelessWidget {
  final Venue venue;
  final bool isSelected;
  final ValueChanged<Venue>? onTap;

  const VenueListItem({
    super.key,
    required this.venue,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final displayAddress = venue.address.isNotEmpty
        ? venue.address
        : (venue.city.isNotEmpty ? venue.city : '-');
    final displayType = venue.type.isNotEmpty ? venue.type : 'venue';
    final hasRating = venue.rating != null && venue.rating! > 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          onTap?.call(venue);
          if (onTap != null) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => VenueDetailPage(venue: venue),
            ),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                : (isDark ? theme.colorScheme.surface : const Color(0xFFF7F3FB)),
            borderRadius: BorderRadius.circular(16),
            border: isDark
                ? Border.all(color: Colors.white.withValues(alpha: 0.05))
                : null,
          ),
          child: Row(
            children: [
              _SourceAvatar(isDark: isDark, isGoogleVenue: venue.source == 'google'),

              const SizedBox(width: 12),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      venue.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      displayAddress,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey,
                        fontSize: 12,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 10,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (hasRating) ...[
                          Icon(
                            Icons.star_rounded,
                            size: 14,
                            color: isDark
                                ? Colors.amber.shade300
                                : Colors.amber.shade700,
                          ),
                          Text(
                            venue.rating!.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white70 : Colors.black87,
                            ),
                          ),
                        ] else
                          Text(
                            'No rating',
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? Colors.white54 : Colors.grey,
                            ),
                          ),
                        VenueCheckinStatsRow(
                          venue: venue,
                          isDark: isDark,
                          iconSize: 14,
                          fontSize: 12,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SourceAvatar extends StatelessWidget {
  final bool isDark;
  final bool isGoogleVenue;

  const _SourceAvatar({required this.isDark, required this.isGoogleVenue});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : const Color(0xFFE8E1F3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: isGoogleVenue
          ? Padding(
              padding: const EdgeInsets.all(7),
              child: Image.network(
                'https://www.gstatic.com/images/branding/product/1x/maps_32dp.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.map_rounded,
                  size: 18,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            )
          : Icon(
              Icons.place,
              size: 18,
              color: isDark ? Theme.of(context).colorScheme.primary : Colors.black87,
            ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final bool isDark;
  final ThemeData theme;

  const _TypeChip({
    required this.label,
    required this.isDark,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.primary.withValues(alpha: 0.2)
            : Colors.deepPurple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? theme.colorScheme.primary : Colors.deepPurple,
        ),
      ),
    );
  }
}
