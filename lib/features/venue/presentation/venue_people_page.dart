import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/cached_image.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_stats_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/profile_preview_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/user_card.dart';
import 'package:kmstry_frontend/features/venue/data/attendee_filter.dart';
import 'package:kmstry_frontend/features/venue/presentation/attendee_filter_sheet.dart';
import 'package:kmstry_frontend/core/user/premium_feature.dart';
import 'package:kmstry_frontend/core/user/premium_gate.dart';

const _kBlue = Color(0xFF1A9FE8);
const _kTeal = Color(0xFF1FD9A8);
const _kMagenta = Color(0xFFE020D8);
const _kDeepPurple = Color(0xFF3D1F8C);
const _kDarkBg = Color(0xFF06091A);

class VenuePeoplePage extends StatefulWidget {
  final Venue venue;

  /// Backend check-in list uses the DB venue UUID. Google-sourced [venue] may
  /// use [placeId] as [Venue.id]; pass the resolved id from active check-in / resolve.
  final String? listVenueId;

  const VenuePeoplePage({super.key, required this.venue, this.listVenueId});

  @override
  State<VenuePeoplePage> createState() => _VenuePeoplePageState();
}

class _VenuePeoplePageState extends State<VenuePeoplePage> {
  final _repo = VenueCheckinRepository();
  final _venueContextRepo = VenueContextRepository();
  late Future<List<VenueCheckin>> _future;
  late Future<VenueCheckinStats> _statsFuture;
  AttendeeFilter _filter = AttendeeFilter.empty;

  @override
  void initState() {
    super.initState();
    _loadCheckins();
  }

  String get _effectiveVenueIdForList =>
      (widget.listVenueId != null && widget.listVenueId!.isNotEmpty)
      ? widget.listVenueId!
      : widget.venue.id;

  void _loadCheckins() {
    setState(() {
      _future = _repo.getWhoIsHere(
        _effectiveVenueIdForList,
        filter: _filter.isEmpty ? null : _filter,
      );
      _statsFuture = _venueContextRepo.getVenueCheckinStats(
        _effectiveVenueIdForList,
      );
    });
  }

  /// Advanced Filters (KMSTRY+): gate before opening the editor so free users
  /// see the upsell instead of a filter they can't apply.
  Future<void> _openFilters() async {
    final allowed = await PremiumGate.ensure(
      context,
      PremiumFeature.advancedFilters,
      title: 'Advanced Filters is a KMSTRY+ feature',
      message:
          'Filter who\'s here by gender, age, intent and vibe with KMSTRY+.',
      icon: Icons.tune_rounded,
    );
    if (!allowed || !mounted) return;

    final result = await AttendeeFilterSheet.show(context, _filter);
    if (result == null || !mounted) return;
    setState(() => _filter = result);
    _loadCheckins();
  }

  void _clearFilters() {
    if (_filter.isEmpty) return;
    setState(() => _filter = AttendeeFilter.empty);
    _loadCheckins();
  }

  Future<void> _setGenderFilter(String? gender) async {
    if (_filter.gender == gender) return;
    if (gender != null) {
      final allowed = await PremiumGate.ensure(
        context,
        PremiumFeature.advancedFilters,
        title: 'Advanced Filters is a KMSTRY+ feature',
        message:
            'Filter who\'s here by gender, age, intent and vibe with KMSTRY+.',
        icon: Icons.tune_rounded,
      );
      if (!allowed || !mounted) return;
    }
    setState(() => _filter = _filter.copyWith(gender: gender));
    _loadCheckins();
  }

