import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/ui/account_exists_sheet.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_invite_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/apple_sign_in_cancellation.dart';
import '../data/auth_repository.dart';
import 'auth_routes.dart';
import 'dart:io' show Platform;

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.authRepository});
  final AuthRepository? authRepository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  late final _authRepository = widget.authRepository ?? AuthRepository();

  bool _loading = false;
  String? _loginMethod;
  bool _obscure = true;
  String? _error;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _surface => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _textPrimary => _isDark ? Colors.white : AppColors.lightTextPrimary;
  Color get _linkColor => _isDark ? _blueBright : AppColors.blueLight;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magentaDark;
  static const _brand = AppColors.brand;
  Color get _muted =>
      _isDark ? const Color(0xFFA6B3D2) : AppColors.lightTextSecondary;
  Color get _mutedDim =>
      _isDark ? const Color(0xFF7F91B2) : AppColors.lightTextSecondary;

  bool _isConsentRequiredError(ApiException error) {
    final code = error.data['errorCode']?.toString().toUpperCase();
    final message = _extractBackendMessage(error.data).toLowerCase();
    return code == 'CONSENT_REQUIRED_FOR_SOCIAL_LOGIN' ||
        code == 'LEGAL_CONSENT_REQUIRED' ||
        message.contains('consent is required for first-time social login');
  }

  bool _isAppUpdateRequiredError(Object error) {
    return error is ApiException &&
        error.statusCode == 426 &&
        error.data['errorCode'] == 'APP_UPDATE_REQUIRED';
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.siteBaseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await showPremiumErrorDialog(
        context,
        message: 'Unable to open policy link.',
      );
    }
  }

  Future<bool?> _showGoogleConsentSheet() {
    bool consent = false;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final surface = isDark ? const Color(0xFF121A2B) : Colors.white;
        final titleColor = isDark ? Colors.white : AppColors.lightTextPrimary;
        final bodyColor = isDark
            ? const Color(0xFFB4C2D8)
            : AppColors.lightTextSecondary;
        final linkColor = isDark ? AppColors.blueDark : AppColors.blue;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final linkStyle = TextStyle(
              color: linkColor,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: linkColor,
            );
            return Container(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Grab handle
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: bodyColor.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // ── Gradient ikon tile'ı
                      Center(
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [AppColors.blue, AppColors.magenta],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.magenta.withValues(
                                  alpha: 0.32,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Colors.white,
                            size: 30,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // ── Başlık
                      Text(
                        'One quick step',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: titleColor,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Please review and accept to continue with Google.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: bodyColor,
                          fontSize: 14.5,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Onay kutusu satırı (tıklanabilir kart)
                      InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setSheetState(() => consent = !consent),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.black.withValues(alpha: 0.03),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: consent
                                  ? AppColors.blue.withValues(alpha: 0.55)
                                  : (isDark
                                        ? Colors.white.withValues(alpha: 0.12)
                                        : Colors.black.withValues(alpha: 0.10)),
                              width: consent ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Özel checkbox
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(7),
                                  gradient: consent
                                      ? const LinearGradient(
                                          colors: [
                                            AppColors.blue,
                                            AppColors.magenta,
                                          ],
                                        )
                                      : null,
                                  color: consent ? null : Colors.transparent,
                                  border: Border.all(
                                    color: consent
                                        ? Colors.transparent
                                        : bodyColor.withValues(alpha: 0.5),
                                    width: 1.5,
                                  ),
                                ),
                                child: consent
                                    ? const Icon(
                                        Icons.check_rounded,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      color: bodyColor,
                                      fontSize: 13.5,
                                      height: 1.45,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    children: [
                                      const TextSpan(text: 'I agree to the '),
                                      TextSpan(
                                        text: 'Terms of Service',
                                        style: linkStyle,
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () => _openPolicy('/terms'),
                                      ),
                                      const TextSpan(text: ' and '),
                                      TextSpan(
                                        text: 'Privacy Policy',
                                        style: linkStyle,
                                        recognizer: TapGestureRecognizer()
                                          ..onTap = () =>
                                              _openPolicy('/privacy'),
                                      ),
                                      const TextSpan(text: '.'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ── Continue (standart mavi, sadece onaylıysa aktif)
                      Opacity(
                        opacity: consent ? 1 : 0.45,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: AppColors.blue,
                            boxShadow: consent
                                ? [
                                    BoxShadow(
                                      color: AppColors.blue.withValues(
                                        alpha: 0.30,
                                      ),
                                      blurRadius: 18,
                                      offset: const Offset(0, 8),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: consent
                                  ? () => Navigator.of(sheetContext).pop(true)
                                  : null,
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 15),
                                child: Text(
                                  'Continue',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _loginWithGoogleWithConsentFlow() async {
    final authRepository = _authRepository;
    try {
      return await authRepository.loginWithGoogle();
    } on ApiException catch (e) {
      if (!_isConsentRequiredError(e)) rethrow;
      final versions = await authRepository.getActiveLegalVersions();
      if (!mounted) return false;
      final consent = await _showGoogleConsentSheet();
      if (consent != true) return false;
      return authRepository.loginWithGoogle(
        consentGiven: true,
        termsVersionId: versions.termsVersionId,
        privacyVersionId: versions.privacyVersionId,
        consentSource: 'MOBILE',
        reusePendingToken: true,
      );
    }
  }

  Future<bool> _loginWithAppleWithConsentFlow() async {
    final authRepository = _authRepository;
    try {
      return await authRepository.loginWithApple();
    } on ApiException catch (e) {
      if (!_isConsentRequiredError(e)) rethrow;
      final versions = await authRepository.getActiveLegalVersions();
      if (!mounted) return false;
      final consent = await _showGoogleConsentSheet();
      if (consent != true) return false;
      return authRepository.loginWithApple(
        consentGiven: true,
        termsVersionId: versions.termsVersionId,
        privacyVersionId: versions.privacyVersionId,
        consentSource: 'MOBILE',
        reusePendingCredential: true,
      );
    }
  }

  /// E-posta zaten kayıtlıysa tutarlı "Sign In" sheet'ini, aksi halde genel
  /// hata diyaloğunu gösterir.
  Future<void> _showLoginError(BuildContext ctx, Object error) async {
    if (isAppleSignInCancellation(error)) return;
    // ApiClient already replaces the current route with the mandatory update
    // screen. Do not show a second, misleading login error on top of it.
    if (_isAppUpdateRequiredError(error)) return;
    if (isEmailAlreadyInUseError(error)) {
      await showAccountExistsSheet(ctx);
      return;
    }
    if (!ctx.mounted) return;
    await showPremiumErrorDialog(ctx, message: _friendlyLoginError(error));
  }

  String _friendlyLoginError(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      final code = error.data['errorCode']?.toString();
      final message = _extractBackendMessage(error.data);

      if (code == 'ACCOUNT_BANNED') {
        return message.isNotEmpty
            ? message
            : 'Your account has been suspended. Please contact support if you believe this is a mistake.';
      }
      if (code == 'INVALID_CREDENTIALS' || code == 'AUTH_INVALID_CREDENTIALS') {
        return 'The email or password you entered is incorrect.';
      }
      if (code == 'EMAIL_NOT_VERIFIED') {
        return 'Please verify your email address before signing in.';
      }
      if (status == 429) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      if (status >= 500) {
        return 'We are unable to sign you in right now. Please try again shortly.';
      }
      if (message.isNotEmpty) {
        return message;
      }
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout')) {
      return 'The request timed out. Please check your connection and try again.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'We could not sign you in. Please try again.';
  }

  String _extractBackendMessage(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      final text = first?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _handleSocialLoginOnly(Map<String, dynamic> data) {
    final providers = List<String>.from(data['providers'] ?? []);

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This account uses social login',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              if (providers.contains('google'))
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _loginSocial(apple: false);
                  },
                  child: const Text('Continue with Google'),
                ),

              if (providers.contains('apple') && Platform.isIOS)
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _loginSocial(apple: true);
                  },
                  child: const Text('Continue with Apple'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _loginSocial({required bool apple}) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _loginMethod = apple ? 'apple' : 'google';
      _error = null;
    });
    try {
      final success = apple
          ? await _loginWithAppleWithConsentFlow()
          : await _loginWithGoogleWithConsentFlow();
      if (!mounted || !success) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      if (!mounted) return;
      await _showLoginError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _login() async {
    if (_loading) return;
    setState(() {
      _error = null;
      _loading = true;
      _loginMethod = 'password';
    });

    try {
      final success = await _authRepository.login(
        _emailCtrl.text.trim().toLowerCase(),
        _passCtrl.text,
      );
      if (!mounted || !success) return;

      final pendingInvite = await VenueInviteRepository().getPendingInvite();
      if (!mounted) return;
      if (pendingInvite != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => VenueInvitePage(token: pendingInvite.token),
          ),
          (route) => false,
        );
        return;
      }

      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      if (!mounted) return;
      if (_isAppUpdateRequiredError(e)) return;
      if (e is ApiException) {
        final code = e.data['errorCode'];

        if (code == 'SOCIAL_LOGIN_ONLY') {
          setState(() => _loading = false);
          _handleSocialLoginOnly(e.data);
          return;
        }
      }
      setState(() => _error = _friendlyLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_loading,
      child: AbsorbPointer(
        absorbing: _loading,
        child: Scaffold(
          backgroundColor: _bg,
          body: Stack(
            children: [
              Positioned(
                top: -120,
                right: -90,
                child: _glow(320, 320, _blue.withValues(alpha: 0.12)),
              ),
              Positioned(
                bottom: -140,
                left: -120,
                child: _glow(360, 360, _brand.withValues(alpha: 0.10)),
              ),
              Positioned(
                top: 250,
                left: -100,
                child: _glow(220, 220, _magenta.withValues(alpha: 0.055)),
              ),
              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
                      decoration: BoxDecoration(
                        color: _surface.withValues(alpha: _isDark ? 0.78 : 1),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: _isDark
                              ? Colors.white.withValues(alpha: 0.08)
                              : const Color(0xFFD9E5F4),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: _isDark ? 0.30 : 0.06,
                            ),
                            blurRadius: 32,
                            offset: const Offset(0, 18),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Center(
                              child: SizedBox(
                                width: 58,
                                height: 58,
                                child: Image.asset(
                                  'assets/images/kmstrylogo.png',
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'Welcome',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 31,
                                height: 1.05,
                                letterSpacing: -0.5,
                                fontWeight: FontWeight.w900,
                                color: _textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Sign in to catch the vibe around you.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13.5,
                                height: 1.35,
                                fontWeight: FontWeight.w600,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(height: 24),
                            TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.text,
                              autocorrect: false,
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: _inputDecoration(
                                icon: Icons.person_outline_rounded,
                                hint: 'Email or username',
                              ),
                              validator: (v) {
                                final x = (v ?? '').trim();
                                if (x.isEmpty) {
                                  return 'Please enter your email or username.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 13),
                            TextFormField(
                              controller: _passCtrl,
                              obscureText: _obscure,
                              style: TextStyle(
                                color: _textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                              decoration: _inputDecoration(
                                icon: Icons.lock_outline_rounded,
                                hint: 'Password',
                                suffix: IconButton(
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_off_rounded
                                        : Icons.visibility_rounded,
                                    color: _muted,
                                  ),
                                ),
                              ),
                              validator: (v) {
                                if ((v ?? '').isEmpty) {
                                  return 'Please enter your password.';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 14),
                            if (_error != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(
                                    alpha: 0.10,
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.redAccent.withValues(
                                      alpha: 0.20,
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: _isDark
                                        ? const Color(0xFFFF8A8A)
                                        : const Color(0xFFB91C1C),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 14),
                            _buildLoginButton(),
                            const SizedBox(height: 8),
                            TextButton(
                              onPressed: () {
                                Navigator.pushNamed(
                                  context,
                                  AuthRoutes.forgotPassword,
                                );
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: _linkColor,
                              ),
                              child: const Text(
                                'Forgot Password?',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(child: _divider()),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: Text(
                                    'Or sign in with',
                                    style: TextStyle(
                                      color: _mutedDim,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Expanded(child: _divider()),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                _SocialCircle(
                                  label: 'G',
                                  loading: _loading && _loginMethod == 'google',
                                  onTap: () => _loginSocial(apple: false),
                                ),
                                if (Platform.isIOS) ...[
                                  const SizedBox(width: 14),
                                  _SocialCircle(
                                    label: '',
                                    loading:
                                        _loading && _loginMethod == 'apple',
                                    onTap: () => _loginSocial(apple: true),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 22),
                            Wrap(
                              alignment: WrapAlignment.center,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  "Don’t have an account? ",
                                  style: TextStyle(
                                    color: _muted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                TextButton(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      AuthRoutes.contextChoice,
                                    );
                                  },
                                  style: TextButton.styleFrom(
                                    foregroundColor: _linkColor,
                                    padding: EdgeInsets.zero,
                                    minimumSize: const Size(0, 34),
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text(
                                    'Sign up →',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required IconData icon,
    required String hint,
    Widget? suffix,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(
        color: _isDark
            ? Colors.white.withValues(alpha: 0.08)
            : const Color(0xFFD9E5F4),
      ),
    );
    return InputDecoration(
      prefixIcon: Icon(
        icon,
        color: _isDark
            ? Colors.white.withValues(alpha: 0.88)
            : AppColors.blueLight,
      ),
      suffixIcon: suffix,
      hintText: hint,
      hintStyle: TextStyle(color: _mutedDim, fontWeight: FontWeight.w600),
      filled: true,
      fillColor: _isDark
          ? Colors.white.withValues(alpha: 0.035)
          : const Color(0xFFF3F6FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: _linkColor, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFFF6B6B), width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFFFF8A8A), width: 1.2),
      ),
    );
  }

  Widget _buildLoginButton() {
    return PrimaryButton(
      label: 'Log in',
      loading: _loading && _loginMethod == 'password',
      onPressed: () {
        if (_formKey.currentState!.validate()) {
          _login();
        }
      },
    );
  }

  Widget _divider() {
    final color = _isDark ? Colors.white : AppColors.lightTextPrimary;
    return Container(
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.12),
            color.withValues(alpha: 0),
          ],
        ),
      ),
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

class _SocialCircle extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool loading;

  const _SocialCircle({
    required this.label,
    required this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.white : AppColors.lightTextPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.045)
              : const Color(0xFFF3F6FA),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : const Color(0xFFD9E5F4),
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.blue.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: loading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foreground,
                ),
              )
            : Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: foreground,
                ),
              ),
      ),
    );
  }
}
