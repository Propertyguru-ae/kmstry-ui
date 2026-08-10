import 'package:flutter/material.dart';
//import 'package:google_maps_flutter/google_maps_flutter.dart';

class VenueMap extends StatelessWidget {
  const VenueMap({super.key});

  @override
  Widget build(BuildContext context) {
    /* return GoogleMap(
      initialCameraPosition: const CameraPosition(
        target: LatLng(25.2048, 55.2708), // Dubai
        zoom: 13,
      ),
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
    );*/
    return Container(
      color: Colors.grey.shade300,
      alignment: Alignment.center,
      child: const Text(
        'Map coming soon',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }
}
