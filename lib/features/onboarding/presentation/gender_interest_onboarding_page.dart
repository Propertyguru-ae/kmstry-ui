import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

class GenderInterestOnboardingPage extends StatefulWidget {
  /// Opsiyonel — çok adımlı onboarding akışında bu son profil adımından sonra
  /// akışı bitirmek için çağrılır. Null ise klasik authGate yönlendirmesi.
  final VoidCallback? onContinue;

  const GenderInterestOnboardingPage({super.key, this.onContinue});

  @override
  State<GenderInterestOnboardingPage> createState() =>
      _GenderInterestOnboardingPageState();
}

class _GenderInterestOnboardingPageState
    extends State<GenderInterestOnboardingPage> {
  String? gender;
  String? interest;
  bool loading = false;

  bool get valid => gender != null && interest != null;

  static const _teal = AppColors.teal;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magenta;
  static const _orange = AppColors.orange;
  static const _purple = AppColors.brandLight;
  static const _muted = Color(0xFFA6B3D2);
  static const _mutedDim = Color(0xFF7F91B2);

  // ── Tema-duyarlı yüzey/metin renkleri ────────────────────────────────────
  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _sheet => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _sheetBorder =>
      _isDark ? const Color(0xFF172445) : const Color(0xFFD9E5F4);
  Color get _fieldBorderIdle =>
      _isDark ? const Color(0xFF1A3060) : const Color(0xFFD9E5F4);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFF4F6FF) : AppColors.lightTextPrimary;
  Color get _textSecondary => _isDark ? _muted : AppColors.lightTextSecondary;
  Color get _handle => _isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);
  Color get _iconBtnBg => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : AppColors.lightTextPrimary.withValues(alpha: 0.05);
  Color get _iconBtnBorder => _isDark
      ? Colors.white.withValues(alpha: 0.09)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);
  List<Color> get _tileInactiveGrad => _isDark
      ? const [Color(0xFF0F1C35), Color(0xFF13223D)]
      : const [Color(0xFFF2F7FF), Color(0xFFEAF1FB)];

  Future<void> submit() async {
    if (!valid) return;

    setState(() => loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({
        'gender': gender!,
        'interestedIn': interest!,
      });

      if (!mounted) return;
      if (widget.onContinue != null) {
        setState(() => loading = false);
        widget.onContinue!();
      } else {
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
      await showPremiumErrorDialog(context, message: 'Something went wrong');
    }
  }

  Widget tile(
    String value,
    String label,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    final active = selected == value;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => onTap(value)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: active
                ? [_blue.withValues(alpha: 0.22), _teal.withValues(alpha: 0.12)]
                : _tileInactiveGrad,
          ),
          border: Border.all(
            color: active ? _blueBright : _fieldBorderIdle,
            width: active ? 1.5 : 1.25,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: active
                  ? _blue.withValues(alpha: 0.18)
                  : Colors.black.withValues(alpha: 0.10),
              blurRadius: active ? 20 : 10,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: active ? _textPrimary : _textSecondary,
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: active
                  ? Container(
                      key: const ValueKey('selected'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: _teal.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _teal.withValues(alpha: 0.95),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: Color(0xFFF4F6FF),
                      ),
                    )
                  : Container(
                      key: const ValueKey('empty'),
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _mutedDim.withValues(alpha: 0.45),
                          width: 1,
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: Row(
                    children: [
                      if (Navigator.canPop(context))
                        _circleIconButton(() => Navigator.of(context).pop())
                      else
                        const SizedBox(width: 38),
                      const Spacer(),
                      const SizedBox(width: 38),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
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
                            'ABOUT YOU',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 2,
                              color: _orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Tell us',
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
                        child: const Text(
                          'who you are.',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This helps KMSTRY personalize who you discover and who discovers you.',
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
                        bottom: bottomInset + 18,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Container(
                              width: 34,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: _handle,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                          _fieldLabel(Icons.person_outline_rounded, 'GENDER'),
                          const SizedBox(height: 8),
                          tile('male', 'Male', gender, (v) => gender = v),
                          const SizedBox(height: 8),
                          tile('female', 'Female', gender, (v) => gender = v),
                          const SizedBox(height: 16),
                          _fieldLabel(
                            Icons.favorite_border_rounded,
                            'INTERESTED IN',
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Choose who you would like to connect with.',
                            style: TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                              color: _textSecondary,
                            ),
                          ),
                          const SizedBox(height: 8),
                          tile('men', 'Men', interest, (v) => interest = v),
                          const SizedBox(height: 8),
                          tile('women', 'Women', interest, (v) => interest = v),
                          const SizedBox(height: 8),
                          tile(
                            'everyone',
                            'Everyone',
                            interest,
                            (v) => interest = v,
                          ),
                          const SizedBox(height: 16),
                          PrimaryButton(
                            label: 'Continue',
                            onPressed: valid ? submit : null,
                            loading: loading,
                            trailingArrow: true,
                          ),
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
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: _blueBright,
          ),
        ),
      ],
    );
  }
}
