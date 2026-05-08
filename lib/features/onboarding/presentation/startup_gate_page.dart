import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_theme.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

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
  late final Animation<double> _slideAnimation;
  late final Animation<double> _logoScaleAnimation;
  late final Animation<double> _buttonScaleAnimation;

  bool _checking = true;
  bool _navigating = false;

  static const Color _bgColor = AppTheme.matteBlack;
  static const Color _blue = AppTheme.brandPrimary;
  static const Color _indigo = AppTheme.brandPrimary;
  static const Color _violet = AppTheme.brandPrimary;

  @override
  void initState() {
    super.initState();

    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
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

    _slideAnimation = Tween<double>(begin: 26, end: 0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutCubic),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(parent: _introController, curve: Curves.easeOutBack),
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
    final introSeen = await SecureStorage.isIntroSeen();
    if (!mounted) return;

    if (introSeen) {
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      return;
    }

    setState(() => _checking = false);
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
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            _buildAnimatedBackground(),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    _buildBrandSection(),
                    const Spacer(flex: 4),
                    _buildBottomSection(),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ],
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
                child: _buildGlowSphere(_blue.withOpacity(0.12), 420),
              ),
            ),
            Positioned(
              bottom: -180,
              left: -150,
              child: Transform.rotate(
                angle: -angle * 0.8,
                child: _buildGlowSphere(_indigo.withOpacity(0.10), 500),
              ),
            ),
            Positioned(
              top: 220,
              left: -90,
              child: Transform.rotate(
                angle: angle * 0.55,
                child: _buildGlowSphere(_violet.withOpacity(0.06), 260),
              ),
            ),
            Positioned(
              bottom: 180,
              right: -80,
              child: Transform.rotate(
                angle: -angle * 0.45,
                child: _buildGlowSphere(_blue.withOpacity(0.06), 240),
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
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value),
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(scale: _logoScaleAnimation, child: child),
          ),
        );
      },
      child: Column(
        children: [
          ScaleTransition(
            scale: _pulseController,
            child: Container(
              width: 156,
              height: 156,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(42),
                color: Colors.white.withOpacity(0.028),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: _blue.withOpacity(0.12),
                    blurRadius: 30,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Image.asset(
                  'assets/images/kmstrylogo.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.center,
                ),
              ),
            ),
          ),
          const SizedBox(height: 42),
          const Text(
            'KMSTRY',
            style: TextStyle(
              color: Colors.white,
              fontSize: 50,
              fontWeight: FontWeight.w900,
              letterSpacing: 7,
              height: 1,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'REAL PLACES. REAL FACES.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withOpacity(0.58),
              fontSize: 12,
              letterSpacing: 2.8,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _buildBottomSection() {
    return AnimatedBuilder(
      animation: _introController,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _slideAnimation.value * 0.8),
          child: FadeTransition(opacity: _fadeAnimation, child: child),
        );
      },
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: _checking
                ? const SizedBox(
                    height: 60,
                    width: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white24,
                    ),
                  )
                : ScaleTransition(
                    scale: _buttonScaleAnimation,
                    child: _buildContinueButton(),
                  ),
          ),
          const SizedBox(height: 34),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTinyDot(),
              const SizedBox(width: 10),
              Text(
                'KNOW BEFORE YOU GO',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.28),
                  fontSize: 11,
                  letterSpacing: 2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              _buildTinyDot(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContinueButton() {
    return SizedBox(
      width: double.infinity,
      height: 62,
      child: ElevatedButton(
        onPressed: _navigating ? null : _goToIntro,
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 120),
          backgroundColor: const WidgetStatePropertyAll<Color>(
            Colors.transparent,
          ),
          shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
          foregroundColor: const WidgetStatePropertyAll<Color>(Colors.black),
          elevation: const WidgetStatePropertyAll<double>(0),
          padding: const WidgetStatePropertyAll<EdgeInsets>(
            EdgeInsets.symmetric(horizontal: 24),
          ),
          shape: WidgetStatePropertyAll<RoundedRectangleBorder>(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(40)),
          ),
          textStyle: const WidgetStatePropertyAll<TextStyle>(
            TextStyle(
              inherit: false,
              fontFamily: 'CupertinoSystemText',
              fontWeight: FontWeight.w900,
              letterSpacing: 2.2,
              fontSize: 15,
              height: 1.2,
              color: Colors.black,
            ),
          ),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Colors.white, Colors.white],
            ),
            borderRadius: BorderRadius.circular(40),
            boxShadow: [ ],
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
                      Text('CONTINUE'),
                      SizedBox(width: 10),
                      Icon(Icons.arrow_forward_rounded, size: 20),
                    ],
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

  Widget _buildTinyDot() {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
    );
  }
}
