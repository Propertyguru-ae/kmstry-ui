import 'package:flutter/material.dart';

import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';

/// "You're nearby — select your venue" sheet for the quick check-in flow.
/// Lists nearby venues by distance; returns the chosen [Venue], or null if
/// dismissed.
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

/// Tap'ın hemen ardından açılan hafif "Finding venues near you" loading sheet'i.
/// Konum + yakın mekan çağrıları sürerken kullanıcı boş ekran görmesin diye
/// anında geri bildirim verir. Dönen callback ile veri gelince kapatılır.
VoidCallback showNearbyLoadingSheet(BuildContext context) {
  final navigator = Navigator.of(context);
  var open = true;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => const _NearbyLoadingSheet(),
  ).whenComplete(() => open = false);
  return () {
    if (open && navigator.canPop()) navigator.pop();
    open = false;
  };
}

class _NearbyLoadingSheet extends StatelessWidget {
  const _NearbyLoadingSheet();

  static const Color _brandBlue = Color(0xFF1A9FE8);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Gerçek mekan sheet'i ile aynı yükseklik (DraggableScrollableSheet
    // initialChildSize: 0.46) → loading → liste geçişinde zıplama olmaz.
    final height = MediaQuery.of(context).size.height * 0.46;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0B1421) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: isDark
                ? _brandBlue.withValues(alpha: 0.20)
                : _brandBlue.withValues(alpha: 0.12),
          ),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.14)
                  : Colors.black.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: _brandBlue,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Finding your spot…',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Getting you ready to check in.',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: isDark
                          ? const Color(0xFF8DA0BD)
                          : const Color(0xFF5D6B7B),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NearbyVenueSheet extends StatelessWidget {
  const _NearbyVenueSheet({
    required this.venues,
    this.activeCheckinVenueId,
  });

  final List<Venue> venues;
  final String? activeCheckinVenueId;

  static const Color _brandBlue = Color(0xFF1A9FE8);
  static const Color _brandTeal = Color(0xFF1FD9A8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.46,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, controller) {
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B1421) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: isDark
                    ? _brandBlue.withValues(alpha: 0.20)
                    : _brandBlue.withValues(alpha: 0.12),
              ),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: 26,
                offset: const Offset(0, -10),
                color: isDark
                    ? Colors.black.withValues(alpha: 0.55)
                    : Colors.black.withValues(alpha: 0.12),
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
                        gradient: LinearGradient(
                          colors: [
                            _brandBlue.withValues(alpha: 0.92),
                            _brandTeal.withValues(alpha: 0.92),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            blurRadius: 12,
                            color: _brandTeal.withValues(alpha: 0.28),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Quick check-in',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Pick your spot and share your moment.',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.68)
                            : Colors.black.withValues(alpha: 0.56),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                ),
              ),
              if (venues.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 32),
                    child: _EmptyNearbyState(isDark: isDark),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.only(
                    left: 16,
                    right: 16,
                    bottom: MediaQuery.of(context).padding.bottom + 20,
                  ),
                  sliver: SliverList.separated(
                    itemBuilder: (_, i) {
                      final venue = venues[i];
                      final stableKey = venue.id.isNotEmpty
                          ? venue.id
                          : ((venue.placeId != null && venue.placeId!.isNotEmpty)
                                ? venue.placeId!
                                : '${venue.name}:${venue.latitude}:${venue.longitude}');
                      return _QuickCheckinVenueCard(
                        key: ValueKey(stableKey),
                        venue: venue,
                        isActiveCheckin:
                            activeCheckinVenueId != null &&
                            venue.id == activeCheckinVenueId,
                        onTap: () => Navigator.pop(context, venue),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemCount: venues.length,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickCheckinVenueCard extends StatelessWidget {
  const _QuickCheckinVenueCard({
    super.key,
    required this.venue,
    required this.isActiveCheckin,
    required this.onTap,
  });

  final Venue venue;
  final bool isActiveCheckin;
  final VoidCallback onTap;

  static const Color _brandBlue = Color(0xFF1A9FE8);
  static const Color _brandTeal = Color(0xFF1FD9A8);
  static const Color _brandOrange = Color(0xFFF08838);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final type = _venueTypeLabel(venue);
    final distance = _formatDistance(venue.distanceMeters);
    final liveLabel = _liveLabel(venue);
    final photoUrl = _photoUrl(venue);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF101A2A) : const Color(0xFFF8FBFD),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isActiveCheckin
                  ? _brandTeal.withValues(alpha: 0.72)
                  : _brandBlue.withValues(alpha: isDark ? 0.16 : 0.12),
            ),
            boxShadow: [
              BoxShadow(
                blurRadius: isActiveCheckin ? 18 : 10,
                offset: const Offset(0, 7),
                color: isActiveCheckin
                    ? _brandTeal.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: isDark ? 0.18 : 0.05),
              ),
            ],
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  width: 68,
                  height: 68,
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEAF1F6),
                  child: photoUrl == null
                      ? Icon(
                          Icons.storefront_rounded,
                          color: _brandBlue.withValues(alpha: 0.85),
                          size: 28,
                        )
                      : CachedImage(
                          photoUrl,
                          fit: BoxFit.cover,
                          errorWidget: (_) => Icon(
                            Icons.storefront_rounded,
                            color: _brandBlue.withValues(alpha: 0.85),
                            size: 28,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      venue.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (type.isNotEmpty) type,
                        if (distance != null) distance,
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.58)
                            : Colors.black.withValues(alpha: 0.52),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _QuickBadge(
                          icon: isActiveCheckin
                              ? Icons.check_circle_rounded
                              : Icons.waving_hand_rounded,
                          label: isActiveCheckin ? "You're here" : liveLabel,
                          color: isActiveCheckin ? _brandTeal : _brandOrange,
                          isDark: isDark,
                        ),
                        if (venue.openNow == true)
                          _QuickBadge(
                            icon: Icons.schedule_rounded,
                            label: 'Open now',
                            color: _brandTeal,
                            isDark: isDark,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _CheckinActionButton(
                isActiveCheckin: isActiveCheckin,
                onTap: onTap,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckinActionButton extends StatelessWidget {
  const _CheckinActionButton({
    required this.isActiveCheckin,
    required this.onTap,
  });

  final bool isActiveCheckin;
  final VoidCallback onTap;

  static const Color _brandBlue = Color(0xFF1A9FE8);
  static const Color _brandTeal = Color(0xFF1FD9A8);

  @override
  Widget build(BuildContext context) {
    final color = isActiveCheckin ? _brandTeal : _brandBlue;
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            colors: [
              color,
              isActiveCheckin ? _brandBlue : _brandTeal,
            ],
          ),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: const Offset(0, 6),
              color: color.withValues(alpha: 0.30),
            ),
          ],
        ),
        child: Icon(
          isActiveCheckin
              ? Icons.check_rounded
              : Icons.add_location_alt_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
    );
  }
}

