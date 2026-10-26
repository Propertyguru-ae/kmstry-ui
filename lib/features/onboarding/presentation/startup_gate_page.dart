import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'startup_brand.dart';

class StartupGatePage extends StatefulWidget {
  const StartupGatePage({super.key});

  @override
  State<StartupGatePage> createState() => _StartupGatePageState();
}

class _StartupGatePageState extends State<StartupGatePage>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _bgController;
  late final AnimationController _pulseController;
  late final AnimationController _buttonPressController;

  late final Animation<double> _fadeAnimation;
  late final Animation<double> _buttonScaleAnimation;

  bool _checking = true;
  bool _navigating = false;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bgColor => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  static const Color _blue = AppColors.blue;
  static const Color _blueBright = AppColors.blueDark;
  static const Color _magenta = AppColors.magentaDark;
  static const Color _teal = AppColors.tealDark;
  static const Color _brand = AppColors.brand;
  Color get _muted =>
      _isDark ? const Color(0xFFA6B3D2) : AppColors.lightTextSecondary;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: StartupBrand.revealDuration,
    );

    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
      lowerBound: 0.98,
      upperBound: 1.03,
    )..repeat(reverse: true);

    _buttonPressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      lowerBound: 0.97,
      upperBound: 1.0,
      value: 1.0,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _introController,
      curve: Curves.easeOut,
    );

    _buttonScaleAnimation = CurvedAnimation(
      parent: _buttonPressController,
      curve: Curves.easeOut,
    );

    _introController.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startFlow());
  }

  @override
  void dispose() {
    _introController.dispose();
    _bgController.dispose();
    _pulseController.dispose();
    _buttonPressController.dispose();
    super.dispose();
  }

  Future<void> _startFlow() async {
    final updateRequired = await _checkVersionPolicy();
    if (updateRequired || !mounted) return;

    final introSeen = await SecureStorage.isIntroSeen();
    if (!mounted) return;

    if (introSeen) {
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      return;
    }

    setState(() => _checking = false);
  }

  Future<bool> _checkVersionPolicy() async {
    try {
      await ApiClient().get(
        '/app/version-policy',
        timeout: const Duration(seconds: 4),
      );
      return false;
    } on ApiException catch (error) {
      // The ApiClient has already handed this response to the global update
      // coordinator. Stop startup navigation while that screen is opening.
      return error.statusCode == 426 &&
          error.data['errorCode'] == 'APP_UPDATE_REQUIRED';
    } catch (_) {
      // Offline, DNS and temporary backend failures must not trap users on the
      // splash screen. Existing offline handling continues in AuthGate.
      return false;
    }
  }

  Future<void> _goToIntro() async {
    if (_navigating) return;

    setState(() => _navigating = true);

    try {
      await _buttonPressController.reverse();
      await _buttonPressController.forward();
    } on TickerCanceled {
      return;
    }

    if (!mounted) return;

    Navigator.pushReplacementNamed(context, AuthRoutes.appIntro);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: _isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: LayoutBuilder(
          builder: (context, constraints) => Stack(
            fit: StackFit.expand,
            children: [
              FadeTransition(
                key: const ValueKey('startup-background-reveal'),
                opacity: _fadeAnimation,
                child: _buildAnimatedBackground(),
              ),
              // Same canvas and full-screen anchor as the native launch image.
              // Footer/loading/label changes cannot move the brand layer.
              Positioned(
                left: (constraints.maxWidth - StartupBrand.size.width) / 2,
                top:
                    (constraints.maxHeight - StartupBrand.size.height) / 2 -
                    StartupBrand.lift,
                width: StartupBrand.size.width,
                height: StartupBrand.size.height,
                child: _buildBrandSection(),
              ),
              Positioned(
                left: 28,
                right: 28,
                bottom: MediaQuery.viewPaddingOf(context).bottom + 18,
                child: _buildBottomSection(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedBackground() {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (context, child) {
        final angle = _bgController.value * 2 * math.pi;

        return Stack(
          children: [
            Positioned(
              top: -140,
              right: -120,
              child: Transform.rotate(
                angle: angle,
                child: _buildGlowSphere(_blue.withValues(alpha: 0.08), 420),
              ),
            ),
            Positioned(
              bottom: -180,
              left: -150,
              child: Transform.rotate(
                angle: -angle * 0.8,
                child: _buildGlowSphere(_brand.withValues(alpha: 0.08), 500),
              ),
            ),
            Positioned(
              top: 220,
              left: -90,
              child: Transform.rotate(
                angle: angle * 0.55,
                child: _buildGlowSphere(_magenta.withValues(alpha: 0.04), 260),
              ),
            ),
            Positioned(
              bottom: 180,
              right: -80,
              child: Transform.rotate(
                angle: -angle * 0.45,
                child: _buildGlowSphere(_teal.withValues(alpha: 0.04), 240),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color.fromARGB(0, 0, 0, 0),
                    Color.fromARGB(0, 0, 0, 0),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBrandSection() {
    return Stack(
      children: [
        Positioned(
          left: StartupBrand.logoCenter.dx - 83,
          top: StartupBrand.logoCenter.dy - 83,
          width: 166,
          height: 166,
          child: AnimatedBuilder(
            animation: Listenable.merge([_introController, _pulseController]),
            builder: (context, child) {
              final fade = _fadeAnimation.value;
              final shimmer = ((_pulseController.value - 0.98) / 0.05).clamp(
                0.0,
                1.0,
              );
              final border = Color.lerp(
                (_isDark ? Colors.white : AppColors.lightTextPrimary)
                    .withValues(alpha: 0.12),
                (_isDark ? _blueBright : AppColors.blueLight).withValues(
                  alpha: 0.38,
                ),
                shimmer,
              )!;
              // Only the decoration changes. The symbol never scales/pulses.
              return DecoratedBox(
                key: const ValueKey('startup-logo-decoration'),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(44),
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withValues(alpha: 0.070 * fade),
                      _blue.withValues(alpha: (0.045 + shimmer * 0.020) * fade),
                      _brand.withValues(alpha: 0.055 * fade),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  border: Border.all(
                    color: Color.lerp(Colors.transparent, border, fade)!,
                    width: 1.1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _blue.withValues(
                        alpha: (0.16 + shimmer * 0.06) * fade,
                      ),
                      blurRadius: 34,
                      spreadRadius: 2,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        Positioned.fill(
          child: Image.asset(
            StartupBrand.assetFor(Theme.of(context).brightness),
            key: StartupBrand.imageKey,
            width: StartupBrand.size.width,
            height: StartupBrand.size.height,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            semanticLabel: 'KMSTRY',
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: StartupBrand.wordmarkBottom + 18,
          child: FadeTransition(
            key: const ValueKey('startup-tagline-reveal'),
            opacity: _fadeAnimation,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.only(left: 2.8),
                child: Text(
                  'REAL PLACES. REAL FACES.',
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    color: _muted.withValues(alpha: _isDark ? 0.76 : 1),
                    fontSize: 12,
                    letterSpacing: 2.8,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomSection() {
    return FadeTransition(
      key: const ValueKey('startup-footer-reveal'),
      opacity: _fadeAnimation,
      child: AnimatedSwitcher(
        duration: StartupBrand.revealDuration,
        child: _checking
            ? SizedBox(
                height: 62,
                child: Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _isDark ? Colors.white24 : AppColors.blueLight,
                    ),
                  ),
                ),
              )
            : ScaleTransition(
                scale: _buttonScaleAnimation,
                child: _buildContinueButton(),
              ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(40),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: _navigating ? null : _goToIntro,
          child: Ink(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_blueBright, _blue],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(40),
            ),
            child: Center(
              child: _navigating
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'CONTINUE',
                          style: TextStyle(
                            inherit: false,
                            fontFamily: 'CupertinoSystemText',
                            fontWeight: FontWeight.w900,
                            letterSpacing: 2.2,
                            fontSize: 15,
                            height: 1.2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 10),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 20,
                          color: Colors.white,
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGlowSphere(Color color, double size) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
            stops: const [0.18, 1.0],
          ),
        ),
      ),
    );
  }
}
