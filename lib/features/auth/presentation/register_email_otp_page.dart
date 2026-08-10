import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';

import '../data/auth_repository.dart';

class RegisterEmailOtpPage extends StatefulWidget {
  final String email;
  /// Signup ekranında OTP zaten istendiyse yanıtı buraya geçilir.
  final Map<String, dynamic>? initialOtpResponse;

  const RegisterEmailOtpPage({
    super.key,
    required this.email,
    this.initialOtpResponse,
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
  /// Shown below the Continue button after a successful send (replaces SnackBar).
  bool _codeSentNotice = false;
  /// Test OTP from the server response (only shown when present).
  String? _testOtpHint;
  int _secondsLeft = 0;
  Timer? _timer;

  /// Reads OTP fields from the response for dev/test (`otp`, `code`, nested `data`, etc.).
  String? _parseTestOtpFromResponse(Map<String, dynamic> response) {
    const keys = ['otp', 'code', 'verificationCode', 'verification_code'];
    for (final k in keys) {
      final v = response[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    final data = response['data'];
    if (data is Map) {
      final m = Map<String, dynamic>.from(data);
      for (final k in keys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _digitCtrls = List.generate(6, (_) => TextEditingController());
    _digitFocusNodes = List.generate(6, (_) => FocusNode());
    final initial = widget.initialOtpResponse;
    if (initial != null) {
      _codeSentNotice = true;
      _testOtpHint = _parseTestOtpFromResponse(initial);
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

  void _syncOtpFromDigits() {
    _otpCtrl.text = _digitCtrls.map((c) => c.text).join();
  }

  void _focusFirstEmptyDigit() {
    for (var i = 0; i < _digitCtrls.length; i++) {
      if (_digitCtrls[i].text.isEmpty) {
        _digitFocusNodes[i].requestFocus();
        return;
      }
    }
    _digitFocusNodes.last.requestFocus();
  }

  void _handleDigitChanged(int index, String value) {
    final onlyDigits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyDigits.isEmpty) {
      _digitCtrls[index].clear();
      _syncOtpFromDigits();
      setState(() {});
      return;
    }

    // Paste handling: distribute multiple digits across the 6 boxes.
    if (onlyDigits.length > 1) {
      var cursor = index;
      for (var i = 0; i < onlyDigits.length; i++) {
        final ch = onlyDigits[i];
        if (cursor >= _digitCtrls.length) break;
        _digitCtrls[cursor].text = ch;
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
    if (raw.contains('timeout')) {
      return 'The request timed out. Please check your connection and try again.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
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
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
      _codeSentNotice = false;
      _testOtpHint = null;
    });
    try {
      final response = await AuthRepository().requestRegisterOtp(widget.email);
      if (!mounted) return;
      setState(() {
        _codeSentNotice = true;
        _testOtpHint = _parseTestOtpFromResponse(response);
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
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => RegisterSetPasswordPage(
            email: widget.email,
            otpProof: proof,
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
    final canResend = _secondsLeft == 0 && !_sending;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Verify Email')),
      body: SafeArea(
        child: GestureDetector(
          onTap: _focusFirstEmptyDigit,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                  Text(
                    'Step 2 of 3',
                    style: TextStyle(
                      color: colors.onSurface.withValues(alpha: 0.72),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Enter verification code',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We sent a verification code to ${widget.email}.',
                    style: TextStyle(
                      fontSize: 15,
                      color: colors.onSurface.withValues(alpha: 0.82),
                    ),
                  ),
                  const SizedBox(height: 18),

                  Row(
                    children: List.generate(6, (index) {
                      final hasValue = _digitCtrls[index].text.isNotEmpty;
                      final isActive = _digitFocusNodes[index].hasFocus;
                      return Expanded(
                        child: Container(
                          height: 56,
                          margin: EdgeInsets.only(right: index == 5 ? 0 : 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.surface.withValues(alpha: isDark ? 0.92 : 0.95),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: hasValue
                                  ? colors.primary.withValues(alpha: 0.85)
                                  : (isActive
                                      ? colors.primary.withValues(alpha: 0.65)
                                      : colors.outline.withValues(alpha: isDark ? 0.26 : 0.36)),
                              width: hasValue || isActive ? 1.4 : 1,
                            ),
                          ),
                          child: TextField(
                            controller: _digitCtrls[index],
                            focusNode: _digitFocusNodes[index],
                            keyboardType: TextInputType.number,
                            textInputAction: index == 5
                                ? TextInputAction.done
                                : TextInputAction.next,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colors.onSurface,
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
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
                            ),
                            onChanged: (v) => _handleDigitChanged(index, v),
                            onSubmitted: (_) {
                              if (index == 5 && !_verifying) {
                                _verifyOtp();
                              }
                            },
                          ),
                        ),
                      );
                    }),
                  ),

                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!, style: TextStyle(color: colors.error)),
                  ],
                  const SizedBox(height: 18),
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _verifying ? null : _verifyOtp,
                      child: _verifying
                          ? CircularProgressIndicator(color: colors.onPrimary)
                          : const Text('Continue'),
                    ),
                  ),
                  if (_codeSentNotice && _testOtpHint != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      'For testing, enter this OTP: $_testOtpHint',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: canResend ? _sendOtp : null,
                    child: Text(
                      canResend
                          ? 'Resend code'
                          : 'Resend available in ${_secondsLeft}s',
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
    );
  }
}
