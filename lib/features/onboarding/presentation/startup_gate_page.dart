import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  static const Color _bgColor = Color(0xFF040404);
  static const Color _cyan = Color(0xFF00E5FF);
  static const Color _pink = Color(0xFFFF00C8);
  static const Color _orange = Color(0xFFFF7043);

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
      duration: const Duration(seconds: 4),
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
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutCubic,
      ),
    );

    _logoScaleAnimation = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _introController,
        curve: Curves.easeOutBack,
      ),
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

    await _buttonPressController.reverse();
    await _buttonPressController.forward();

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
                child: _buildGlowSphere(_cyan.withOpacity(0.10), 420),
              ),
            ),
            Positioned(
              bottom: -180,
              left: -150,
              child: Transform.rotate(
                angle: -angle * 0.8,
                child: _buildGlowSphere(_cyan.withOpacity(0.08), 500),
              ),
            ),
            Positioned(
              top: 220,
              left: -90,
              child: Transform.rotate(
                angle: angle * 0.55,
                child: _buildGlowSphere(_pink.withOpacity(0.045), 260),
              ),
            ),
            Positioned(
              bottom: 180,
              right: -80,
              child: Transform.rotate(
                angle: -angle * 0.45,
                child: _buildGlowSphere(_orange.withOpacity(0.05), 240),
              ),
            ),
            Container(
              color: Colors.black.withOpacity(0.10),
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
            child: ScaleTransition(
              scale: _logoScaleAnimation,
              child: child,
            ),
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
                    color: _cyan.withOpacity(0.05),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _buildOrbitDot(const Offset(-30, -30), _pink, 12),
                  _buildOrbitDot(const Offset(30, -30), _cyan, 12),
                  _buildOrbitDot(const Offset(-30, 30), _cyan, 12),
                  _buildOrbitDot(const Offset(30, 30), _orange, 12),
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: _cyan.withOpacity(0.25),
                          blurRadius: 18,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ],
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
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: child,
          ),
        );
      },
      child: Column(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: _checking
                ? const SizedBox(
                    key: ValueKey('loading'),
                    height: 60,
                    width: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white24,
                    ),
                  )
                : ScaleTransition(
                    key: const ValueKey('button'),
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
                'AUTHENTIC CONNECTION',
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
        style: ElevatedButton.styleFrom(
          backgroundColor: _orange,
          foregroundColor: Colors.white,
          elevation: 0,
          disabledBackgroundColor: _orange.withOpacity(0.85),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(40),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
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
                      fontWeight: FontWeight.w900,
                      letterSpacing: 3,
                      fontSize: 15,
                    ),
                  ),
                  SizedBox(width: 10),
                  Icon(Icons.arrow_forward_rounded, size: 20),
                ],
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

  Widget _buildOrbitDot(Offset offset, Color color, double size) {
    return Transform.translate(
      offset: offset,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.38),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTinyDot() {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(
        color: _cyan,
        shape: BoxShape.circle,
      ),
    );
  }
}