import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/signup_page.dart';

/// Kayit akisinin ilk adimi: kisisel mi yoksa mekan hesabi mi aciyor?
/// Login sayfasindaki "Kayit Ol" dugmesine basilinca gosterilir.
class ContextChoicePage extends StatelessWidget {
  const ContextChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? Theme.of(context).scaffoldBackgroundColor : Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      'How would you\nlike to join?',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: colors.onSurface,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Choose the account type that fits you best.\nYou can add the other one later.',
                      style: TextStyle(
                        fontSize: 15,
                        color: colors.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Personal card
                    _ChoiceCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal',
                      subtitle:
                          'Discover venues, meet people\nand share moments.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignupPage(isVenueSignup: false),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 16),

                    // Venue card
                    _ChoiceCard(
                      icon: Icons.store_mall_directory_outlined,
                      title: 'Venue',
                      subtitle:
                          'Manage your venue, engage guests\nand grow your presence.',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SignupPage(isVenueSignup: true),
                          ),
                        );
                      },
                    ),

                    const Spacer(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ChoiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
        decoration: BoxDecoration(
          color: isDark
              ? colors.surface
              : colors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colors.outline.withValues(alpha: isDark ? 0.22 : 0.32),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: colors.primary, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: colors.onSurface.withValues(alpha: 0.60),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: colors.onSurface.withValues(alpha: 0.38),
            ),
          ],
        ),
      ),
    );
  }
}
