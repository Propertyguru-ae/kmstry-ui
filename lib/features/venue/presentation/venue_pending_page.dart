import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

/// Venue claim gonderilmis, admin onayi bekleniyor.
/// homeRoute == 'VENUE_PENDING' iken gosterilir.
class VenuePendingPage extends StatelessWidget {
  const VenuePendingPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.hourglass_top_rounded,
                    size: 44,
                    color: colors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Claim Under Review',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              Text(
                'We received your venue ownership request and our team is reviewing it. '
                'You will be notified by email once it is approved.',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.onSurface.withValues(alpha: 0.65),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 40),
              OutlinedButton(
                onPressed: () {
                  // Refresh auth_gate to pick up any status change
                  Navigator.of(context)
                      .pushReplacementNamed(AuthRoutes.authGate);
                },
                child: const Text('Check status'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () {
                  // Let user sign out / switch to personal context from auth_gate
                  Navigator.of(context)
                      .pushReplacementNamed(AuthRoutes.authGate);
                },
                child: Text(
                  'Back to app',
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}
