import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import '../data/venue_model.dart';

class VenueListItem extends StatelessWidget {
  final Venue venue;

  const VenueListItem({super.key, required this.venue});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
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
            color: isDark ? theme.colorScheme.surface : const Color(0xFFF7F3FB),
            borderRadius: BorderRadius.circular(16),
            border: isDark ? Border.all(color: Colors.white.withOpacity(0.05)) : null,
          ),
          child: Row(
            children: [
              /// ICON
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withOpacity(0.05) : const Color(0xFFE8E1F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.place,
                  size: 18,
                  color: isDark ? theme.colorScheme.primary : Colors.black87,
                ),
              ),

              const SizedBox(width: 12),

              /// TEXT
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
                      venue.tag,
                      style: TextStyle(
                        color: isDark ? Colors.white54 : Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

              /// BADGE
              _Badge(venue.type, isDark, theme),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String text;
  final bool isDark;
  final ThemeData theme;
  const _Badge(this.text, this.isDark, this.theme);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? theme.colorScheme.primary.withOpacity(0.2) : Colors.deepPurple.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isDark ? theme.colorScheme.primary : Colors.deepPurple,
        ),
      ),
    );
  }
}
