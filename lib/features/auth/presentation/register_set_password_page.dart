import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/presentation/context_choice_page.dart';

import '../data/auth_repository.dart';

class RegisterSetPasswordPage extends StatefulWidget {
  final String email;
  final String otpProof;

  const RegisterSetPasswordPage({
    super.key,
    required this.email,
    required this.otpProof,
  });

  @override
  State<RegisterSetPasswordPage> createState() => _RegisterSetPasswordPageState();
}

class _RegisterSetPasswordPageState extends State<RegisterSetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _marketingOptIn = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
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
      if (message.isNotEmpty) return message;
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
      final first = raw.first;
      final text = first?.toString().trim() ?? '';
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await AuthRepository().registerAndAutoLogin(
        widget.email,
        _passwordCtrl.text,
        widget.otpProof,
      );

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ContextChoicePage()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = _friendlySignupError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Create Account'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Step 3 of 3: Set your password',
                      style: TextStyle(color: colors.onSurface),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      widget.email,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _passwordCtrl,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        hintText: 'Password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
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
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmCtrl,
                      obscureText: _obscureConfirm,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.lock_outline),
                        hintText: 'Confirm password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          onPressed: () => setState(
                            () => _obscureConfirm = !_obscureConfirm,
                          ),
                          icon: Icon(
                            _obscureConfirm
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                        ),
                      ),
                      validator: (v) {
                        if ((v ?? '').isEmpty) {
                          return 'Please confirm your password.';
                        }
                        if (v != _passwordCtrl.text) {
                          return 'Passwords do not match. Please try again.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _marketingOptIn,
                          onChanged: (v) => setState(
                            () => _marketingOptIn = v ?? false,
                          ),
                        ),
                        const Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: Text(
                              'Send me occasional emails regarding my account '
                              'subscription and special offers',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _error!,
                        style: TextStyle(color: colors.error),
                      ),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _loading ? null : _register,
                        child: _loading
                            ? CircularProgressIndicator(
                                color: colors.onPrimary,
                              )
                            : const Text('Create Account'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
