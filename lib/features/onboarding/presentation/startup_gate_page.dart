import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/storage/secure_storage.dart';
import 'package:kmstry_frontend/core/network/api_client.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
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
  late final Animation<double> _buttonScaleAnimation;

  bool _checking = true;
  bool _navigating = false;

  static const Color _bgColor = AppColors.darkBg;
  static const Color _blue = AppColors.blue;
  static const Color _blueBright = AppColors.blueDark;
  static const Color _magenta = AppColors.magentaDark;
  static const Color _teal = AppColors.tealDark;
  static const Color _brand = AppColors.brand;
  static const Color _muted = Color(0xFFA6B3D2);

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
    return Column(
      children: [
        // Logo — native splash ile BİREBİR aynı konumda kalır (opacity 0'dan
        // gelmez); yalnızca etrafındaki parıltı/kutu fade-in ile belirir. Bu,
        // native splash → bu ekran geçişini kusursuz (zıplamasız) yapar.
        AnimatedBuilder(
          animation: Listenable.merge([_introController, _pulseController]),
          builder: (context, child) {
            final fade = _fadeAnimation.value;
            final shimmer = ((_pulseController.value - 0.98) / (1.03 - 0.98))
                .clamp(0.0, 1.0);
            final borderTarget = Color.lerp(
              Colors.white.withValues(alpha: 0.12),
              _blueBright.withValues(alpha: 0.38),
              shimmer,
            )!;
            return Transform.scale(
              scale: _pulseController.value,
              child: Container(
                width: 166,
                height: 166,
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
                    color: Color.lerp(Colors.transparent, borderTarget, fade)!,
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
                child: child,
              ),
            );
          },
          child: const Padding(
            padding: EdgeInsets.all(6),
            child: Image(
              image: AssetImage('assets/images/kmstrylogo.png'),
              fit: BoxFit.contain,
              alignment: Alignment.center,
            ),
          ),
        ),
        const SizedBox(height: 40),
        // KMSTRY + tagline — aşağıdan yükselerek belirir.
        AnimatedBuilder(
          animation: _introController,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, _slideAnimation.value),
              child: FadeTransition(opacity: _fadeAnimation, child: child),
            );
          },
          child: Column(
            children: [
              const Text(
                'KMSTRY',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 52,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 7,
                  height: 1,
                  shadows: [
                    Shadow(
                      color: Color(0x661A9FE8),
                      blurRadius: 22,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'REAL PLACES. REAL FACES.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _muted.withValues(alpha: 0.76),
                  fontSize: 12,
                  letterSpacing: 2.8,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ],
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
                  color: _muted.withValues(alpha: 0.85),
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

  Widget _buildTinyDot() {
    return Container(
      width: 4,
      height: 4,
      decoration: const BoxDecoration(color: _teal, shape: BoxShape.circle),
    );
  }
}
