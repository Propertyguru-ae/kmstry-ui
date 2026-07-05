import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_email_otp_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';

class SignupPage extends StatefulWidget {
  final bool isVenueSignup;
  final bool isInviteSignup;
  const SignupPage({super.key, this.isVenueSignup = false, this.isInviteSignup = false});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _emailCtrl   = TextEditingController();
  final _formKey     = GlobalKey<FormState>();
  bool _loading      = false;
  bool _googleLoading = false;
  String? _error;
  static const _darkBg    = Color(0xFF06091A);
  static const _sheetBg   = Color(0xFF0B1322);
  static const _blueAccent = AppColors.blueDark;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    setState(() { _loading = true; _error = null; });
    try {
      // Invite signup: verify the entered email matches a claimed invite before sending OTP
      if (widget.isInviteSignup) {
        final found = await VenueInviteRepository().checkInviteEmail(email);
        if (!found) {
          setState(() {
            _loading = false;
            _error = 'No invite was found for this email. Please use the same email you entered on the invite link page.';
          });
          return;
        }
      }
      final response = await AuthRepository().requestRegisterOtp(email);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegisterEmailOtpPage(
            email: email,
            initialOtpResponse: response,
            isVenueSignup: widget.isVenueSignup,
            isInviteSignup: widget.isInviteSignup,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
        final code = e.data['errorCode']?.toString().toUpperCase();
        if (code == 'EMAIL_ALREADY_IN_USE' || code == 'USER_ALREADY_EXISTS') {
          final isLoggedIn = await AuthRepository().restoreSession();
          if (!mounted) return;
          if (isLoggedIn) {
            Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
            return;
          }
        }
      }
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loginWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      final success = await AuthRepository().loginWithGoogle();
      if (!mounted) return;
      if (success) {
        if (widget.isVenueSignup) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const VenueContextOnboardingPage()),
          );
        } else {
          Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Google sign-in failed. Please try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final message = _extractBackendMessage(error.data).toLowerCase();
      final code    = error.data['errorCode']?.toString().toUpperCase();
      if (code == 'EMAIL_ALREADY_IN_USE' || code == 'USER_ALREADY_EXISTS' ||
          message.contains('email already in use') || message.contains('already registered')) {
        return 'This email is already in use. Please sign in instead.';
      }
      if (message.isNotEmpty) return _extractBackendMessage(error.data);
    }
    return 'Unable to continue. Please try again.';
  }

  String _extractBackendMessage(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List && raw.isNotEmpty) {
      final text = raw.first?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Stack(
        children: [
          // Ambient glow — blue top
          if (isDark) ...[
            Positioned(
              top: -80, left: 0, right: 0,
              child: Center(
                child: Container(
                  width: 340, height: 300,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0, -0.35),
                      radius: 1.0,
                      colors: [Color(0x293B6DEA), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // Ambient glow — purple right
            Positioned(
              top: 80, right: -60,
              child: Container(
                width: 200, height: 200,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x128C46FF), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],

          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _CircleBackButton(isDark: isDark),
                      _ProgressDots(isDark: isDark),
                    ],
                  ),
                ),

                // Hero
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Eyebrow(isDark: isDark),
                      const SizedBox(height: 13),
                      _Headline(isDark: isDark),
                      const SizedBox(height: 6),
                      Text(
                        'Create your account in seconds.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: isDark ? const Color(0xFF4A6280) : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 18),
                      // Account badge
                      _AccountBadge(
                        isVenue: widget.isVenueSignup,
                        isInvite: widget.isInviteSignup,
                        isDark: isDark,
                        onChangeTap: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),

                // Sheet
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? _sheetBg : Colors.white,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(26)),
                      border: isDark
                          ? const Border(
                              top: BorderSide(color: Color(0xFF162040)))
                          : const Border(
                              top: BorderSide(color: Color(0xFFE8EEF8))),
                    ),
                    child: SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: EdgeInsets.only(
                        left: 20,
                        right: 20,
                        top: 8,
                        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Handle
                            Center(
                              child: Container(
                                width: 32, height: 4,
                                margin: const EdgeInsets.only(bottom: 20),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // Field label
                            Text(
                              'EMAIL ADDRESS',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: isDark
                                    ? const Color(0xFF5B6F8D)
                                    : Colors.black38,
                              ),
                            ),
                            const SizedBox(height: 7),

                            // Email field
                            _EmailField(
                              controller: _emailCtrl,
                              isDark: isDark,
                            ),

                            const SizedBox(height: 5),
                            Text(
                              "We'll send a verification code to this address.",
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color(0xFF5A6F8F)
                                    : Colors.black38,
                              ),
                            ),

                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFEF4444),
                                ),
                              ),
                            ],

                            const SizedBox(height: 14),

                            // Continue button
                            _ContinueButton(
                              loading: _loading,
                              isDark: isDark,
                              onTap: _continueToOtp,
                            ),

                            const SizedBox(height: 12),

                            // OR divider
                            Row(
                              children: [
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.07),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  child: Text(
                                    'or sign up with',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: isDark
                                          ? const Color(0xFF506884)
                                          : Colors.black38,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Container(
                                    height: 1,
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.07),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Social buttons
                            Row(
                              children: [
                                Expanded(
                                  child: _SocialButton(
                                    label: 'Google',
                                    customIcon: Text(
                                      'G',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: isDark
                                            ? const Color(0xFF7A90B0)
                                            : Colors.black54,
                                      ),
                                    ),
                                    isDark: isDark,
                                    loading: _googleLoading,
                                    onTap: _loginWithGoogle,
                                  ),
                                ),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: _SocialButton(
                                    label: 'Apple',
                                    customIcon: Icon(
                                      Icons.apple,
                                      size: 20,
                                      color: isDark
                                          ? const Color(0xFF7A90B0)
                                          : Colors.black54,
                                    ),
                                    isDark: isDark,
                                    loading: false,
                                    onTap: () {},
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 16),

                            // Terms
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 10.5,
                                  height: 1.6,
                                  color: isDark
                                      ? const Color(0xFF5B6F8D)
                                      : Colors.black38,
                                ),
                                children: [
                                  const TextSpan(
                                      text: 'By continuing you agree to our '),
                                  TextSpan(
                                    text: 'Terms',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF2E4D80)
                                          : _blueAccent,
                                    ),
                                  ),
                                  const TextSpan(text: ' and '),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: TextStyle(
                                      color: isDark
                                          ? const Color(0xFF2E4D80)
                                          : _blueAccent,
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),

                            const SizedBox(height: 16),

                            // Separator
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(colors: [
                                  Colors.transparent,
                                  isDark
                                      ? Colors.white.withValues(alpha: 0.04)
                                      : Colors.black.withValues(alpha: 0.07),
                                  Colors.transparent,
                                ]),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Sign in
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF2E4560)
                                      : Colors.black38,
                                ),
                                children: [
                                  const TextSpan(
                                      text: 'Already have an account? '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Text(
                                        'Sign in →',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppColors.blueDark
                                              : _blueAccent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _CircleBackButton extends StatelessWidget {
  final bool isDark;
  const _CircleBackButton({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Container(
        width: 38, height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.black.withValues(alpha: 0.05),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.1),
          ),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: isDark ? const Color(0xFF607090) : Colors.black54,
        ),
      ),
    );
  }
}

