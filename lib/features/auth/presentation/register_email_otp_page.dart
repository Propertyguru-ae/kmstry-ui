import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/core/ui/force_dark.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';

import '../data/auth_repository.dart';

class RegisterEmailOtpPage extends StatefulWidget {
  final String email;
  final Map<String, dynamic>? initialOtpResponse;
  final bool isVenueSignup;
  final bool isInviteSignup;

  const RegisterEmailOtpPage({
    super.key,
    required this.email,
    this.initialOtpResponse,
    this.isVenueSignup = false,
    this.isInviteSignup = false,
  });

  @override
  State<RegisterEmailOtpPage> createState() => _RegisterEmailOtpPageState();
}

class _RegisterEmailOtpPageState extends State<RegisterEmailOtpPage> {
  final _otpCtrl = TextEditingController();
  late final List<TextEditingController> _digitCtrls;
  late final List<FocusNode> _digitFocusNodes;
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  String? _verifiedProof;

  int _secondsLeft = 0;
  Timer? _timer;

  static const _darkBg = Color(0xFF06091A);
  static const _sheetBg = Color(0xFF0B1322);
  static const _blue = AppColors.blueDark;
  static const _blueDark = AppColors.blue;
  static const _pink = Color(0xFF00D4C8);
  static const _darkTextMuted = Color(0xFFA6B3D2);
  static const _darkTextSoft = Color(0xFF8FA2C4);

  // Görünmez sentinel: her boş kutuda 1 karakter tutar ki mobil klavyede boş
  // kutuda basılan backspace de onChanged'i tetiklesin (önceki kutuya geç + sil).
  static const _zwsp = '\u200B';

  void _setBox(int i, String digit) {
    _digitCtrls[i].text = _zwsp + digit;
    _digitCtrls[i].selection = TextSelection.collapsed(
      offset: _digitCtrls[i].text.length,
    );
  }

