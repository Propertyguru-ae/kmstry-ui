import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/venue/data/venue_model.dart';
import 'package:kmstry_frontend/features/checkin/presentation/checkin_upload_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_people_page.dart';

class VenueDetailPage extends StatefulWidget {
  final Venue venue;

  const VenueDetailPage({super.key, required this.venue});

  @override
  State<VenueDetailPage> createState() => _VenueDetailPageState();
}

class _VenueDetailPageState extends State<VenueDetailPage> {
  /// 🔑 BACKEND’DEN GELECEK STATE
  String? _activeCheckinVenueId;
  bool _loadingActiveCheckin = true;

  @override
  void initState() {
    super.initState();
    _loadActiveCheckin();
  }

  /// ⛔ ŞİMDİLİK FAKE
  /// ✅ BACKEND GELİNCE SADECE BURASI DEĞİŞECEK
  Future<void> _loadActiveCheckin() async {
    await Future.delayed(const Duration(milliseconds: 500));

    setState(() {
      // TEST SENARYOLARI (TEK TEK AÇIP DENE)

      // 1️⃣ Aktif check-in YOK
      _activeCheckinVenueId = null;

      // 2️⃣ BU MEKANDA aktif check-in VAR
      // _activeCheckinVenueId = widget.venue.id;

      // 3️⃣ BAŞKA MEKANDA aktif check-in VAR
      // _activeCheckinVenueId = 'another-venue-id';

      _loadingActiveCheckin = false;
    });
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
                      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
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
                  image: const DecorationImage(
                    image: NetworkImage(
                      'https://images.unsplash.com/photo-1517248135467-4c7edcad34c4',
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
                  onPressed: _loadingActiveCheckin || hasActiveCheckinHere
                      ? null
                      : () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => CheckInPage(
                                venueId: widget.venue.id,
                              ),
                            ),
                          );
                        },
                  child: Text(
                    _loadingActiveCheckin
                        ? 'Checking status...'
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

              /// WHO’S HERE
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            VenuePeoplePage(venue: widget.venue),
                      ),
                    );
                  },
                  child: const Text("Who's here?"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