  String? get _venueAvatarUrl {
    final primary = widget.venue.photoUrl.trim();
    if (primary.isNotEmpty) return primary;
    for (final photo in widget.venue.photos) {
      final cleaned = photo.trim();
      if (cleaned.isNotEmpty) return cleaned;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = Theme.of(context).colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final bg = isDark ? _kDarkBg : colors.surface;
    final dividerColor = colors.onSurface.withValues(
      alpha: isDark ? 0.08 : 0.10,
    );

    return Scaffold(
      backgroundColor: bg,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(78),
        child: AppBar(
          backgroundColor: bg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 4,
          leadingWidth: 54,
          leading: Padding(
            padding: const EdgeInsets.only(left: 12, top: 10, bottom: 8),
            child: _RoundIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 10, bottom: 8),
              child: _FilterButton(
                count: _filter.activeCount,
                onTap: _openFilters,
              ),
            ),
          ],
          title: Padding(
            padding: const EdgeInsets.only(top: 9.0),
            child: Row(
              children: [
                _VenueHeaderAvatar(
                  imageUrl: _venueAvatarUrl,
                  venueName: widget.venue.name,
                ),

                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.venue.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 17,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      FutureBuilder<VenueCheckinStats>(
                        future: _statsFuture,
                        builder: (_, snapshot) {
                          if (!snapshot.hasData) return const SizedBox.shrink();
                          final stats = snapshot.data!;
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.people_rounded,
                                size: 14,
                                color: _kTeal,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.checkinCountActive}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.82,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(Icons.man_rounded, size: 14, color: _kBlue),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.male}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.woman_rounded,
                                size: 14,
                                color: _kMagenta,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.female}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Divider(height: 1, thickness: 0.5, color: dividerColor),
          FutureBuilder<VenueCheckinStats>(
            future: _statsFuture,
            builder: (_, snapshot) {
              final stats = snapshot.data;
              return _LiveFilterStrip(
                stats: stats,
                filter: _filter,
                onClear: _clearFilters,
                onGenderSelected: _setGenderFilter,
              );
            },
          ),
          Expanded(
            child: FutureBuilder<List<VenueCheckin>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const _PeopleLoadingState();
                }

                if (snapshot.hasError) {
                  debugPrint('❌ VenuePeople error: ${snapshot.error}');
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.error_outline,
                            size: 48,
                            color: colors.secondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load people',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: colors.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _getErrorMessage(snapshot.error),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: colors.onSurface.withValues(alpha: 0.8),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton.icon(
                            onPressed: _loadCheckins,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Retry'),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final people = snapshot.data!;

                if (people.isEmpty) {
                  return _PeopleEmptyState(
                    filtered: _filter.isNotEmpty,
                    onClear: _clearFilters,
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 16),
                  itemCount: people.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 4,
                    crossAxisSpacing: 4,
                    childAspectRatio: 0.72,
                  ),
                  itemBuilder: (context, index) {
                    final person = people[index];

                    return UserCard(
                      user: person,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfilePreviewPage(
                              checkinId: person.id,
                              venueId: _effectiveVenueIdForList,
                              hideVenueInfo: true,
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _getErrorMessage(Object? error) {
    final errorString = error.toString();
    if (errorString.contains('UnAuth')) {
      return 'Authentication required. Please log in again.';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection.';
    } else if (errorString.contains('SocketException') ||
        errorString.contains('Failed host lookup')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('statusCode')) {
      // Extract status code from error message
      final match = RegExp(r'\((\d+)\)').firstMatch(errorString);
      if (match != null) {
        final statusCode = match.group(1);
        if (statusCode == '401') {
          return 'Unauthorized. Please log in again.';
        } else if (statusCode == '403') {
          return 'Access denied.';
        } else if (statusCode == '404') {
          return 'Venue not found.';
        } else if (statusCode == '500') {
          return 'Server error. Please try again later.';
        }
        return 'Error $statusCode: ${errorString.split(':').last.trim()}';
      }
    }
    return errorString;
  }
}

class _LiveFilterStrip extends StatelessWidget {
  final VenueCheckinStats? stats;
  final AttendeeFilter filter;
  final VoidCallback onClear;
  final ValueChanged<String?> onGenderSelected;

  const _LiveFilterStrip({
    required this.stats,
    required this.filter,
    required this.onClear,
    required this.onGenderSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final all = stats?.checkinCountActive ?? 0;
    final women = stats?.female ?? 0;
    final men = stats?.male ?? 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: BoxDecoration(
        color: isDark ? _kDarkBg : colors.surface,
        border: Border(
          bottom: BorderSide(
            color: colors.onSurface.withValues(alpha: isDark ? 0.08 : 0.10),
            width: 0.5,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          children: [
            _LiveChip(
              label: 'All',
              value: all,
              icon: Icons.groups_rounded,
              color: _kTeal,
              active: filter.gender == null,
              onTap: () => onGenderSelected(null),
            ),
            const SizedBox(width: 8),
            _LiveChip(
              label: 'Women',
              value: women,
              icon: Icons.woman_rounded,
              color: _kMagenta,
              active: filter.gender == 'female',
              onTap: () => onGenderSelected('female'),
            ),
            const SizedBox(width: 8),
            _LiveChip(
              label: 'Men',
              value: men,
              icon: Icons.man_rounded,
              color: _kBlue,
              active: filter.gender == 'male',
              onTap: () => onGenderSelected('male'),
            ),
            if (filter.isNotEmpty) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: onClear,
                child: Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: _kDeepPurple.withValues(alpha: isDark ? 0.40 : 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: _kMagenta.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 15,
                        color: _kMagenta,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${filter.activeCount} active',
                        style: const TextStyle(
                          color: _kMagenta,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: _kMagenta,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  final bool active;
  final VoidCallback? onTap;

  const _LiveChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: isDark ? 0.15 : 0.12)
              : colors.onSurface.withValues(alpha: isDark ? 0.055 : 0.045),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active
                ? color.withValues(alpha: 0.36)
                : colors.onSurface.withValues(alpha: isDark ? 0.09 : 0.08),
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 15,
              color: active ? color : colors.onSurface.withValues(alpha: 0.58),
            ),
            const SizedBox(width: 6),
            Text(
              '$label · $value',
              style: TextStyle(
                color: active
                    ? color
                    : colors.onSurface.withValues(alpha: 0.72),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleLoadingState extends StatelessWidget {
  const _PeopleLoadingState();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: 0.055),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colors.onSurface.withValues(alpha: 0.08)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: _kTeal),
            ),
            SizedBox(width: 12),
            Text(
              'Checking the room',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeopleEmptyState extends StatelessWidget {
  final bool filtered;
  final VoidCallback onClear;

  const _PeopleEmptyState({required this.filtered, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 82,
              height: 82,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _kTeal.withValues(alpha: isDark ? 0.08 : 0.10),
                border: Border.all(color: _kTeal.withValues(alpha: 0.20)),
              ),
              child: const Icon(Icons.radar_rounded, color: _kTeal, size: 36),
            ),
            const SizedBox(height: 18),
            Text(
              filtered ? 'No matches right now' : 'Quiet right now',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Try widening your filters to see more people here.'
                  : 'When people check in, they will appear here live.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.onSurface.withValues(alpha: 0.58),
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 16),
            if (filtered)
              TextButton(
                onPressed: onClear,
                style: TextButton.styleFrom(foregroundColor: _kBlue),
                child: const Text('Clear filters'),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: _kTeal.withValues(alpha: isDark ? 0.10 : 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _kTeal.withValues(alpha: 0.20)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PulseDot(),
                    SizedBox(width: 8),
                    Text(
                      'Watching live',
                      style: TextStyle(
                        color: _kTeal,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PulseDot extends StatelessWidget {
  const _PulseDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(color: _kTeal, shape: BoxShape.circle),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _RoundIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.onSurface.withValues(alpha: isDark ? 0.055 : 0.045),
          border: Border.all(
            color: colors.onSurface.withValues(alpha: isDark ? 0.09 : 0.08),
          ),
        ),
        child: Icon(icon, color: colors.onSurface, size: 18),
      ),
    );
  }
}

class _VenueHeaderAvatar extends StatelessWidget {
  final String? imageUrl;
  final String venueName;

  const _VenueHeaderAvatar({required this.imageUrl, required this.venueName});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasImage = imageUrl != null && imageUrl!.trim().isNotEmpty;

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.onSurface.withValues(alpha: 0.10)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: hasImage
            ? CachedImage(imageUrl!, fit: BoxFit.cover)
            : DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF1A9FE8), Color(0xFF1FD9A8)],
                  ),
                ),
                child: Center(
                  child: Text(
                    venueName.trim().isNotEmpty
                        ? venueName.trim()[0].toUpperCase()
                        : 'V',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

/// Filter icon with an active-count badge for the attendee list app bar.
class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: colors.onSurface.withValues(
                  alpha: isDark ? 0.055 : 0.045,
                ),
                border: Border.all(
                  color: colors.onSurface.withValues(
                    alpha: isDark ? 0.10 : 0.08,
                  ),
                ),
              ),
              child: Icon(
                Icons.tune_rounded,
                color: count > 0 ? _kMagenta : colors.onSurface,
                size: 19,
              ),
            ),
            if (count > 0)
              Positioned(
                right: -4,
                top: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFE020D8),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
