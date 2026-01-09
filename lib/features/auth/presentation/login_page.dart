import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import '../data/auth_repository.dart';
import 'auth_routes.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  void _handleSocialLoginOnly(Map<String, dynamic> data) {
    final providers = List<String>.from(data['providers'] ?? []);

    showModalBottomSheet(
      context: context,
      builder: (_) {
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This account uses social login',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              if (providers.contains('google'))
                ElevatedButton(
                  onPressed: () async {
                    final authRepository = AuthRepository();

                    final success = await authRepository.loginWithGoogle();
                    if (!context.mounted) return;

                    if (success) {
                      Navigator.pop(context);
                      Navigator.pushReplacementNamed(
                        context,
                        AuthRoutes.authGate,
                      );
                    }
                  },
                  child: const Text('Continue with Google'),
                ),

              if (providers.contains('apple'))
                ElevatedButton(
                  onPressed: () {},
                  child: const Text('Continue with Apple'),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _login() async {
    setState(() {
      _error = null;
      _loading = true;
    });

    try {
      await AuthRepository().login(_emailCtrl.text.trim(), _passCtrl.text);
      if (!mounted) return;

      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      if (e is ApiException) {
        final code = e.data['errorCode'];

        if (code == 'SOCIAL_LOGIN_ONLY') {
          setState(() => _loading = false);
          _handleSocialLoginOnly(e.data);
          return;
        }

        setState(() => _error = e.data['message']);
      } else {
        setState(() => _error = 'Unexpected error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomSheetRadius = BorderRadius.circular(24);

    return Scaffold(
      backgroundColor: const Color(0xFFF3F3F3),
      body: SafeArea(
        child: Stack(
          children: [
            // üst boş alan (gri arka plan)
            Positioned.fill(
              child: Column(
                children: [
                  const SizedBox(height: 140),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: bottomSheetRadius,
                      ),
                      padding: const EdgeInsets.all(24),
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 24),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 10),
                              const Text(
                                'Welcome to Kmstry',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Email
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
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

                              // Password
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
                                  if ((v ?? '').isEmpty)
                                    return 'Password is required';
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              if (_error != null)
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(color: Colors.red),
                                ),

                              const SizedBox(height: 10),

                              SizedBox(
                                height: 52,
                                child: ElevatedButton(
                                  onPressed: _loading
                                      ? null
                                      : () {
                                          if (_formKey.currentState!
                                              .validate()) {
                                            _login();
                                          }
                                        },
                                  child: _loading
                                      ? const CircularProgressIndicator()
                                      : const Text('Log in'),
                                ),
                              ),

                              TextButton(
                                onPressed: () {
                                  Navigator.pushNamed(
                                    context,
                                    AuthRoutes.forgotPassword,
                                  );
                                },
                                child: const Text('Forgot Password?'),
                              ),

                              const SizedBox(height: 16),
                              const Center(child: Text('Or')),
                              const SizedBox(height: 10),
                              const Center(child: Text('Sign in with')),
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
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(content: Text(e.toString())),
                                        );
                                      }
                                    },
                                  ),

                                  const SizedBox(width: 14),
                                  _SocialCircle(label: '', onTap: () {}),
                                  const SizedBox(width: 14),
                                  _SocialCircle(label: 'f', onTap: () {}),
                                ],
                              ),

                              const SizedBox(height: 24),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Text("Don’t have an account? "),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AuthRoutes.signup,
                                      );
                                    },
                                    child: const Text('Sign up →'),
                                  ),
                                ],
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
