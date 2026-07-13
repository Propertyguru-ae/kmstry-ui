import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_section.dart';

/// Manage > Analytics ekranı — analytics bloğunu tam sayfa gösterir.
class VenueAnalyticsScreen extends StatelessWidget {
  final String venueId;
  final String? venueName;

  const VenueAnalyticsScreen({super.key, required this.venueId, this.venueName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: VenueAnalyticsSection(venueId: venueId),
      ),
    );
  }
}