class _ProgressDots extends StatelessWidget {
  final bool isDark;
  const _ProgressDots({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(3, (i) {
        final active = i == 0;
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
          child: Container(
            width: active ? 20 : 14,
            height: 4,
            decoration: BoxDecoration(
              color: active
                  ? AppColors.blue
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.1)
                      : Colors.black.withValues(alpha: 0.12)),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  final bool isDark;
  const _Eyebrow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18, height: 2,
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'STEP 1 OF 3',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: AppColors.blue,
          ),
        ),
      ],
    );
  }
}

class _Headline extends StatelessWidget {
  final bool isDark;
  const _Headline({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final baseStyle = TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.8,
      height: 1.1,
      color: isDark ? Colors.white : const Color(0xFF111827),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Welcome.', style: baseStyle),
        Text("Let's set you", style: baseStyle),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: AppColors.gradientDark,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text('up right.', style: baseStyle),
        ),
      ],
    );
  }
}

class _AccountBadge extends StatelessWidget {
  final bool isVenue;
  final bool isInvite;
  final bool isDark;
  final VoidCallback onChangeTap;
  const _AccountBadge({
    required this.isVenue,
    required this.isDark,
    required this.onChangeTap,
    this.isInvite = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconBg    = isInvite ? const Color(0xFF0A3020) : isVenue ? const Color(0xFF3B1580) : const Color(0xFF1540A0);
    final iconColor = isInvite ? const Color(0xFF34D399) : isVenue ? const Color(0xFFC4A0FF) : const Color(0xFF90B8FF);
    final titleColor = isInvite ? const Color(0xFF34D399) : isVenue ? const Color(0xFFC4A0FF) : const Color(0xFFAAC4FF);
    final borderColor = isInvite
        ? (isDark ? const Color(0xFF0D4028) : const Color(0xFFB0E8D4))
        : isVenue
        ? (isDark ? const Color(0xFF3D2080) : const Color(0xFFD4B8FF))
        : (isDark ? const Color(0x401A9FE8) : const Color(0xFFBFD4FF));
    final bgColor = isInvite
        ? (isDark ? const Color(0x1A0A3020) : const Color(0xFFEEFBF6))
        : isVenue
        ? (isDark ? const Color(0x1A3B1580) : const Color(0xFFF5F0FF))
        : (isDark ? const Color(0x2E1540A0) : const Color(0xFFF0F5FF));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          // Icon
          Stack(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isInvite
                      ? Icons.link_rounded
                      : isVenue
                          ? Icons.store_mall_directory_outlined
                          : Icons.person_outline_rounded,
                  color: iconColor,
                  size: 20,
                ),
              ),
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isInvite ? 'Invite Sign-up' : isVenue ? 'Venue Account' : 'Personal Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isDark ? titleColor : AppColors.blueLight,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isInvite
                      ? 'You\'ll be taken to your invite after sign-up'
                      : isVenue
                          ? 'Manage your venue & grow your presence'
                          : 'Discover venues & share moments',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.4,
                    color: isDark ? const Color(0xFF3A5880) : Colors.black45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Change link
          GestureDetector(
            onTap: onChangeTap,
            child: Text(
              'Change →',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.blue : AppColors.blueLight,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;
  const _EmailField({required this.controller, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827),
      ),
      decoration: InputDecoration(
        hintText: 'your@email.com',
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF253A58) : Colors.black26,
        ),
        prefixIcon: Icon(
          Icons.mail_outline_rounded,
          size: 18,
          color: isDark ? const Color(0xFF2E4A6A) : Colors.black38,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF0F1C35) : const Color(0xFFF8FAFF),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF1A3060) : const Color(0xFFD4E0FF),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 15, vertical: 15),
      ),
      validator: (v) {
        final x = (v ?? '').trim();
        if (x.isEmpty) return 'Please enter your email address.';
        if (!x.contains('@')) return 'Please enter a valid email address.';
        return null;
      },
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final bool loading;
  final bool isDark;
  final VoidCallback onTap;
  const _ContinueButton(
      {required this.loading, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFF1E4FC7),
          borderRadius: BorderRadius.circular(14),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned(
              top: 0, left: 0, right: 0,
              child: Container(
                height: 26,
                decoration: const BoxDecoration(
                  color: Color(0x12FFFFFF),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(14)),
                ),
              ),
            ),
            Center(
              child: loading
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.2,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: Colors.white, size: 18),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final Widget customIcon;
  final bool isDark;
  final bool loading;
  final VoidCallback onTap;

  const _SocialButton({
    required this.label,
    required this.customIcon,
    required this.isDark,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F1C35) : const Color(0xFFF8FAFF),
          border: Border.all(
            color: isDark ? const Color(0xFF162040) : const Color(0xFFD4E0FF),
          ),
          borderRadius: BorderRadius.circular(13),
        ),
        child: loading
            ? const Center(
                child: SizedBox(
                  width: 18, height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.blueDark),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  customIcon,
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isDark
                          ? const Color(0xFF6A85A8)
                          : Colors.black54,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
