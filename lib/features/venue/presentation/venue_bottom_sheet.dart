import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_repository.dart';
import '../data/venue_dummy_data.dart';
import 'venue_list_item.dart';

class VenueBottomSheet extends StatefulWidget {
  final ValueChanged<bool> onExpandChanged;

  const VenueBottomSheet({super.key, required this.onExpandChanged});
  @override
  State<VenueBottomSheet> createState() => _VenueBottomSheetState();
}

class _VenueBottomSheetState extends State<VenueBottomSheet> {
  bool _isExpanded = false;
  List<Venue> _venues = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  Future<void> _loadVenues() async {
    try {
      final venues = await VenueRepository().getVenues();
      setState(() {
        _venues = venues;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ Venue load error: $e');
      setState(() => _loading = false);
    }
  }
  @override
  Widget build(BuildContext context) {

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return DraggableScrollableSheet(
      initialChildSize: 0.25,
      minChildSize: 0.22,
      maxChildSize: 0.95,

      builder: (context, controller) {
        /// 👇👇👇 TAM OLARAK BURAYA KOYUYORSUN
        controller.addListener(() {
          final expanded = controller.position.pixels > 120;

          if (expanded != _isExpanded) {
            _isExpanded = expanded;
            widget.onExpandChanged(expanded);
            setState(() {});
          }
        });

        /// 👆👆👆

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

                _isExpanded ? _ExpandedHeader(isDark: isDark, theme: theme) : _CollapsedHeader(),

                const SizedBox(height: 8),

                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _venues.isEmpty
                      ? const Center(
                          child: Text(
                            'No venues found nearby',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: controller,
                          itemCount: _venues.length,
                          itemBuilder: (_, i) =>
                              VenueListItem(venue: _venues[i]),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CollapsedHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      'Over 1,000 venues in this area',
      style: TextStyle(
        fontSize: 13,
        color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.grey,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _ExpandedHeader extends StatelessWidget {
  final bool isDark;
  final ThemeData theme;

  const _ExpandedHeader({required this.isDark, required this.theme});

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
                color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, size: 18, color: isDark ? Colors.white54 : Colors.grey),
                  const SizedBox(width: 8),
                  Text(
                    'Search venues or areas',
                    style: TextStyle(color: isDark ? Colors.white54 : Colors.grey, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 12),

          /// FILTER ICON
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.05) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.tune, size: 20, color: isDark ? Colors.white70 : Colors.black87),
          ),
        ],
      ),
    );
  }
}
