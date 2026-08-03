import 'package:flutter/material.dart';

import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';

/// "You're nearby — select your venue" sheet for the quick check-in flow.
/// Mirrors the map screen's venue bottom sheet design (rounded top, drag handle,
/// [VenueListItem] rows) but without the search/filter controls. Lists nearby
/// venues by distance; returns the chosen [Venue], or null if dismissed.
Future<Venue?> showNearbyVenueSheet(
  BuildContext context, {
  required List<Venue> venues,
  required int checkinMaxDistanceMeters,
  String? activeCheckinVenueId,
}) {
  return showModalBottomSheet<Venue>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _NearbyVenueSheet(
      venues: venues,
      activeCheckinVenueId: activeCheckinVenueId,
    ),
  );
}

class _NearbyVenueSheet extends StatelessWidget {
  const _NearbyVenueSheet({
    required this.venues,
    this.activeCheckinVenueId,
  });

  final List<Venue> venues;
  final String? activeCheckinVenueId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isDark ? theme.colorScheme.surface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                blurRadius: 14,
                color: isDark ? Colors.black45 : Colors.black12,
              ),
            ],
          ),
          // Single scroll view driven by the sheet controller → the whole sheet
          // (header included) can be grabbed anywhere to raise/lower, exactly
          // like the map's venue sheet.
          child: CustomScrollView(
            controller: controller,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      "You're nearby",
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Select your venue to check in',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white54 : Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (_, i) {
                    final venue = venues[i];
                    final stableKey = venue.id.isNotEmpty
                        ? venue.id
                        : ((venue.placeId != null && venue.placeId!.isNotEmpty)
                            ? venue.placeId!
                            : '${venue.name}:${venue.latitude}:${venue.longitude}');
                    return VenueListItem(
                      key: ValueKey(stableKey),
                      venue: venue,
                      isActiveCheckin:
                          activeCheckinVenueId != null &&
                          venue.id == activeCheckinVenueId,
                      onTap: (v) => Navigator.pop(context, v),
                    );
                  },
                  childCount: venues.length,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
