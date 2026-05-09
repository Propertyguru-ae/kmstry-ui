import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/data/me_context_model.dart';
import 'package:kmstry_frontend/features/onboarding/presentation/username_onboarding_page.dart';

class VenueAccountHomePage extends StatefulWidget {
  const VenueAccountHomePage({super.key});

  @override
  State<VenueAccountHomePage> createState() => _VenueAccountHomePageState();
}

class _VenueAccountHomePageState extends State<VenueAccountHomePage> {
  bool _bannerLoading = false;
  bool _showPersonalBanner = false;

  @override
  void initState() {
    super.initState();
    _loadPersonalBannerState();
  }

  Future<void> _loadPersonalBannerState() async {
    try {
      final me = await AuthRepository().getMe();
      final contextModel = MeContextModel.fromMe(me);
      if (!mounted) return;
      setState(() {
        _showPersonalBanner = !contextModel.hasPersonalProfile;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _showPersonalBanner = false;
      });
    }
  }

  Future<void> _startPersonalOnboarding() async {
    if (_bannerLoading) return;
    setState(() => _bannerLoading = true);
    try {
      await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const UsernameOnboardingPage()),
      );
    } catch (_) {
      if (!mounted) return;
      await showPremiumErrorDialog(
        context,
        message: 'Could not start personal onboarding.',
      );
    } finally {
      if (!mounted) return;
      setState(() => _bannerLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      child: Stack(
        children: [
          Center(
            child: Text(
              'Welcome to venue account',
              style: TextStyle(
                color: colors.onSurface,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          if (_showPersonalBanner)
            Positioned(
              left: 12,
              right: 12,
              top: 12,
              child: Material(
                elevation: 2,
                borderRadius: BorderRadius.circular(14),
                color: colors.surface,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colors.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Want to use Kmstry as a person too?',
                          style: TextStyle(
                            color: colors.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: _bannerLoading ? null : _startPersonalOnboarding,
                        child: const Text('Start'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
