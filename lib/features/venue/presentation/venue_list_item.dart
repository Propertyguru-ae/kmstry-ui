import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
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
    final activeCount = venue.checkinCountActive ?? 0;
    final distance = _formatDistance(venue.distanceMeters);
    final galleryPhotos = _galleryPhotos(venue);
    final about = _aboutText(venue);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          onTap?.call(venue);
          if (onTap != null) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => VenueDetailPage(venue: venue)),
          );
        },
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.brandPrimary.withValues(alpha: 0.14)
                : (isDark
                      ? theme.colorScheme.surface
                      : const Color(0xFFF8FBFD)),
            borderRadius: BorderRadius.circular(20),
            border: isSelected
                ? Border.all(
                    color: AppTheme.brandPrimary.withValues(alpha: 0.14),
                    width: 1.0,
                  )
                : (isDark
                      ? Border.all(color: Colors.white.withValues(alpha: 0.05))
                      : Border.all(color: const Color(0xFFE6EEF4))),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                venue.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                displayAddress,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 9),
              _VenueMetadataLine(
                venue: venue,
                distance: distance,
                isDark: isDark,
              ),
              if (galleryPhotos.isNotEmpty) ...[
                const SizedBox(height: 12),
                _VenuePhotoStrip(photos: galleryPhotos, isDark: isDark),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (venue.openNow == true)
                    _MiniBadge(
                      icon: Icons.schedule_rounded,
                      label: 'Open now',
                      color: const Color(0xFF1FD9A8),
                      isDark: isDark,
                    ),
                  if (activeCount > 0)
                    _MiniBadge(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Busy now',
                      color: const Color(0xFFF08838),
                      isDark: isDark,
                    ),
                  VenueCheckinStatsRow(
                    venue: venue,
                    isDark: isDark,
                    iconSize: 14,
                    fontSize: 12,
                    treatMissingStatsAsCheckInPrompt: true,
                  ),
                  for (final platform in venue.partnershipPlatforms.take(2))
                    _MiniBadge(
                      icon: Icons.handshake_outlined,
                      label: _partnershipLabel(platform),
                      color: const Color(0xFF1A9FE8),
                      isDark: isDark,
                    ),
                ],
              ),
              if (about != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : const Color(0xFFEFF7F8),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : const Color(0xFFDDEBEC),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Discover ${venue.name}',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        about,
                        style: TextStyle(
                          color: isDark ? Colors.white70 : Colors.black54,
                          fontSize: 12.5,
                          height: 1.25,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isDark;

  const _MiniBadge({
    required this.icon,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white.withValues(alpha: 0.86) : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _VenueMetadataLine extends StatelessWidget {
  final Venue venue;
  final String? distance;
  final bool isDark;

  const _VenueMetadataLine({
    required this.venue,
    required this.distance,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final rating = venue.rating;
    final typeLabel = _venueTypeLabel(venue);
    final textColor = isDark ? Colors.white70 : Colors.black54;
    final strongColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black87;
    final children = <Widget>[];

    if (rating != null && rating > 0) {
      children.add(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              rating.toStringAsFixed(1),
              style: TextStyle(
                color: strongColor,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.star_rounded, size: 15, color: Colors.amber.shade700),
            if (venue.ratingCount != null && venue.ratingCount! > 0) ...[
              const SizedBox(width: 4),
              Text(
                '(${_formatCount(venue.ratingCount!)})',
                style: TextStyle(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(width: 5),
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: textColor.withValues(alpha: 0.8),
            ),
          ],
        ),
      );
    }

    if (typeLabel.isNotEmpty) {
      children.add(_MetadataText(typeLabel, color: textColor));
    }
    if (distance != null) {
      children.add(_MetadataText(distance!, color: textColor));
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            _MetadataText('·', color: textColor.withValues(alpha: 0.8)),
          children[i],
        ],
      ],
    );
  }
}

class _MetadataText extends StatelessWidget {
  final String text;
  final Color color;

  const _MetadataText(this.text, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        height: 1.15,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _VenuePhotoStrip extends StatelessWidget {
  final List<String> photos;
  final bool isDark;

  const _VenuePhotoStrip({required this.photos, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final visible = photos.take(4).toList();
    return SizedBox(
      height: 116,
      child: Row(
        children: [
          for (var i = 0; i < visible.length; i++) ...[
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : const Color(0xFFEAF1F4),
                  child: Image.network(
                    visible[i],
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.image_not_supported_outlined,
                      color: isDark ? Colors.white38 : Colors.black26,
                    ),
                  ),
                ),
              ),
            ),
            if (i != visible.length - 1) const SizedBox(width: 7),
          ],
        ],
      ),
    );
  }
}

List<String> _galleryPhotos(Venue venue) {
  final ordered = <String>[
    ...venue.photos,
    if (venue.photoUrl.trim().isNotEmpty) venue.photoUrl.trim(),
  ];
  return ordered
      .where((url) => url.trim().isNotEmpty)
      .where((url) => !_isGooglePlacePhotoUrl(url))
      .toSet()
      .toList();
}

String? _aboutText(Venue venue) {
  final description = venue.description?.trim();
  if (description != null && description.isNotEmpty) {
    return description.length > 118
        ? '${description.substring(0, 118).trimRight()}...'
        : description;
  }
  return null;
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

String _formatCount(int count) {
  if (count < 1000) return count.toString();
  if (count < 1000000) {
    final value = count / 1000;
    return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}K';
  }
  final value = count / 1000000;
  return '${value.toStringAsFixed(value >= 10 ? 0 : 1)}M';
}

String _partnershipLabel(String raw) {
  switch (raw.toUpperCase()) {
    case 'THE_ENTERTAINER':
      return 'Entertainer';
    case 'FAZAA':
      return 'Fazaa';
    case 'ESAAD':
      return 'ESAAD';
    case 'COBONE':
      return 'Cobone';
    case 'GROUPON':
      return 'Groupon';
    default:
      return 'Partner';
  }
}

bool _isGooglePlacePhotoUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  final host = uri.host.toLowerCase();
  return host == 'maps.googleapis.com' &&
      uri.path.contains('/maps/api/place/photo');
}
