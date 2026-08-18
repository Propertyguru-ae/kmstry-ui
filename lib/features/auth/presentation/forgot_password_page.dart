import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _requestSent = false;
  String _sentToEmail = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.login,
      (route) => false,
    );
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _requestSent = false;
    });

    try {
      await AuthRepository().forgotPassword(email);
    } catch (_) {
      // Enumeration güvenliği: hata olsa da aynı onayı göster.
    } finally {
      if (mounted) {
        setState(() {
          _sentToEmail = email;
          _requestSent = true;
          _loading = false;
        });
      }
    }
  }

  // ── Marka renkleri (logo paleti — her iki temada aynı) ───────────────────
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magenta;
  static const _orange = AppColors.orange;
  static const _purple = AppColors.brandLight;
  static const _teal = AppColors.teal;
  static const _muted = Color(0xFFA6B3D2);

  // ── Tema-duyarlı yüzey/metin renkleri ────────────────────────────────────
  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _sheet => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _sheetBorder =>
      _isDark ? const Color(0xFF172445) : const Color(0xFFD9E5F4);
  Color get _fieldFill =>
      _isDark ? const Color(0xFF0F1C35) : const Color(0xFFF2F7FF);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFEEF2FF) : AppColors.lightTextPrimary;
  Color get _textSecondary => _isDark ? _muted : AppColors.lightTextSecondary;
  Color get _hint => _isDark ? const Color(0xFF33486A) : const Color(0xFF95A8C2);
  Color get _handle => _isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);
  Color get _iconBtnBg => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : AppColors.lightTextPrimary.withValues(alpha: 0.05);
  Color get _iconBtnBorder => _isDark
      ? Colors.white.withValues(alpha: 0.09)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    return ForceDark(child: Builder(builder: _buildBody));
  }

  Widget _buildBody(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: _glow(320, 280, _blue.withValues(alpha: 0.14)),
              ),
            ),
            Positioned(
              bottom: 40,
              right: -60,
              child: _glow(220, 220, _magenta.withValues(alpha: 0.10)),
            ),
            Positioned(
              top: 200,
              left: -70,
              child: _glow(190, 190, _purple.withValues(alpha: 0.12)),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Topbar ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _circleIconButton(
                      () => Navigator.of(context).maybePop(),
                    ),
                  ),
                  // ── Hero ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 2,
                              decoration: BoxDecoration(
                                color: _orange,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'RESET PASSWORD',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: _orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          _requestSent ? 'Check your' : 'Forgot your',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_orange, _magenta],
                          ).createShader(bounds),
                          child: Text(
                            _requestSent ? 'inbox.' : 'password?',
                            style: const TextStyle(
                              fontSize: 30,
                              height: 1.12,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          _requestSent
                              ? 'If an account exists, a reset link is on its way.'
                              : 'Enter your email and we\'ll send you a link to reset your password.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Sheet ──────────────────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _sheet,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        border: Border(top: BorderSide(color: _sheetBorder)),
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 8,
                          bottom: bottomInset + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 34,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 22),
                                decoration: BoxDecoration(
                                  color: _handle,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            if (_requestSent)
                              _buildSentState()
                            else
                              _buildRequestForm(),
                          ],
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

  Widget _buildRequestForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel(Icons.alternate_email_rounded, 'EMAIL'),
        const SizedBox(height: 8),
        TextField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          onSubmitted: (_) => _send(),
          cursorColor: _blue,
          style: TextStyle(color: _textPrimary, fontSize: 15),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: _fieldFill,
            hintText: 'you@example.com',
            hintStyle: TextStyle(color: _hint),
            contentPadding: const EdgeInsets.symmetric(vertical: 15),
            prefixIcon: const Padding(
              padding: EdgeInsets.only(left: 15, right: 10),
              child: Icon(Icons.alternate_email_rounded, size: 20, color: _blue),
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 0,
              minHeight: 0,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _blue, width: 1.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: _blueBright, width: 1.6),
            ),
          ),
        ),
        const SizedBox(height: 20),
        PrimaryButton(
          label: 'Send reset link',
          loading: _loading,
          onPressed: _send,
          trailingArrow: true,
        ),
      ],
    );
  }

  Widget _buildSentState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: _teal.withValues(alpha: 0.14),
              shape: BoxShape.circle,
              border: Border.all(color: _teal.withValues(alpha: 0.30)),
            ),
            child: const Icon(
              Icons.mark_email_read_outlined,
              size: 30,
              color: _teal,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text.rich(
          TextSpan(
            style: TextStyle(fontSize: 14, height: 1.5, color: _textSecondary),
            children: [
              const TextSpan(text: 'We sent a reset link to '),
              TextSpan(
                text: _sentToEmail,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _textPrimary,
                ),
              ),
              const TextSpan(
                text: '. Check your inbox and follow the link to continue.',
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 22),
        PrimaryButton(
          label: 'Back to sign in',
          onPressed: _goToLogin,
        ),
        const SizedBox(height: 4),
        PrimaryButton.secondary(
          label: 'Use a different email',
          onPressed: () => setState(() => _requestSent = false),
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

  Widget _circleIconButton(VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _iconBtnBg,
          border: Border.all(color: _iconBtnBorder),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: _isDark ? const Color(0xFF7D88A8) : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: _blueBright),
        const SizedBox(width: 6),
        Text(
          text,
          style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: _blueBright,
          ),
        ),
      ],
    );
  }
}
