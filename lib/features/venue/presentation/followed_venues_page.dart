import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';

enum _VenueSort { latest, earliest }

class FollowedVenuesPage extends StatefulWidget {
  const FollowedVenuesPage({super.key});

  @override
  State<FollowedVenuesPage> createState() => _FollowedVenuesPageState();
}

class _FollowedVenuesPageState extends State<FollowedVenuesPage> {
  final VenueContextRepository _repository = VenueContextRepository();
  final TextEditingController _searchController = TextEditingController();

  List<Venue> _venues = const [];
  bool _loading = true;
  String? _error;
  String _query = '';
  _VenueSort _sort = _VenueSort.latest;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadVenues() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final venues = await _repository.getFollowedVenues();
      if (!mounted) return;
      setState(() {
        _venues = venues;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Followed venues could not be loaded.';
        _loading = false;
      });
    }
  }

  List<Venue> get _visibleVenues {
    final normalized = _query.trim().toLowerCase();
    final filtered = normalized.isEmpty
        ? List<Venue>.from(_venues)
        : _venues.where((venue) {
            final haystack = [
              venue.name,
              venue.type,
              venue.city,
              venue.address,
            ].join(' ').toLowerCase();
            return haystack.contains(normalized);
          }).toList();

    switch (_sort) {
      case _VenueSort.latest:
        return filtered;
      case _VenueSort.earliest:
        return filtered.reversed.toList();
    }
  }

  String get _sortLabel {
    switch (_sort) {
      case _VenueSort.latest:
        return 'Latest';
      case _VenueSort.earliest:
        return 'Earliest';
    }
  }

  Future<void> _openSortSheet() async {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark
          ? const Color(0xFF161C28)
          : theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        Widget option(_VenueSort key, String label) {
          final selected = _sort == key;
          return ListTile(
            title: Text(label),
            trailing: selected
                ? Icon(Icons.check_rounded, color: theme.colorScheme.primary)
                : null,
            onTap: () {
              setState(() => _sort = key);
              Navigator.pop(ctx);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Sort by',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
              option(_VenueSort.latest, 'Latest'),
              option(_VenueSort.earliest, 'Earliest'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final onSurface = isDark ? Colors.white : Colors.black;
    final visibleVenues = _visibleVenues;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.appBarTheme.backgroundColor,
        elevation: 0,
        title: Text(
          'Venues',
          style: TextStyle(
            color: onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadVenues,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _buildSearchField(isDark, onSurface),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
              child: Row(
                children: [
                  Text(
                    'Sort by: ',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.6),
                      fontSize: 13.5,
                    ),
                  ),
                  Text(
                    _sortLabel,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Sort',
                    icon: Icon(Icons.swap_vert_rounded, color: onSurface),
                    onPressed: _openSortSheet,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Text(
                '${visibleVenues.length} ${visibleVenues.length == 1 ? 'venue' : 'venues'}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 90),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              _buildMessageState(
                icon: Icons.error_outline_rounded,
                title: _error!,
                subtitle: 'Pull to refresh and try again.',
                isDark: isDark,
              )
            else if (_venues.isEmpty)
              _buildMessageState(
                icon: Icons.location_city_rounded,
                title: 'No followed venues yet',
                subtitle: 'Follow venues to see them here.',
                isDark: isDark,
              )
            else if (visibleVenues.isEmpty)
              _buildMessageState(
                icon: Icons.search_off_rounded,
                title: 'No venues found',
                subtitle: 'Try another venue name.',
                isDark: isDark,
              )
            else
              for (final venue in visibleVenues)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: VenueListItem(
                    venue: venue,
                    onTap: (selectedVenue) async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => VenueDetailPage(venue: selectedVenue),
                        ),
                      );
                      if (mounted) await _loadVenues();
                    },
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color onSurface) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      style: TextStyle(color: onSurface),
      decoration: InputDecoration(
        hintText: 'Search by name',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF1F3F5),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildMessageState({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 110),
      child: Column(
        children: [
          Icon(
            icon,
            size: 50,
            color: isDark ? Colors.white24 : const Color(0xFFCBD5E1),
          ),
          const SizedBox(height: 14),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.white38 : const Color(0xFF94A3B8),
            ),
          ),
        ],
      ),
    );
  }
}
