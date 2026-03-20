import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'venue_list_item.dart';

class VenueBottomSheet extends StatefulWidget {
  final ValueChanged<bool> onExpandChanged;
  final List<Venue> venues;
  final bool loading;
  final String? selectedVenueId;
  final ValueChanged<Venue>? onVenueTap;

  const VenueBottomSheet({
    super.key,
    required this.onExpandChanged,
    required this.venues,
    required this.loading,
    this.selectedVenueId,
    this.onVenueTap,
  });
  @override
  State<VenueBottomSheet> createState() => _VenueBottomSheetState();
}

class _VenueBottomSheetState extends State<VenueBottomSheet> {
  bool _isExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query.trim().toLowerCase();
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  List<Venue> _filterVenues(List<Venue> venues) {
    if (_searchQuery.isEmpty) return venues;

    return venues.where((v) {
      final name = v.name.toLowerCase();
      final address = v.address.toLowerCase();
      final city = v.city.toLowerCase();
      final type = v.type.toLowerCase();
      return name.contains(_searchQuery) ||
          address.contains(_searchQuery) ||
          city.contains(_searchQuery) ||
          type.contains(_searchQuery);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final sortedVenues = [...widget.venues]
      ..sort(
        (a, b) =>
            (a.distanceMeters ?? 999999).compareTo(b.distanceMeters ?? 999999),
      );
    final visibleVenues = _filterVenues(sortedVenues);

    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final expanded = notification.extent > 0.35;
        if (expanded != _isExpanded) {
          setState(() => _isExpanded = expanded);
          widget.onExpandChanged(expanded);
        }
        return false;
      },
      child: DraggableScrollableSheet(
        initialChildSize: 0.25,
        minChildSize: 0.22,
        maxChildSize: 0.95,
        builder: (context, controller) {
          return Padding(
            padding: const EdgeInsets.only(bottom: kBottomNavigationBarHeight),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: isDark ? theme.colorScheme.surface : Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(_isExpanded ? 0 : 24),
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: 14,
                    color: isDark ? Colors.black45 : Colors.black12,
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  if (!_isExpanded)
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  const SizedBox(height: 8),
                  _isExpanded
                      ? _ExpandedHeader(
                          isDark: isDark,
                          theme: theme,
                          searchController: _searchController,
                          onSearchChanged: _onSearchChanged,
                          onClearSearch: _clearSearch,
                          hasQuery: _searchQuery.isNotEmpty,
                        )
                      : _CollapsedHeader(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: widget.loading
                        ? const Center(child: CircularProgressIndicator())
                        : widget.venues.isEmpty
                        ? const Center(
                            child: Text(
                              'No venues found nearby',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : visibleVenues.isEmpty
                        ? const Center(
                            child: Text(
                              'No matching venues',
                              style: TextStyle(color: Colors.grey),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            itemCount: visibleVenues.length,
                            itemBuilder: (_, i) => VenueListItem(
                              venue: visibleVenues[i],
                              isSelected:
                                  widget.selectedVenueId == visibleVenues[i].id,
                              onTap: widget.onVenueTap,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CollapsedHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Discover nearby venues',
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).brightness == Brightness.dark
            ? Colors.white54
            : Colors.grey,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final bool hasQuery;

  const _ExpandedHeader({
    required this.isDark,
    required this.theme,
    required this.searchController,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.hasQuery,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          /// SEARCH BAR
          Expanded(
            child: Container(
              height: 42,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.search,
                    size: 18,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: searchController,
                      onChanged: onSearchChanged,
                      decoration: InputDecoration(
                        hintText: 'Search venues or areas',
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: TextStyle(
                          color: isDark ? Colors.white54 : Colors.grey,
                        ),
                      ),
                      style: TextStyle(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  if (hasQuery)
                    InkWell(
                      onTap: onClearSearch,
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

       
        ],
      ),
    );
  }
}
