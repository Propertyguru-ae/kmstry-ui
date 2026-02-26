import 'package:flutter/material.dart';
import 'venue_map_view.dart';
import 'venue_bottom_sheet.dart';

class VenueHomePage extends StatefulWidget {
  const VenueHomePage({super.key});

  @override
  State<VenueHomePage> createState() => _VenueHomePageState();
}

class _VenueHomePageState extends State<VenueHomePage> {
  bool isSheetExpanded = false;
  bool _locationAvailable = false;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          VenueMapView(
            hideSearch: isSheetExpanded,
            onLocationAccessChanged: (granted) {
              if (!mounted) return;
              setState(() {
                _locationAvailable = granted;
              });
            },
          ),
          if (_locationAvailable)
            VenueBottomSheet(
              onExpandChanged: (expanded) {
                setState(() => isSheetExpanded = expanded);
              },
            ),
        ],
      ),
    );
  }
}

