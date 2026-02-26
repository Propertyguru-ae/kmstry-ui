import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_set_password_page.dart';

import '../data/auth_repository.dart';

class RegisterEmailOtpPage extends StatefulWidget {
  final String email;

  const RegisterEmailOtpPage({super.key, required this.email});

  @override
  State<RegisterEmailOtpPage> createState() => _RegisterEmailOtpPageState();
}

class _RegisterEmailOtpPageState extends State<RegisterEmailOtpPage> {
  final _otpCtrl = TextEditingController();
  bool _sending = false;
  bool _verifying = false;
  String? _error;
  int _secondsLeft = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
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
    });
    try {
      await AuthRepository().requestRegisterOtp(widget.email);
      if (!mounted) return;
      _startCooldown();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification code sent. Please check your email.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _verifyOtp() async {
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(title: const Text('Verify Email')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Step 2 of 3: Enter OTP',
                  style: TextStyle(color: colors.onSurface),
                ),
                const SizedBox(height: 10),
                Text(
                  'We sent a verification code to ${widget.email}.',
                  style: const TextStyle(fontSize: 15),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Verification code',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: TextStyle(color: colors.error)),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _verifying ? null : _verifyOtp,
                    child: _verifying
                        ? CircularProgressIndicator(color: colors.onPrimary)
                        : const Text('Continue'),
                  ),
                ),
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
        ),
      ),
    );
  }
}