  @override
  void initState() {
    super.initState();
    _digitCtrls = List.generate(6, (_) => TextEditingController(text: _zwsp));
    _digitFocusNodes = List.generate(6, (_) => FocusNode());
    final initial = widget.initialOtpResponse;
    if (initial != null) {
      _startCooldown();
    } else {
      _sendOtp();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    for (final c in _digitCtrls) {
      c.dispose();
    }
    for (final f in _digitFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _syncOtpFromDigits() => _otpCtrl.text = _digitCtrls
      .map((c) => c.text.replaceAll(_zwsp, ''))
      .join();

  void _handleDigitChanged(int index, String value) {
    final onlyDigits = value.replaceAll(RegExp(r'[^0-9]'), '');

    // Sentinel silindi → kutu zaten boştu; önceki kutuya geç ve onu temizle.
    if (value.isEmpty) {
      _setBox(index, '');
      if (index > 0) {
        _setBox(index - 1, '');
        _digitFocusNodes[index - 1].requestFocus();
      }
      _syncOtpFromDigits();
      setState(() {});
      return;
    }

    // Rakam yok (dolu kutuda backspace ile rakam silindi) → boş kal.
    if (onlyDigits.isEmpty) {
      _setBox(index, '');
      _syncOtpFromDigits();
      setState(() {});
      return;
    }

    // Yapıştırma / çoklu rakam → kutulara dağıt.
    if (onlyDigits.length > 1) {
      var cursor = index;
      for (
        var i = 0;
        i < onlyDigits.length && cursor < _digitCtrls.length;
        i++, cursor++
      ) {
        _setBox(cursor, onlyDigits[i]);
      }
      _syncOtpFromDigits();
      if (cursor < _digitFocusNodes.length) {
        _digitFocusNodes[cursor].requestFocus();
      } else {
        _digitFocusNodes.last.unfocus();
      }
      setState(() {});
      return;
    }

    // Tek rakam → yaz ve sonraki kutuya geç.
    _setBox(index, onlyDigits);
    _syncOtpFromDigits();
    if (index < _digitFocusNodes.length - 1) {
      _digitFocusNodes[index + 1].requestFocus();
    } else {
      _digitFocusNodes[index].unfocus();
    }
    setState(() {});
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final message = _extractBackendMessage(error.data);
      if (message.isNotEmpty) return message;
      if (error.statusCode >= 500) {
        return 'We are unable to verify your email right now. Please try again.';
      }
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout')) {
      return 'The request timed out. Please try again.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'No internet connection. Please try again.';
    }
    return 'Something went wrong. Please try again.';
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

  void _startCooldown([int seconds = 45]) {
    _timer?.cancel();
    setState(() => _secondsLeft = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    if (_verifiedProof != null) return;
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await AuthRepository().requestRegisterOtp(widget.email);
      if (!mounted) return;
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    if (_verifiedProof != null) {
      _openPasswordPage(_verifiedProof!);
      return;
    }

    _syncOtpFromDigits();
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) {
      setState(() => _error = 'Please enter a valid verification code.');
      return;
    }
    setState(() {
      _verifying = true;
      _error = null;
    });
    try {
      final proof = await AuthRepository().verifyRegisterOtp(
        email: widget.email,
        otp: otp,
      );
      if (!mounted) return;
      _verifiedProof = proof;
      _openPasswordPage(proof);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _openPasswordPage(String proof) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RegisterSetPasswordPage(
          isInviteSignup: widget.isInviteSignup,
          email: widget.email,
          otpProof: proof,
          isVenueSignup: widget.isVenueSignup,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ForceDark(child: Builder(builder: _buildBody));
  }

  Widget _buildBody(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isVerified = _verifiedProof != null;
    final canResend = !isVerified && _secondsLeft == 0 && !_sending;

    return Scaffold(
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
                      colors: [Color(0x263B6DEA), Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // Ambient glow — green bottom-left
            Positioned(
              bottom: 120,
              left: -40,
              child: Container(
                width: 180,
                height: 180,
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    colors: [Color(0x0F00D4C8), Colors.transparent],
                  ),
                ),
              ),
            ),
          ],

          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => FocusScope.of(context).unfocus(),
            child: SafeArea(
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
                    padding: const EdgeInsets.fromLTRB(24, 26, 24, 0),
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
                            horizontal: 12,
                            vertical: 6,
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
                                size: 13,
                                color: isDark ? _blue : AppColors.blueLight,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                widget.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? _blue : AppColors.blueLight,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isVerified
                              ? 'Your email is verified. Continue to create your password.'
                              : 'We sent a 6-digit code to this address. It expires in 10 minutes.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.55,
                            color: isDark ? _darkTextMuted : Colors.black45,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Handle
                            Center(
                              child: Container(
                                width: 32,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 22),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.08)
                                      : Colors.black.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),

                            // OTP label
                            Text(
                              isVerified
                                  ? 'EMAIL VERIFIED'
                                  : 'VERIFICATION CODE',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: isDark ? _darkTextSoft : Colors.black38,
                              ),
                            ),
                            const SizedBox(height: 12),

                            if (isVerified)
                              _VerifiedEmailCard(isDark: isDark)
                            else
                              Row(
                                children: List.generate(6, (i) {
                                  final hasValue = _digitCtrls[i].text
                                      .replaceAll(_zwsp, '')
                                      .isNotEmpty;
                                  final isActive = _digitFocusNodes[i].hasFocus;
                                  return Expanded(
                                    child: Container(
                                      height: 52,
                                      margin: EdgeInsets.only(
                                        right: i == 5 ? 0 : 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isDark
                                            ? (hasValue || isActive
                                                  ? const Color(0xFF0D1F45)
                                                  : const Color(0xFF0F1C35))
                                            : (hasValue || isActive
                                                  ? const Color(0xFFEEF4FF)
                                                  : const Color(0xFFF8FAFF)),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(
                                          color: hasValue
                                              ? _blueDark
                                              : isActive
                                              ? _blueDark
                                              : (isDark
                                                    ? const Color(0xFF1A3060)
                                                    : const Color(0xFFD4E0FF)),
                                          width: isActive ? 2.0 : 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: TextField(
                                          controller: _digitCtrls[i],
                                          focusNode: _digitFocusNodes[i],
                                          keyboardType: TextInputType.number,
                                          textInputAction: i == 5
                                              ? TextInputAction.done
                                              : TextInputAction.next,
                                          textAlign: TextAlign.center,
                                          enabled: !isVerified,
                                          readOnly: isVerified,
                                          style: TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                            height: 1.0,
                                            color: isDark
                                                ? AppColors.blueDark
                                                : AppColors.blueLight,
                                          ),
                                          autofillHints: const [
                                            AutofillHints.oneTimeCode,
                                          ],
                                          decoration: const InputDecoration(
                                            counterText: '',
                                            border: InputBorder.none,
                                            enabledBorder: InputBorder.none,
                                            focusedBorder: InputBorder.none,
                                            contentPadding: EdgeInsets.zero,
                                            isDense: true,
                                            isCollapsed: true,
                                            filled: false,
                                          ),
                                          onChanged: (v) =>
                                              _handleDigitChanged(i, v),
                                          onSubmitted: (_) {
                                            if (i == 5 && !_verifying) {
                                              _verifyOtp();
                                            }
                                          },
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),

                            if (_error != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Color(0xFFEF4444),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],

                            if (!isVerified) ...[
                              const SizedBox(height: 10),
                              Text(
                                'Tap a box or use your keyboard',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark
                                      ? _darkTextSoft
                                      : Colors.black45,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 18),

                            // Timer row
                            if (!isVerified)
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 36,
                                    height: 36,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: isDark
                                          ? const Color(0x1A3B6DEA)
                                          : const Color(0xFFEEF4FF),
                                      border: Border.all(
                                        color: isDark
                                            ? const Color(0x333B6DEA)
                                            : const Color(0xFFBFD4FF),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        canResend ? '—' : '${_secondsLeft}s',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? AppColors.blueDark
                                              : AppColors.blueLight,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  canResend
                                      ? GestureDetector(
                                          onTap: _sendOtp,
                                          child: Text.rich(
                                            TextSpan(
                                              style: TextStyle(
                                                fontSize: 12.5,
                                                color: isDark
                                                    ? _darkTextSoft
                                                    : Colors.black45,
                                              ),
                                              children: [
                                                TextSpan(
                                                  text: 'Resend code',
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? _blue
                                                        : AppColors.blueLight,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Text.rich(
                                          TextSpan(
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              color: isDark
                                                  ? _darkTextSoft
                                                  : Colors.black45,
                                            ),
                                            children: [
                                              const TextSpan(
                                                text: 'Resend code in ',
                                              ),
                                              TextSpan(
                                                text: '$_secondsLeft seconds',
                                                style: TextStyle(
                                                  color: isDark
                                                      ? _blue
                                                      : AppColors.blueLight,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ],
                              ),

                            const SizedBox(height: 18),

                            // Verify button
                            PrimaryButton(
                              label: isVerified
                                  ? 'Continue to Password'
                                  : 'Verify & Continue',
                              onPressed: _verifyOtp,
                              loading: _verifying,
                              trailingArrow: true,
                            ),

                            const SizedBox(height: 16),

                            // Security note
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0x1200D4C8)
                                    : const Color(0xFFEEFBF4),
                                border: Border.all(
                                  color: isDark
                                      ? const Color(0x2600D4C8)
                                      : const Color(0xFFB0E8CC),
                                ),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.shield_outlined,
                                    size: 15,
                                    color: _pink,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.45,
                                          color: isDark
                                              ? _darkTextMuted
                                              : Colors.black45,
                                        ),
                                        children: const [
                                          TextSpan(
                                            text:
                                                "This code confirms it's really you. ",
                                          ),
                                          TextSpan(
                                            text: 'Never share it',
                                            style: TextStyle(
                                              color: _pink,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          TextSpan(text: ' with anyone.'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 18),

                            // Separator
                            Container(
                              height: 1,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.transparent,
                                    isDark
                                        ? Colors.white.withValues(alpha: 0.04)
                                        : Colors.black.withValues(alpha: 0.07),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(height: 14),

                            // Wrong email
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? _darkTextSoft
                                      : Colors.black38,
                                ),
                                children: [
                                  const TextSpan(text: 'Wrong email address? '),
                                  WidgetSpan(
                                    child: GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Text(
                                        'Go back & change →',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: isDark
                                              ? AppColors.blueDark
                                              : AppColors.blueLight,
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────────

class _VerifiedEmailCard extends StatelessWidget {
  final bool isDark;

  const _VerifiedEmailCard({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0x141FD9A8) : const Color(0xFFEFFDF8),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0x381FD9A8) : const Color(0xFFB8F2DF),
          width: 1.4,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.teal.withValues(alpha: isDark ? 0.18 : 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 22,
              color: AppColors.tealDark,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Email verified',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Your code is confirmed. Next, create your password.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: isDark
                        ? const Color(0xFFA6B3D2)
                        : AppColors.lightTextSecondary,
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
    // step 1 = done (green), step 2 = active (blue), step 3 = off
    const states = ['done', 'active', 'off'];
    return Row(
      children: List.generate(3, (i) {
        final state = states[i];
        return Padding(
          padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
          child: Container(
            width: state == 'off' ? 14 : 20,
            height: 4,
            decoration: BoxDecoration(
              color: state == 'done'
                  ? const Color(0xFF00D4C8)
                  : state == 'active'
                  ? AppColors.blueDark
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
          width: 18,
          height: 2,
          decoration: BoxDecoration(
            color: AppColors.blueDark,
            borderRadius: BorderRadius.circular(1),
          ),
        ),
        const SizedBox(width: 7),
        const Text(
          'STEP 2 OF 3',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            color: AppColors.blueDark,
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
        Text('Check your', style: baseStyle),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: AppColors.gradientDark,
          ).createShader(bounds),
          blendMode: BlendMode.srcIn,
          child: Text('inbox.', style: baseStyle),
        ),
      ],
    );
  }
}
