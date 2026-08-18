import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_invite_page.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_repository.dart';

class RegisterSetPasswordPage extends StatefulWidget {
  final String email;
  final String otpProof;
  final bool isVenueSignup;
  final bool isInviteSignup;

  const RegisterSetPasswordPage({
    super.key,
    required this.email,
    required this.otpProof,
    this.isVenueSignup = false,
    this.isInviteSignup = false,
  });

  @override
  State<RegisterSetPasswordPage> createState() =>
      _RegisterSetPasswordPageState();
}

class _RegisterSetPasswordPageState extends State<RegisterSetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool marketingEmailOptIn = false;
  bool _legalConsent = false;
  bool _loadingLegalVersions = true;
  String? _termsVersionId;
  String? _privacyVersionId;
  String? _legalVersionsError;
  String? _legalConsentError;
  bool _loading = false;
  String? _error;

  static const _darkBg = Color(0xFF06091A);
  static const _sheetBg = Color(0xFF0B1322);
  static const _teal = Color(0xFF00D4C8);
  static const _darkTextMuted = Color(0xFFB1BBD4);
  static const _darkTextSoft = Color(0xFF8FA2C4);

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(_onFormChanged);
    _confirmCtrl.addListener(_onFormChanged);
    _loadLegalVersions();
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _passwordCtrl.removeListener(_onFormChanged);
    _confirmCtrl.removeListener(_onFormChanged);
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  // ── Password rules ──────────────────────────────────────────────────────────
  bool get _hasLength => _passwordCtrl.text.length >= 8;
  bool get _hasNumber => _passwordCtrl.text.contains(RegExp(r'[0-9]'));
  bool get _hasSpecial =>
      _passwordCtrl.text.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>_\-]'));

  int get _strengthLevel =>
      [_hasLength, _hasNumber, _hasSpecial].where((v) => v).length;

  String get _strengthLabel {
    switch (_strengthLevel) {
      case 0:
        return '';
      case 1:
        return 'Weak';
      case 2:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  Color get _strengthColor {
    switch (_strengthLevel) {
      case 1:
        return const Color(0xFFE05040);
      case 2:
        return const Color(0xFFF0A030);
      default:
        return _teal;
    }
  }

  // ── Computed ────────────────────────────────────────────────────────────────
  bool get _isPasswordReady =>
      _passwordCtrl.text.trim().length >= 8 &&
      _confirmCtrl.text.trim().isNotEmpty &&
      _confirmCtrl.text == _passwordCtrl.text;

  bool get _canSubmit =>
      !_loading &&
      !_loadingLegalVersions &&
      _legalVersionsError == null &&
      _legalConsent &&
      _isPasswordReady;

  // ── Network ─────────────────────────────────────────────────────────────────
  Future<void> _loadLegalVersions() async {
    setState(() {
      _loadingLegalVersions = true;
      _legalVersionsError = null;
    });
    try {
      final versions = await AuthRepository().getActiveLegalVersions();
      if (!mounted) return;
      setState(() {
        _termsVersionId = versions.termsVersionId;
        _privacyVersionId = versions.privacyVersionId;
        _loadingLegalVersions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLegalVersions = false;
        _legalVersionsError =
            'Policies could not be loaded. Check /legal/active-versions response shape and try again.';
      });
    }
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_legalConsent) {
      setState(() {
        _legalConsentError =
            'You must agree to Terms of Service and Privacy Policy.';
      });
      return;
    }
    if (_termsVersionId == null || _privacyVersionId == null) {
      setState(() {
        _legalVersionsError = 'Policies could not be loaded. Please try again.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _legalConsentError = null;
    });
    try {
      await AuthRepository().registerAndAutoLogin(
        widget.email,
        _passwordCtrl.text,
        widget.otpProof,
        marketingEmailOptIn: marketingEmailOptIn,
        consentGiven: true,
        termsVersionId: _termsVersionId!,
        privacyVersionId: _privacyVersionId!,
        consentSource: 'MOBILE',
      );

      // Check for a pending venue invite claimed with this email before any onboarding
      final pendingInvite = await VenueInviteRepository().getPendingInvite();
      if (!mounted) return;
      if (pendingInvite != null) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(
            builder: (_) => VenueInvitePage(token: pendingInvite.token),
          ),
          (route) => false,
        );
        return;
      }

      // Invite-only signup: if no pending invite found, show error — do NOT fall through to onboarding
      if (widget.isInviteSignup) {
        setState(
          () => _error =
              'No pending invite was found for this email. Please check that you entered the same email used on the invite link page.',
        );
        return;
      }

      if (widget.isVenueSignup) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const VenueContextOnboardingPage()),
        );
      } else {
        await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
        if (!mounted) return;
        // Hesap oluşturuldu ve giriş yapıldı; bayat email/OTP sayfalarına geri
        // dönülüp continue ile username'e tekrar düşülmesin diye tüm auth
        // stack'ini temizleyerek username'i kök yapıyoruz.
        Navigator.of(context).pushNamedAndRemoveUntil(
          AuthRoutes.onboardingUsername,
          (route) => false,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
        final code = e.data['errorCode']?.toString();
        if (code == 'EMAIL_ALREADY_IN_USE' || code == 'AUTH_EMAIL_IN_USE') {
          final isLoggedIn = await AuthRepository().restoreSession();
          if (!mounted) return;
          if (isLoggedIn) {
            final pendingInvite = await VenueInviteRepository()
                .getPendingInvite();
            if (!mounted) return;
            if (pendingInvite != null) {
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (_) => VenueInvitePage(token: pendingInvite.token),
                ),
                (route) => false,
              );
              return;
            }
            if (widget.isInviteSignup) {
              setState(
                () => _error =
                    'No pending invite was found for this email. Please check that you entered the same email used on the invite link page.',
              );
              return;
            }
            if (widget.isVenueSignup) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const VenueContextOnboardingPage(),
                ),
              );
            } else {
              Navigator.of(context).pushNamedAndRemoveUntil(
                AuthRoutes.onboardingUsername,
                (route) => false,
              );
            }
            return;
          }
        }
      }
      setState(() => _error = _friendlySignupError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlySignupError(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      final code = error.data['errorCode']?.toString();
      final message = _extractBackendMessage(error.data);
      if (code == 'EMAIL_ALREADY_IN_USE' || code == 'AUTH_EMAIL_IN_USE') {
        return 'An account with this email already exists. Please sign in instead.';
      }
      if (code == 'WEAK_PASSWORD') {
        return 'Your password is too weak. Please choose a stronger password.';
      }
      if (status == 429) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      if (status >= 500) {
        return 'We are unable to create your account right now. Please try again shortly.';
      }
      if (code == 'LEGAL_CONSENT_REQUIRED') {
        return 'You must accept Terms and Privacy to create an account.';
      }
      if (code == 'LEGAL_VERSION_INVALID') {
        return 'Legal policy version is invalid. Please refresh and try again.';
      }
      if (code == 'LEGAL_VERSION_INACTIVE') {
        return 'Legal policies were updated. Please review and try again.';
      }
      if (code == 'LEGAL_VERSION_TYPE_MISMATCH') {
        return 'Legal policy mismatch detected. Please refresh and try again.';
      }
      if (code == 'LEGAL_CONSENT_SOURCE_INVALID') {
        return 'Invalid consent source. Please update the app and try again.';
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
    return 'We could not create your account. Please try again.';
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
    return ForceDark(child: Builder(builder: _buildBody));
  }

  Widget _buildBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final pw = _passwordCtrl.text;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: isDark ? _darkBg : Colors.white,
        body: Stack(
          children: [
            // Ambient glow — blue top
            if (isDark) ...[
              Positioned(
                top: -70,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    width: 300,
                    height: 260,
                    decoration: const BoxDecoration(
                      gradient: RadialGradient(
                        center: Alignment(0, -0.4),
                        radius: 1.0,
                        colors: [Color(0x243B6DEA), Colors.transparent],
                      ),
                    ),
                  ),
                ),
              ),
              // Ambient glow — teal bottom-right
              Positioned(
                bottom: 100,
                right: -40,
                child: Container(
                  width: 180,
                  height: 180,
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      colors: [Color(0x1200D4C8), Colors.transparent],
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
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Eyebrow(isDark: isDark),
                        const SizedBox(height: 13),
                        _Headline(isDark: isDark),
                        const SizedBox(height: 10),
                        // Email chip
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0x1F3B6DEA)
                                : const Color(0xFFEEF4FF),
                            border: Border.all(
                              color: isDark
                                  ? const Color(0x383B6DEA)
                                  : const Color(0xFFBFD4FF),
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.mail_outline_rounded,
                                size: 12,
                                color: isDark
                                    ? const Color(0xFF7AAAFF)
                                    : AppColors.blueLight,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF7AAAFF)
                                      : AppColors.blueLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Sheet
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? _sheetBg : Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        border: isDark
                            ? const Border(
                                top: BorderSide(color: Color(0xFF162040)),
                              )
                            : const Border(
                                top: BorderSide(color: Color(0xFFE8EEF8)),
                              ),
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
                                  width: 32,
                                  height: 4,
                                  margin: const EdgeInsets.only(bottom: 20),
                                  decoration: BoxDecoration(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),

                              // Password field
                              _FieldLabel(label: 'PASSWORD', isDark: isDark),
                              const SizedBox(height: 7),
                              _PasswordField(
                                controller: _passwordCtrl,
                                obscure: _obscurePassword,
                                hint: 'Create a password',
                                isDark: isDark,
                                onToggle: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                                validator: (v) {
                                  if ((v ?? '').isEmpty) {
                                    return 'Please enter a password.';
                                  }
                                  if (v!.length < 8) {
                                    return 'Password must be at least 8 characters.';
                                  }
                                  return null;
                                },
                              ),

                              // Strength bars
                              if (pw.isNotEmpty) ...[
                                const SizedBox(height: 10),
                                _StrengthBars(
                                  level: _strengthLevel,
                                  label: _strengthLabel,
                                  color: _strengthColor,
                                  isDark: isDark,
                                ),
                              ],

                              const SizedBox(height: 10),

                              // Rules
                              _RulesBox(
                                hasLength: _hasLength,
                                hasNumber: _hasNumber,
                                hasSpecial: _hasSpecial,
                                isDark: isDark,
                              ),

                              const SizedBox(height: 4),

                              // Confirm password field
                              _FieldLabel(
                                label: 'CONFIRM PASSWORD',
                                isDark: isDark,
                              ),
                              const SizedBox(height: 7),
                              _PasswordField(
                                controller: _confirmCtrl,
                                obscure: _obscureConfirm,
                                hint: 'Repeat your password',
                                isDark: isDark,
                                onToggle: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                                validator: (v) {
                                  if ((v ?? '').isEmpty) {
                                    return 'Please confirm your password.';
                                  }
                                  if (v != _passwordCtrl.text) {
                                    return 'Passwords do not match.';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 16),

                              // Checkboxes
                              _CheckRow(
                                checked: marketingEmailOptIn,
                                isDark: isDark,
                                onTap: () => setState(
                                  () => marketingEmailOptIn =
                                      !marketingEmailOptIn,
                                ),
                                child: Text(
                                  'Send me occasional emails about my account and special offers',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    height: 1.5,
                                    color: isDark
                                        ? _darkTextMuted
                                        : Colors.black54,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              _CheckRow(
                                checked: _legalConsent,
                                isDark: isDark,
                                onTap: _loadingLegalVersions
                                    ? null
                                    : () => setState(() {
                                        _legalConsent = !_legalConsent;
                                        _legalConsentError = null;
                                      }),
                                child: Text.rich(
                                  TextSpan(
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      height: 1.5,
                                      color: isDark
                                          ? _darkTextMuted
                                          : Colors.black54,
                                    ),
                                    children: [
                                      const TextSpan(text: 'I agree to the '),
                                      WidgetSpan(
                                        child: GestureDetector(
                                          onTap: () => _openPolicy('/terms'),
                                          child: Text(
                                            'Terms of Service',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark
                                                  ? AppColors.blueDark
                                                  : AppColors.blueLight,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const TextSpan(text: ' and '),
                                      WidgetSpan(
                                        child: GestureDetector(
                                          onTap: () => _openPolicy('/privacy'),
                                          child: Text(
                                            'Privacy Policy',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: isDark
                                                  ? AppColors.blueDark
                                                  : AppColors.blueLight,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              if (_loadingLegalVersions)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: LinearProgressIndicator(
                                    color: AppColors.blue,
                                    backgroundColor: Color(0xFF0F1C35),
                                  ),
                                ),
                              if (_legalVersionsError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _legalVersionsError!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFEF4444),
                                          ),
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: _loadLegalVersions,
                                        child: const Text(
                                          'Retry',
                                          style: TextStyle(
                                            color: AppColors.blue,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              if (_legalConsentError != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _legalConsentError!,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ),
                              if (_error != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _error!,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 16),

                              // Create Account button
                              PrimaryButton(
                                label: 'Create Account',
                                onPressed: _canSubmit ? _register : null,
                                loading: _loading,
                                trailingArrow: true,
                              ),

                              const SizedBox(height: 14),

                              // Security note
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 13,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0x1200D4C8)
                                      : const Color(0xFFEEFBF9),
                                  border: Border.all(
                                    color: isDark
                                        ? const Color(0x2400D4C8)
                                        : const Color(0xFFB0E8E4),
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.shield_outlined,
                                      size: 15,
                                      color: _teal,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text.rich(
                                        TextSpan(
                                          style: TextStyle(
                                            fontSize: 11,
                                            height: 1.45,
                                            color: isDark
                                                ? const Color(0xFF9ADDD8)
                                                : Colors.black45,
                                          ),
                                          children: const [
                                            TextSpan(text: 'Your password is '),
                                            TextSpan(
                                              text: 'end-to-end encrypted',
                                              style: TextStyle(
                                                color: _teal,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            TextSpan(
                                              text:
                                                  ' and never stored in plain text.',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
        width: 38,
        height: 38,
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
    // step 1=done (teal), step 2=done (teal), step 3=active (blue)
    const states = ['done', 'done', 'active'];
    return Row(
      children: List.generate(3, (i) {
        final state = states[i];
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
          child: Container(
            width: state == 'active' ? 20 : 20,
            height: 4,
            decoration: BoxDecoration(
              color: state == 'done' ? const Color(0xFF00D4C8) : AppColors.blue,
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
          width: 18,
          height: 2,
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'STEP 3 OF 3',
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
      fontSize: 30,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.7,
      height: 1.12,
      color: isDark ? Colors.white : const Color(0xFF111827),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Almost there.', style: baseStyle),
        Text('Set your', style: baseStyle),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: AppColors.gradientDark,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text('password.', style: baseStyle),
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String label;
  final bool isDark;
  const _FieldLabel({required this.label, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: isDark
            ? _RegisterSetPasswordPageState._darkTextSoft
            : Colors.black45,
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final String hint;
  final bool isDark;
  final VoidCallback onToggle;
  final FormFieldValidator<String> validator;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.hint,
    required this.isDark,
    required this.onToggle,
    required this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      style: TextStyle(
        fontSize: 14,
        color: isDark ? const Color(0xFFEEF2FF) : const Color(0xFF111827),
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? const Color(0xFF6F84A8) : Colors.black38,
        ),
        prefixIcon: Icon(
          Icons.lock_outline_rounded,
          size: 18,
          color: isDark ? const Color(0xFF6F84A8) : Colors.black45,
        ),
        suffixIcon: IconButton(
          onPressed: onToggle,
          icon: Icon(
            obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            size: 18,
            color: isDark ? const Color(0xFF6F84A8) : Colors.black45,
          ),
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
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
      ),
      validator: validator,
    );
  }
}

class _StrengthBars extends StatelessWidget {
  final int level;
  final String label;
  final Color color;
  final bool isDark;
  const _StrengthBars({
    required this.level,
    required this.label,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(3, (i) {
            final filled = i < level;
            return Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.only(right: i == 2 ? 0 : 5),
                decoration: BoxDecoration(
                  color: filled
                      ? color
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.07)
                            : Colors.black.withValues(alpha: 0.07)),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Password strength',
              style: TextStyle(
                fontSize: 10.5,
                color: isDark
                    ? _RegisterSetPasswordPageState._darkTextSoft
                    : Colors.black45,
              ),
            ),
            if (label.isNotEmpty)
              Text(
                label,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RulesBox extends StatelessWidget {
  final bool hasLength;
  final bool hasNumber;
  final bool hasSpecial;
  final bool isDark;
  const _RulesBox({
    required this.hasLength,
    required this.hasNumber,
    required this.hasSpecial,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0D1A30) : const Color(0xFFF8FAFF),
        border: Border.all(
          color: isDark ? const Color(0xFF162040) : const Color(0xFFD4E0FF),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          _Rule(label: 'At least 8 characters', ok: hasLength, isDark: isDark),
          const SizedBox(height: 6),
          _Rule(label: 'Contains a number', ok: hasNumber, isDark: isDark),
          const SizedBox(height: 6),
          _Rule(
            label: 'Contains a special character',
            ok: hasSpecial,
            isDark: isDark,
          ),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  final String label;
  final bool ok;
  final bool isDark;
  const _Rule({required this.label, required this.ok, required this.isDark});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF00D4C8);
    return Row(
      children: [
        Icon(
          ok ? Icons.check_circle_outline_rounded : Icons.circle_outlined,
          size: 13,
          color: ok
              ? teal
              : (isDark
                    ? _RegisterSetPasswordPageState._darkTextSoft
                    : Colors.black38),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: ok
                ? teal
                : (isDark
                      ? _RegisterSetPasswordPageState._darkTextMuted
                      : Colors.black54),
          ),
        ),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool checked;
  final bool isDark;
  final VoidCallback? onTap;
  final Widget child;
  const _CheckRow({
    required this.checked,
    required this.isDark,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 18,
            height: 18,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: checked
                  ? const Color(0xFF1E4FC7)
                  : (isDark
                        ? const Color(0xFF0F1C35)
                        : const Color(0xFFF0F5FF)),
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: checked
                    ? AppColors.blue
                    : (isDark
                          ? const Color(0xFF1E3A60)
                          : const Color(0xFFD4E0FF)),
                width: 1.5,
              ),
            ),
            child: checked
                ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(child: child),
        ],
      ),
    );
  }
}
