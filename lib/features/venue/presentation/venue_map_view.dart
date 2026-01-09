import 'package:flutter/material.dart';

class VenueMapView extends StatelessWidget {
  final bool hideSearch;

  const VenueMapView({super.key, this.hideSearch = false});
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        /// MAP PLACEHOLDER (Google Map / Mapbox buraya gelecek)
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFF2F2F2), Color(0xFFE6E6E6)],
            ),
          ),
        ),

        /// HEATMAP SPOTS (mock)
        ..._buildHeatSpots(),

        /// VENUE LABELS
        _venueLabel('After Eight', top: 180, left: 160),
        _venueLabel('Sidewalk Bar', top: 210, left: 210),
        _venueLabel('Social Club', top: 300, left: 80),
        _venueLabel('Sunset Sessions', top: 360, left: 140),

        /// SEARCH BAR
        /// SEARCH BAR
        if (!hideSearch)
          Positioned(top: 14, left: 16, right: 16, child: _SearchBar()),

        /// RIGHT FLOATING CONTROLS
        if (!hideSearch)
          Positioned(
            right: 16,
            top: 90,
            child: Column(
              children: const [
                _CircleIcon(Icons.layers_outlined),
                SizedBox(height: 12),
                _CircleIcon(Icons.navigation_outlined),
              ],
            ),
          ),
      ],
    );
  }

  // --------------------
  // Helpers
  // --------------------

  static List<Widget> _buildHeatSpots() {
    return [
      _heatSpot(top: 260, left: 180),
      _heatSpot(top: 310, left: 120),
      _heatSpot(top: 220, left: 230),
    ];
  }

  static Widget _heatSpot({required double top, required double left}) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              Colors.red.withOpacity(0.8),
              Colors.orange.withOpacity(0.4),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  static Widget _venueLabel(
    String text, {
    required double top,
    required double left,
  }) {
    return Positioned(
      top: top,
      left: left,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black12)],
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// SEARCH BAR
class _SearchBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            blurRadius: 12,
            offset: Offset(0, 4),
            color: Colors.black12,
          ),
        ],
      ),
      child: Row(
        children: const [
          Icon(Icons.search, size: 20, color: Colors.grey),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Search venues or areas',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

/// FLOATING ICON
class _CircleIcon extends StatelessWidget {
  final IconData icon;
  const _CircleIcon(this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(blurRadius: 8, color: Colors.black12)],
      ),
      child: Icon(icon),
    );
  }
}