class _QuickBadge extends StatelessWidget {
  const _QuickBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.15 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 12),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: isDark ? Colors.white.withValues(alpha: 0.84) : color,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyNearbyState extends StatelessWidget {
  const _EmptyNearbyState({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF101A2A) : const Color(0xFFF8FBFD),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE6EEF4),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.location_searching_rounded,
            color: const Color(0xFF1A9FE8).withValues(alpha: 0.86),
            size: 30,
          ),
          const SizedBox(height: 10),
          Text(
            'No nearby venues found',
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Move closer to a venue or try again in a moment.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.58)
                  : Colors.black.withValues(alpha: 0.52),
              fontWeight: FontWeight.w600,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

String? _photoUrl(Venue venue) {
  final candidates = <String>[
    venue.photoUrl,
    ...venue.photos,
  ];
  for (final candidate in candidates) {
    final trimmed = candidate.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return null;
}

String _liveLabel(Venue venue) {
  final count = venue.checkinCountActive ?? 0;
  if (count <= 0) return 'Be first here';
  if (count == 1) return '1 person here';
  return '$count people here';
}

String _venueTypeLabel(Venue venue) {
  final rawType = venue.type.trim().toLowerCase();
  final raw = (rawType.isEmpty || rawType == 'venue') && venue.types.isNotEmpty
      ? venue.types.first
      : venue.type;
  final normalized = raw.trim().toLowerCase().replaceAll('_', ' ');
  if (normalized.isEmpty || normalized == 'venue') return 'Venue';
  return normalized
      .split(' ')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

String? _formatDistance(int? meters) {
  if (meters == null || meters < 0) return null;
  if (meters < 1000) return '${meters}m';
  final km = meters / 1000;
  return '${km.toStringAsFixed(km >= 10 ? 0 : 1)} km';
}
