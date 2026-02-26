import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/register_email_otp_page.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

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
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RegisterEmailOtpPage(email: email)),
      );
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Unable to continue. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
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
                  color: colors.surface,
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
