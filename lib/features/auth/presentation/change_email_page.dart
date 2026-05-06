import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';

enum _ChangeEmailStep { request, confirm }

class ChangeEmailPage extends StatefulWidget {
  const ChangeEmailPage({super.key});

  @override
  State<ChangeEmailPage> createState() => _ChangeEmailPageState();
}

class _ChangeEmailPageState extends State<ChangeEmailPage> {
  final _requestFormKey = GlobalKey<FormState>();
  final _confirmFormKey = GlobalKey<FormState>();
  final _currentPasswordCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _confirmEmailCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  bool _obscureCurrent = true;
  bool _loading = false;
  String? _error;
  String? _infoNote;
  String? _devOtp;
  _ChangeEmailStep _step = _ChangeEmailStep.request;

  void _showPremiumSuccess(String message) {
    final colors = Theme.of(context).colorScheme;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearMaterialBanners();
    messenger.showMaterialBanner(
      MaterialBanner(
        backgroundColor: colors.surface,
        elevation: 1,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        content: Row(
          children: [
            const Icon(
              Icons.check_circle_rounded,
              size: 18,
              color: Color(0xFF22C55E),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: colors.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        actions: const [SizedBox.shrink()],
      ),
    );
    Future.delayed(const Duration(seconds: 2), () {
      messenger.clearMaterialBanners();
    });
  }

  @override
  void dispose() {
    _currentPasswordCtrl.dispose();
    _newEmailCtrl.dispose();
    _confirmEmailCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
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

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      final code = error.data['errorCode']?.toString();
      final msg = _extractBackendMessage(error.data);
      if (code == 'INVALID_PASSWORD') return 'Current password is incorrect.';
      if (code == 'EMAIL_ALREADY_IN_USE') {
        return 'This email is already used by another account.';
      }
      if (code == 'INVALID_OR_EXPIRED_OTP') {
        return 'Verification code is invalid or expired.';
      }
      if (msg.isNotEmpty) return msg;
      if (status >= 500) return 'Something went wrong. Please try again.';
    }
    final raw = error.toString().toLowerCase();
    if (raw.contains('not signed in')) return 'Please sign in again.';
    if (raw.contains('timeout')) {
      return 'The request timed out. Please check your connection.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'No internet connection. Please check your network.';
    }
    return 'Something went wrong. Please try again.';
  }

  Future<void> _requestChange() async {
    setState(() {
      _error = null;
      _infoNote = null;
    });
    if (!(_requestFormKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final response = await AuthRepository().requestChangeEmail(
        newEmail: _newEmailCtrl.text.trim(),
        currentPassword: _currentPasswordCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _step = _ChangeEmailStep.confirm;
        _devOtp = response['otp']?.toString();
        _infoNote = 'Verification code sent to your new email.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmChange() async {
    setState(() => _error = null);
    if (!(_confirmFormKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      await AuthRepository().confirmChangeEmail(
        newEmail: _newEmailCtrl.text.trim(),
        otp: _otpCtrl.text.trim(),
      );
      if (!mounted) return;
      _showPremiumSuccess('Your email has been updated.');
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isConfirm = _step == _ChangeEmailStep.confirm;
    return Scaffold(
      appBar: AppBar(title: const Text('Change email')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isConfirm
                    ? 'Enter the verification code sent to your new email.'
                    : 'Enter your current password and your new email.',
                style: TextStyle(fontSize: 15, color: colors.onSurfaceVariant),
              ),
              const SizedBox(height: 20),
              if (!isConfirm)
                Form(
                  key: _requestFormKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _newEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'New email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final s = v?.trim() ?? '';
                          if (s.isEmpty) return 'Enter your new email.';
                          if (!s.contains('@') || !s.contains('.')) {
                            return 'Enter a valid email address.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _confirmEmailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if ((v?.trim() ?? '') != _newEmailCtrl.text.trim()) {
                            return 'Email addresses do not match.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _currentPasswordCtrl,
                        obscureText: _obscureCurrent,
                        autocorrect: false,
                        decoration: InputDecoration(
                          labelText: 'Current password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureCurrent
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                            onPressed: () => setState(
                              () => _obscureCurrent = !_obscureCurrent,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Enter your current password.';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                )
              else
                Form(
                  key: _confirmFormKey,
                  child: Column(
                    children: [
                      TextFormField(
                        initialValue: _newEmailCtrl.text.trim(),
                        enabled: false,
                        decoration: const InputDecoration(
                          labelText: 'New email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _otpCtrl,
                        keyboardType: TextInputType.number,
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Verification code',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          if ((v?.trim() ?? '').isEmpty) {
                            return 'Enter the verification code.';
                          }
                          return null;
                        },
                      ),
                      if (_devOtp != null && _devOtp!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Test code: $_devOtp',
                          style: TextStyle(
                            color: colors.onSurface.withValues(alpha: 0.65),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
              if (_infoNote != null) ...[
                const SizedBox(height: 12),
                Text(
                  _infoNote!,
                  style: TextStyle(
                    color: colors.onSurface.withValues(alpha: 0.8),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading
                      ? null
                      : (isConfirm ? _confirmChange : _requestChange),
                  child: _loading
                      ? CircularProgressIndicator(color: colors.onPrimary)
                      : Text(
                          isConfirm
                              ? 'Confirm email change'
                              : 'Send verification',
                        ),
                ),
              ),
              if (isConfirm) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _loading
                      ? null
                      : () {
                          setState(() {
                            _step = _ChangeEmailStep.request;
                            _otpCtrl.clear();
                            _error = null;
                            _infoNote = null;
                          });
                        },
                  child: const Text('Edit email'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
