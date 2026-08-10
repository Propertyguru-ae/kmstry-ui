import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class AppIntroPage extends StatefulWidget {
  const AppIntroPage({super.key});

  @override
  State<AppIntroPage> createState() => _AppIntroPageState();
}

class _AppIntroPageState extends State<AppIntroPage> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  bool _completing = false;

  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      title: 'See What’s Happening Around You',
      description:
          'Discover people and venues nearby and explore the energy of your city.',
      icon: Icons.people_alt_outlined,
    ),
    _IntroSlide(
      title: 'Showcase Your Venue',
      description:
          'Own a venue? Create a venue account and let people discover your place.',
      icon: Icons.storefront_outlined,
    ),

    _IntroSlide(
      title: 'Share The Moment',
      description:
          'Check in, post photos or videos, and be part of the city’s social scene.',
      icon: Icons.video_camera_front_outlined,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _completeIntro() async {
    if (_completing) return;
    setState(() => _completing = true);
    try {
      await SecureStorage.setIntroSeen();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } finally {
      if (mounted) {
        setState(() => _completing = false);
      }
    }
  }

  Future<void> _next() async {
    if (_currentIndex >= _slides.length - 1) {
      await _completeIntro();
      return;
    }
    await _pageController.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Column(
            children: [
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _slides.length,
                  onPageChanged: (index) =>
                      setState(() => _currentIndex = index),
                  itemBuilder: (context, index) {
                    final slide = _slides[index];
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 128,
                          height: 128,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.primary.withValues(alpha: 0.12),
                          ),
                          child: Icon(
                            slide.icon,
                            size: 64,
                            color: colors.primary,
                          ),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          slide.title,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          slide.description,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.8),
                            height: 1.35,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_slides.length, (index) {
                  final selected = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: selected ? 22 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.primary
                          : colors.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(99),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _completing ? null : _next,
                  child: _completing
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          _currentIndex == _slides.length - 1
                              ? 'Get Started'
                              : 'Next',
                        ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntroSlide {
  final String title;
  final String description;
  final IconData icon;

  const _IntroSlide({
    required this.title,
    required this.description,
    required this.icon,
  });
}
