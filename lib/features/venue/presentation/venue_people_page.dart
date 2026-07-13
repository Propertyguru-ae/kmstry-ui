import 'package:flutter/material.dart';
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

class VenuePeoplePage extends StatefulWidget {
  final Venue venue;

  /// Backend check-in list uses the DB venue UUID. Google-sourced [venue] may
  /// use [placeId] as [Venue.id]; pass the resolved id from active check-in / resolve.
  final String? listVenueId;

  const VenuePeoplePage({
    super.key,
    required this.venue,
    this.listVenueId,
  });

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
      _statsFuture =
          _venueContextRepo.getVenueCheckinStats(_effectiveVenueIdForList);
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

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: AppBar(
          backgroundColor: colors.surface,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 8),
              child: _FilterButton(
                count: _filter.activeCount,
                onTap: _openFilters,
              ),
            ),
          ],
          title: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                  ),
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
                                color: colors.onSurface.withValues(alpha: 0.72),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.checkinCountActive}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(alpha: 0.72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.man_rounded,
                                size: 14,
                                color: colors.onSurface.withValues(alpha: 0.72),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.male}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(alpha: 0.72),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Icon(
                                Icons.woman_rounded,
                                size: 14,
                                color: colors.onSurface.withValues(alpha: 0.72),
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '${stats.female}',
                                style: TextStyle(
                                  color: colors.onSurface.withValues(alpha: 0.72),
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
          Divider(
            height: 1,
            thickness: 0.5,
            color: colors.onSurface.withValues(alpha: 0.2),
          ),
          if (_filter.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              color: const Color(0xFFE020D8).withValues(alpha: 0.08),
              child: Row(
                children: [
                  const Icon(Icons.tune_rounded,
                      size: 16, color: Color(0xFFE020D8)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_filter.activeCount} filter${_filter.activeCount == 1 ? '' : 's'} active',
                      style: TextStyle(
                        color: colors.onSurface,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: FutureBuilder<List<VenueCheckin>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
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
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _filter.isEmpty
                                ? 'No one is here yet'
                                : 'No one matches these filters',
                            style: TextStyle(color: colors.onSurface),
                          ),
                          if (_filter.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _clearFilters,
                              child: const Text('Clear filters'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                }

                return GridView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: people.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 1.5,
                    crossAxisSpacing: 1.5,
                    childAspectRatio: 0.7,
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

/// Filter icon with an active-count badge for the attendee list app bar.
class _FilterButton extends StatelessWidget {
  final int count;
  final VoidCallback onTap;

  const _FilterButton({required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkResponse(
      onTap: onTap,
      radius: 24,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(Icons.tune_rounded, color: colors.onSurface, size: 24),
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
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
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
