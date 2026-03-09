import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/name_dob_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_context_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';

class ContextChoicePage extends StatefulWidget {
  const ContextChoicePage({super.key});

  @override
  State<ContextChoicePage> createState() => _ContextChoicePageState();
}

class _ContextChoicePageState extends State<ContextChoicePage> {
  final _venueContextRepository = VenueContextRepository();
  bool _loading = false;

  Future<void> _choosePersonal() async {
    setState(() => _loading = true);
    try {
      await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const NameDobOnboardingPage()),
      );
    } catch (_) {
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
    }
  }

  Future<void> _chooseVenue() async {
    setState(() => _loading = true);
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const VenueContextOnboardingPage()),
    );
  }

  Future<void> _quickVenueTest() async {
    final placeId = await _askTestPlaceId();
    if (placeId == null || placeId.isEmpty) return;

    setState(() => _loading = true);
    try {
      final claimed = await _venueContextRepository.claimVenueFromPlace(placeId);
      final venueRaw = claimed['venue'];
      String? venueId;
      if (venueRaw is Map) {
        venueId = venueRaw['id']?.toString();
      } else {
        venueId = claimed['venueId']?.toString();
      }

      await AuthRepository().switchContext(
        lastActiveContext: 'VENUE',
        activeVenueId: venueId,
      );

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.appShell);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not create a venue test account.')),
      );
    }

  }

  Future<String?> _askTestPlaceId() async {
    final ctrl = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Venue test setup'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Google Place ID',
            hintText: 'Enter test place id',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(ctrl.text.trim()),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose your mode')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            const Text(
              'How do you want to continue?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'You can switch this later from your account context menu.',
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _loading ? null : _choosePersonal,
              child: const Text('Personal'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _loading ? null : _chooseVenue,
              child: const Text('Venue'),
            ),
            if (kDebugMode) ...[
              const SizedBox(height: 10),
              TextButton(
                onPressed: _loading ? null : _quickVenueTest,
                child: const Text(
                  'Quick test: Create venue context directly',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
