import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';

class VenueContextOnboardingPage extends StatefulWidget {
  const VenueContextOnboardingPage({super.key});

  @override
  State<VenueContextOnboardingPage> createState() =>
      _VenueContextOnboardingPageState();
}

class _VenueContextOnboardingPageState extends State<VenueContextOnboardingPage> {
  final _placeIdController = TextEditingController();
  final _repo = VenueContextRepository();
  bool _loading = false;
  Map<String, dynamic>? _preview;
  String? _error;

  @override
  void dispose() {
    _placeIdController.dispose();
    super.dispose();
  }

  Future<void> _previewPlace() async {
    final placeId = _placeIdController.text.trim();
    if (placeId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.getPlaceDetails(placeId);
      if (!mounted) return;
      setState(() {
        _preview = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not fetch place details.';
        _loading = false;
      });
    }
  }

  Future<void> _claimVenue() async {
    final placeId = _placeIdController.text.trim();
    if (placeId.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final claimed = await _repo.claimVenueFromPlace(placeId);
      final venueRaw = claimed['venue'];
      String? venueId;
      if (venueRaw is Map) {
        venueId = venueRaw['id']?.toString();
      } else {
        venueId = claimed['venueId']?.toString();
      }
      if (venueId == null || venueId.isEmpty) {
        final me = await AuthRepository().getMe();
        final meContext = MeContextModel.fromMe(me);
        venueId = meContext.activeVenueId ??
            (meContext.memberVenues.isNotEmpty
                ? meContext.memberVenues.first.id
                : null);
      }
      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: venueId,
      );
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
    } catch (_) {
      final continued = await _continueIfVenueContextExists();
      if (!mounted || continued) {
        return;
      }
      if (!mounted) return;
      setState(() {
        _error = 'Could not claim venue. Please try another place.';
        _loading = false;
      });
    }
  }

  Future<bool> _continueIfVenueContextExists() async {
    try {
      final me = await AuthRepository().getMe();
      final meContext = MeContextModel.fromMe(me);
      final hasVenueHome =
          (meContext.homeRoute?.toUpperCase() == 'VENUE_HOME') ||
              (meContext.nextAction?.toUpperCase() == 'GO_TO_VENUE_HOME');
      final hasVenueMembership =
          meContext.hasVenueMembership || meContext.memberVenues.isNotEmpty;
      final fallbackVenueId = meContext.activeVenueId ??
          (meContext.memberVenues.isNotEmpty
              ? meContext.memberVenues.first.id
              : null);
      if (!hasVenueMembership && !hasVenueHome) {
        return false;
      }
      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: fallbackVenueId,
      );
      if (!mounted) return true;
      Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeName =
        _preview?['name']?.toString() ??
        _preview?['venue']?['name']?.toString() ??
        '';
    return Scaffold(
      appBar: AppBar(title: const Text('Venue onboarding')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Claim your venue by Google Place ID',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _placeIdController,
            decoration: const InputDecoration(
              labelText: 'Google Place ID',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _loading ? null : _previewPlace,
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _loading ? null : _claimVenue,
                  child: const Text('Claim Venue'),
                ),
              ),
            ],
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _loading
                    ? null
                    : () async {
                        setState(() => _loading = true);
                        final continued = await _continueIfVenueContextExists();
                        if (!mounted || continued) {
                          return;
                        }
                        setState(() => _loading = false);
                      },
                child: const Text('Continue with linked venue'),
              ),
            ),
          ],
          if (placeName.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Preview: $placeName',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }
}
