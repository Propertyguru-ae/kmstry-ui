import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
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

  static const _bg = AppColors.darkBg;
  static const _teal = AppColors.teal;
  static const _tealBright = AppColors.tealDark;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magenta;
  static const _purple = AppColors.brandLight;
  static const _muted = Color(0xFFA6B3D2);

  static const List<_IntroSlide> _slides = [
    _IntroSlide(
      title: 'See What’s Happening Around You',
      description:
          'Discover people and venues nearby and explore the energy of your city.',
      icon: Icons.travel_explore_rounded,
      iconColor: _tealBright,
      gradient: [_blueBright, _tealBright],
    ),
    _IntroSlide(
      title: 'Showcase Your Venue',
      description:
          'Own a venue? Create a venue account and let people discover your place.',
      icon: Icons.storefront_rounded,
      primary: _blueBright,
      secondary: _teal,
      gradient: [_teal, _blueBright],
    ),

    _IntroSlide(
      title: 'Share The Moment',
      description:
          'Check in, post photos or videos, and be part of the city’s social scene.',
      icon: Icons.auto_awesome_rounded,
      primary: _teal,
      secondary: _magenta,
      gradient: [_teal, _blueBright],
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
    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          Positioned(
            top: -90,
            left: 0,
            right: 0,
            child: Center(
              child: _glow(330, 280, _blue.withValues(alpha: 0.16)),
            ),
          ),
          Positioned(
            bottom: 90,
            right: -70,
            child: _glow(240, 240, _magenta.withValues(alpha: 0.10)),
          ),
          Positioned(
            top: 290,
            left: -80,
            child: _glow(210, 210, _purple.withValues(alpha: 0.12)),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
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
                              width: 148,
                              height: 148,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: [
                                    slide.primary.withValues(alpha: 0.26),
                                    slide.secondary.withValues(alpha: 0.16),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: slide.primary.withValues(alpha: 0.24),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: slide.primary.withValues(
                                      alpha: 0.20,
                                    ),
                                    blurRadius: 38,
                                    offset: const Offset(0, 16),
                                  ),
                                ],
                              ),
                              child: Icon(
                                slide.icon,
                                size: 68,
                                color: slide.iconColor,
                              ),
                            ),
                            const SizedBox(height: 34),
                            _gradientTitle(slide.title, slide.gradient),
                            const SizedBox(height: 14),
                            Text(
                              slide.description,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 15.5,
                                height: 1.45,
                                fontWeight: FontWeight.w500,
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
                        width: selected ? 28 : 9,
                        height: 9,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          gradient: selected
                              ? const LinearGradient(
                                  colors: [_blueBright, _teal],
                                )
                              : null,
                          color: selected
                              ? null
                              : Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(99),
                          boxShadow: [
                            if (selected)
                              BoxShadow(
                                color: _blue.withValues(alpha: 0.26),
                                blurRadius: 12,
                                offset: const Offset(0, 3),
                              ),
                          ],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  PrimaryButton(
                    label: _currentIndex == _slides.length - 1
                        ? 'Get Started'
                        : 'Next',
                    onPressed: _completing ? null : _next,
                    loading: _completing,
                    trailingArrow: _currentIndex != _slides.length - 1,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _gradientTitle(String title, List<Color> colors) {
    final words = title.split(' ');
    final firstLine = words.length > 2
        ? words.sublist(0, words.length - 2).join(' ')
        : title;
    final secondLine = words.length > 2
        ? words.sublist(words.length - 2).join(' ')
        : '';

    return Column(
      children: [
        Text(
          firstLine,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 30,
            height: 1.12,
            letterSpacing: -0.7,
            fontWeight: FontWeight.w800,
            color: Color(0xFFF4F6FF),
          ),
        ),
        if (secondLine.isNotEmpty)
          ShaderMask(
            shaderCallback: (bounds) =>
                LinearGradient(colors: colors).createShader(bounds),
            child: Text(
              secondLine,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 30,
                height: 1.12,
                letterSpacing: -0.7,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  Widget _glow(double w, double h, Color color) {
    return IgnorePointer(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.65],
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
  final Color primary;
  final Color secondary;
  final Color? iconColorOverride;
  final List<Color> gradient;

  const _IntroSlide({
    required this.title,
    required this.description,
    required this.icon,
    this.primary = _AppIntroPageState._blueBright,
    this.secondary = _AppIntroPageState._teal,
    Color? iconColor,
    this.gradient = const [
      _AppIntroPageState._blueBright,
      _AppIntroPageState._teal,
    ],
  }) : iconColorOverride = iconColor;

  Color get iconColor => iconColorOverride ?? primary;
}
