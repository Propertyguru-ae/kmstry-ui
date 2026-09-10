import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/app_back_button.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_analytics_section.dart';

/// Manage > Analytics ekranı — analytics bloğunu tam sayfa gösterir.
class VenueAnalyticsScreen extends StatefulWidget {
  final String venueId;
  final String? venueName;

  const VenueAnalyticsScreen({super.key, required this.venueId, this.venueName});

  @override
  State<VenueAnalyticsScreen> createState() => _VenueAnalyticsScreenState();
}

class _VenueAnalyticsScreenState extends State<VenueAnalyticsScreen> {
  final _analyticsKey = GlobalKey<VenueAnalyticsSectionState>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leadingWidth: 60,
        leading: const Padding(
          padding: EdgeInsets.only(left: 14),
          child: AppBackButton(),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => _analyticsKey.currentState?.refresh() ?? Future.value(),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          child: VenueAnalyticsSection(
            key: _analyticsKey,
            venueId: widget.venueId,
          ),
        ),
      ),
    );
  }
}
