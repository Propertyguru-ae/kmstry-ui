import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_email_otp_page.dart';

class SignupPage extends StatefulWidget {
  /// true ise kayit sonrasi venue claim akisina yonlendirilir.
  final bool isVenueSignup;

  const SignupPage({super.key, this.isVenueSignup = false});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _continueToOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailCtrl.text.trim();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await AuthRepository().requestRegisterOtp(email);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RegisterEmailOtpPage(
            email: email,
            initialOtpResponse: response,
            isVenueSignup: widget.isVenueSignup,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Hesap zaten olusturulmus, session varsa devam et
      if (e is ApiException) {
        final code = e.data['errorCode']?.toString().toUpperCase();
        if (code == 'EMAIL_ALREADY_IN_USE' || code == 'USER_ALREADY_EXISTS') {
          final isLoggedIn = await AuthRepository().restoreSession();
          if (!mounted) return;
          if (isLoggedIn) {
            Navigator.of(context).pushReplacementNamed(AuthRoutes.authGate);
            return;
          }
        }
      }
      setState(() => _error = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final message = _extractBackendMessage(error.data).toLowerCase();
      final code = error.data['errorCode']?.toString().toUpperCase();
      if (code == 'EMAIL_ALREADY_IN_USE' ||
          code == 'USER_ALREADY_EXISTS' ||
          message.contains('email already in use') ||
          message.contains('already registered')) {
        return 'This email is already in use. Please sign in instead.';
      }
      if (message.isNotEmpty) {
        return _extractBackendMessage(error.data);
      }
    }
    return 'Unable to continue. Please try again.';
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
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            const SizedBox(height: 80),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Create Account',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Step 1 of 3: Enter your email',
                          style: TextStyle(color: colors.onSurface),
                        ),
                        const SizedBox(height: 18),

                        TextFormField(
                          controller: _emailCtrl,
                          decoration: InputDecoration(
                            prefixIcon: Icon(
                              Icons.mail_outline,
                              color: colors.onSurface,
                            ),
                            hintText: 'Email',
                            border: const OutlineInputBorder(),
                          ),
                          validator: (v) {
                            final x = (v ?? '').trim();
                            if (x.isEmpty) {
                              return 'Please enter your email address.';
                            }
                            if (!x.contains('@')) {
                              return 'Please enter a valid email address.';
                            }
                            return null;
                          },
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 10),
                            child: Text(
                              _error!,
                              style: TextStyle(color: colors.error),
                            ),
                          ),

                        const SizedBox(height: 10),

                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _loading
                                ? null
                                : () {
                                    _continueToOtp();
                                  },
                            child: _loading
                                ? CircularProgressIndicator(
                                    color: colors.onPrimary,
                                  )
                                : const Text('Continue'),
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
    );
  }
}
