import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';

import '../data/auth_repository.dart';

class RegisterEmailOtpPage extends StatefulWidget {
  final String email;
  final Map<String, dynamic>? initialOtpResponse;
  final bool isVenueSignup;

  const RegisterEmailOtpPage({
    super.key,
    required this.email,
    this.initialOtpResponse,
    this.isVenueSignup = false,
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

  String? _testOtpHint;
  int _secondsLeft = 0;
  Timer? _timer;

  static const _darkBg   = Color(0xFF06091A);
  static const _sheetBg  = Color(0xFF0B1322);
  static const _blue     = AppColors.blueDark;
  static const _blueDark = AppColors.blue;
  static const _pink    = Color(0xFF00D4C8);

  String? _parseTestOtpFromResponse(Map<String, dynamic> response) {
    const keys = ['otp', 'code', 'verificationCode', 'verification_code'];
    for (final k in keys) {
      final v = response[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    final data = response['data'];
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      for (final k in keys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _digitCtrls      = List.generate(6, (_) => TextEditingController());
    _digitFocusNodes = List.generate(6, (_) => FocusNode());
    final initial = widget.initialOtpResponse;
    if (initial != null) {
      
      _testOtpHint    = _parseTestOtpFromResponse(initial);
      _startCooldown();
    } else {
      _sendOtp();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    for (final c in _digitCtrls) c.dispose();
    for (final f in _digitFocusNodes) f.dispose();
    super.dispose();
  }

  void _syncOtpFromDigits() =>
      _otpCtrl.text = _digitCtrls.map((c) => c.text).join();


  void _handleDigitChanged(int index, String value) {
    final onlyDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) {
      _digitCtrls[index].clear();
      _syncOtpFromDigits();
      setState(() {});
      return;
    }
    if (onlyDigits.length > 1) {
      var cursor = index;
      for (var i = 0; i < onlyDigits.length; i++) {
        if (cursor >= _digitCtrls.length) break;
        _digitCtrls[cursor].text = onlyDigits[i];
        cursor++;
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
    _digitCtrls[index].text = onlyDigits;
    _digitCtrls[index].selection = TextSelection.fromPosition(
      TextPosition(offset: _digitCtrls[index].text.length),
    );
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
    if (raw.contains('timeout')) return 'The request timed out. Please try again.';
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
      if (!mounted) { t.cancel(); return; }
      if (_secondsLeft <= 1) {
        t.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft -= 1);
      }
    });
  }

  Future<void> _sendOtp() async {
    if (_sending) return;
    setState(() { _sending = true; _error = null; _testOtpHint = null; });
    try {
      final response = await AuthRepository().requestRegisterOtp(widget.email);
      if (!mounted) return;
      setState(() {
        
        _testOtpHint    = _parseTestOtpFromResponse(response);
      });
      _startCooldown();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
    _syncOtpFromDigits();
    final otp = _otpCtrl.text.trim();
    if (otp.length < 4) {
      setState(() => _error = 'Please enter a valid verification code.');
      return;
    }
    setState(() { _verifying = true; _error = null; });
    try {
      final proof = await AuthRepository().verifyRegisterOtp(
        email: widget.email,
        otp: otp,
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RegisterSetPasswordPage(
            email: widget.email,
            otpProof: proof,
            isVenueSignup: widget.isVenueSignup,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final canResend  = _secondsLeft == 0 && !_sending;

    return Scaffold(
      backgroundColor: isDark ? _darkBg : Colors.white,
      body: Stack(
        children: [
          // Ambient glow — blue top
          if (isDark) ...[
            Positioned(
              top: -70, left: 0, right: 0,
              child: Center(
                child: Container(
                  width: 300, height: 260,
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
              bottom: 120, left: -40,
              child: Container(
                width: 180, height: 180,
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
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                              Icon(Icons.mail_outline_rounded,
                                  size: 13,
                                  color: isDark ? _blue : AppColors.blueLight),
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
                          'We sent a 6-digit code to this address. It expires in 45 seconds.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.55,
                            color: isDark ? const Color(0xFFB1B4BB) : Colors.black45,
                          ),
                        ),
                        // Test OTP hint
                        if (_testOtpHint != null) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0x1F00D4C8)
                                  : const Color(0xFFEEFBF4),
                              border: Border.all(
                                color: isDark
                                    ? const Color(0x3300D4C8)
                                    : const Color(0xFFB0E8CC),
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.bug_report_outlined,
                                    size: 14, color: _pink),
                                const SizedBox(width: 6),
                                Text(
                                  'Test OTP: $_testOtpHint',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: _pink,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Sheet
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? _sheetBg : Colors.white,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
                        border: isDark
                            ? const Border(
                                top: BorderSide(color: Color(0xFF162040)),
                              )
                            : const Border(
                                top: BorderSide(color: Color(0xFFE8EEF8)),
                              ),
                      ),
                      child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.only(
                          left: 20, right: 20, top: 8,
                          bottom: MediaQuery.of(context).viewInsets.bottom + 28,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Handle
                            Center(
                              child: Container(
                                width: 32, height: 4,
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
                              'VERIFICATION CODE',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: isDark
                                    ? const Color(0xFF5B6F8D)
                                    : Colors.black38,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // OTP boxes
                            Row(
                              children: List.generate(6, (i) {
                                final hasValue = _digitCtrls[i].text.isNotEmpty;
                                final isActive  = _digitFocusNodes[i].hasFocus;
                                return Expanded(
                                  child: Container(
                                    height: 52,
                                    margin: EdgeInsets.only(right: i == 5 ? 0 : 8),
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
                                        style: TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w700,
                                          height: 1.0,
                                          color: isDark
                                              ? AppColors.blueDark
                                              : AppColors.blueLight,
                                        ),
                                        autofillHints: const [AutofillHints.oneTimeCode],
                                        inputFormatters: [
                                          FilteringTextInputFormatter.digitsOnly,
                                          LengthLimitingTextInputFormatter(1),
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
                                        onChanged: (v) => _handleDigitChanged(i, v),
                                        onSubmitted: (_) {
                                          if (i == 5 && !_verifying) _verifyOtp();
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
                                    fontSize: 12.5, color: Color(0xFFEF4444)),
                                textAlign: TextAlign.center,
                              ),
                            ],

                            const SizedBox(height: 10),
                            Text(
                              'Tap a box or use your keyboard',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark
                                    ? const Color.fromARGB(255, 68, 87, 110)
                                    : Colors.black26,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 18),

                            // Timer row
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 36, height: 36,
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
                                                  ? const Color(0xFF3A5070)
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
                                                ? const Color(0xFF3A5070)
                                                : Colors.black45,
                                          ),
                                          children: [
                                            const TextSpan(text: 'Resend code in '),
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
                            _VerifyButton(
                              verifying: _verifying,
                              isDark: isDark,
                              onTap: _verifyOtp,
                            ),

                            const SizedBox(height: 16),

                            // Security note
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
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
                                  const Icon(Icons.shield_outlined,
                                      size: 15, color: _pink),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text.rich(
                                      TextSpan(
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.45,
                                          color: isDark
                                              ? const Color(0xFF3A6050)
                                              : Colors.black45,
                                        ),
                                        children: const [
                                          TextSpan(
                                              text:
                                                  "This code confirms it's really you. "),
                                          TextSpan(
                                            text: 'Never share it',
                                            style: TextStyle(
                                                color: _pink,
                                                fontWeight: FontWeight.w600),
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

                            // Wrong email
                            Text.rich(
                              TextSpan(
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark
                                      ? const Color(0xFF5B6F8D)
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
          width: 18, height: 2,
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

class _VerifyButton extends StatelessWidget {
  final bool verifying;
  final bool isDark;
  final VoidCallback onTap;
  const _VerifyButton({required this.verifying, required this.isDark, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: verifying ? null : onTap,
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
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                ),
              ),
            ),
            Center(
              child: verifying
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Verify & Continue',
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
