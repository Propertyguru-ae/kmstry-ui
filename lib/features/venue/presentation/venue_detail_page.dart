import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/venue/data/venue_checkin_reporsitory.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';

class VenueDetailPage extends StatefulWidget {
  final Venue venue;

  const VenueDetailPage({super.key, required this.venue});

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  final _repo = VenueCheckinRepository();
  String? _activeCheckinVenueId;
  bool _loadingActiveCheckin = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCheckin();
  }

  Future<void> _loadActiveCheckin() async {
    try {
      final activeCheckin = await _repo.getActiveCheckin();
      
      debugPrint('🔍 DEBUG: activeCheckin = $activeCheckin');
      debugPrint('🔍 DEBUG: activeCheckin?.venueId = ${activeCheckin?.venueId}');
      debugPrint('🔍 DEBUG: widget.venue.id = ${widget.venue.id}');
      debugPrint('🔍 DEBUG: venue.id type = ${widget.venue.id.runtimeType}');
      debugPrint('🔍 DEBUG: venueId type = ${activeCheckin?.venueId.runtimeType}');
      
      setState(() {
        _activeCheckinVenueId = activeCheckin?.venueId;
        _loadingActiveCheckin = false;
      });
      
      debugPrint('🔍 DEBUG: _activeCheckinVenueId = $_activeCheckinVenueId');
      debugPrint('🔍 DEBUG: hasActiveCheckinHere = ${_activeCheckinVenueId == widget.venue.id}');
    } catch (e) {
      // On error, assume no active check-in
      debugPrint('⚠️ Error loading active check-in: $e');
      setState(() {
        _activeCheckinVenueId = null;
        _loadingActiveCheckin = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasActiveCheckinHere =
        _activeCheckinVenueId == widget.venue.id;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// BACK
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),

              const SizedBox(height: 8),

              /// HEADER
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      widget.venue.photoUrl.isNotEmpty
                          ? widget.venue.photoUrl
                          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                      width: 40,
                      height: 40,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.venue.name,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.venue.status,
                    style: const TextStyle(color: Colors.grey),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              /// COVER IMAGE
              Container(
                height: 220,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: NetworkImage(
                      widget.venue.photoUrl.isNotEmpty
                          ? widget.venue.photoUrl
                          : 'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
                    ),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withOpacity(0.35),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              /// TAG
              Text(
                '#${widget.venue.tag}',
                style: const TextStyle(
                  color: Colors.blue,
                  fontWeight: FontWeight.w600,
                ),
              ),

              const SizedBox(height: 8),

              /// ADDRESS
              Text(
                widget.venue.address,
                style: const TextStyle(color: Colors.grey),
              ),

              const SizedBox(height: 8),

              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.map),
                label: const Text('Get Directions'),
              ),

              const SizedBox(height: 24),

              /// ✅ CHECK-IN BUTTON (KURAL BURADA)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _loadingActiveCheckin ||
                          hasActiveCheckinHere ||
                          !widget.venue.canCheckin
                      ? null
                      : () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckInPage(
                                venueId: widget.venue.id,
                              ),
                            ),
                          );
                          // Refresh check-in state after returning from check-in page
                          _loadActiveCheckin();
                        },
                  child: Text(
                    _loadingActiveCheckin
                        ? 'Checking status...'
                        : !widget.venue.canCheckin
                            ? 'Community data pending (details only)'
                            : hasActiveCheckinHere
                            ? 'You are already checked in'
                            : 'Check In Live',
                  ),
                ),
              ),

              if (!_loadingActiveCheckin && hasActiveCheckinHere)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'You can only check in once per venue.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),

              const SizedBox(height: 12),

              /// WHO'S HERE
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: hasActiveCheckinHere
                      ? () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  VenuePeoplePage(venue: widget.venue),
                            ),
                          );
                        }
                      : null,
                  child: Text(
                    _loadingActiveCheckin
                        ? "Loading..."
                        : hasActiveCheckinHere
                            ? "Who's here?"
                            : "Who's here? (Check in first)",
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
