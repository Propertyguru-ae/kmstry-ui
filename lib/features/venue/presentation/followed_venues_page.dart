import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_detail_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_list_item.dart';

enum _VenueSort { recent, name, followers }

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
  _VenueSort _sort = _VenueSort.recent;

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
      case _VenueSort.recent:
        return filtered;
      case _VenueSort.name:
        filtered.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
        return filtered;
      case _VenueSort.followers:
        filtered.sort((a, b) => b.followerCount.compareTo(a.followerCount));
        return filtered;
    }
  }

  String get _sortLabel {
    switch (_sort) {
      case _VenueSort.recent:
        return 'Recently followed';
      case _VenueSort.name:
        return 'Name A-Z';
      case _VenueSort.followers:
        return 'Most followers';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF10141B) : Colors.white;
    final border = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE4EAF0);
    final visibleVenues = _visibleVenues;

    return Scaffold(
      appBar: AppBar(title: const Text('Venues')),
      body: RefreshIndicator(
        onRefresh: _loadVenues,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                Expanded(child: _buildSearchField(isDark, surface, border)),
                const SizedBox(width: 10),
                _buildSortButton(isDark, surface, border),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '${visibleVenues.length} ${visibleVenues.length == 1 ? 'venue' : 'venues'}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white54 : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
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
                VenueListItem(
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
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField(bool isDark, Color surface, Color border) {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
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
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: AppTheme.brandPrimary, width: 1.2),
        ),
      ),
    );
  }

  Widget _buildSortButton(bool isDark, Color surface, Color border) {
    return PopupMenuButton<_VenueSort>(
      initialValue: _sort,
      onSelected: (value) => setState(() => _sort = value),
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _VenueSort.recent,
          child: Text('Recently followed'),
        ),
        PopupMenuItem(value: _VenueSort.name, child: Text('Name A-Z')),
        PopupMenuItem(
          value: _VenueSort.followers,
          child: Text('Most followers'),
        ),
      ],
      child: Container(
        height: 54,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort_rounded,
              size: 20,
              color: isDark ? Colors.white70 : const Color(0xFF334155),
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 92),
              child: Text(
                _sortLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: isDark ? Colors.white70 : const Color(0xFF334155),
                ),
              ),
            ),
          ],
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
