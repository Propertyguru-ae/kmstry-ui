import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import '../data/auth_repository.dart';

class SignupPage extends StatefulWidget {
  const SignupPage({super.key});

  @override
  State<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends State<SignupPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  bool _obscure2 = true;
  bool _marketingOptIn = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _register1() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await AuthRepository().register(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;

      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Account created'),
          content: const Text(
            'Your account has been created successfully.\n\n'
            'We’ve sent a verification email to your inbox.\n'
            'You can continue using the app, but some features '
            'may be limited until your email is verified.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // dialog
                Navigator.pop(context); // signup -> login
              },
              child: const Text('Go to Login'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _register() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      final email = _emailCtrl.text.trim();
      final pass = _passCtrl.text;

      await AuthRepository().registerAndAutoLogin(email, pass);

      if (!mounted) return;

      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text(
                        'Create Account',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 18),

                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.mail_outline),
                          hintText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) {
                          final x = (v ?? '').trim();
                          if (x.isEmpty) return 'Email is required';
                          if (!x.contains('@')) return 'Invalid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _passCtrl,
                        obscureText: _obscure,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline),
                          hintText: 'Password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Password is required';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      TextFormField(
                        controller: _confirmCtrl,
                        obscureText: _obscure2,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.lock_outline),
                          hintText: 'Confirm password',
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure2 = !_obscure2),
                            icon: Icon(
                              _obscure2
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').isEmpty) return 'Confirm is required';
                          if (v != _passCtrl.text)
                            return 'Passwords do not match';
                          return null;
                        },
                      ),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Checkbox(
                            value: _marketingOptIn,
                            onChanged: (v) =>
                                setState(() => _marketingOptIn = v ?? false),
                          ),
                          const Expanded(
                            child: Text(
                              'Send me occasional emails regarding my account '
                              'subscription and special offers',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      if (_error != null)
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),

                      const SizedBox(height: 10),

                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _loading
                              ? null
                              : () {
                                  if (_formKey.currentState!.validate()) {
                                    _register();
                                  }
                                },
                          child: _loading
                              ? const CircularProgressIndicator()
                              : const Text('Create Account'),
                        ),
                      ),

                      const SizedBox(height: 18),
                      const Text('Continue with'),
                      const SizedBox(height: 12),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _SocialCircle(
                            label: 'G',
                            onTap: () async {
                              try {
                                final success = await AuthRepository()
                                    .loginWithGoogle();
                                if (!mounted) return;

                                if (success) {
                                  Navigator.pushReplacementNamed(
                                    context,
                                    AuthRoutes.authGate,
                                  );
                                }
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            },
                          ),

                          const SizedBox(width: 14),

                          _SocialCircle(
                            label: '',
                            onTap: () {
                              // Apple login → sonra
                            },
                          ),

                          const SizedBox(width: 14),

                          _SocialCircle(
                            label: 'f',
                            onTap: () {
                              // Facebook login → sonra
                            },
                          ),
                        ],
                      ),
                    ],
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

class _SocialCircle extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SocialCircle({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: const Color(0xFFF2F2F2),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
