import 'package:flutter/material.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class ForgotPasswordPage extends StatefulWidget {
  const ForgotPasswordPage({super.key});

  @override
  State<ForgotPasswordPage> createState() => _ForgotPasswordPageState();
}

class _ForgotPasswordPageState extends State<ForgotPasswordPage> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  bool _requestSent = false;
  String _sentToEmail = '';

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.login,
      (route) => false,
    );
  }

  Future<void> _send() async {
    final email = _emailCtrl.text.trim();
    setState(() {
      _loading = true;
      _requestSent = false;
    });

    try {
      await AuthRepository().forgotPassword(email);
    } catch (_) {
      // Enumeration güvenliği: hata olsa da aynı onayı göster.
    } finally {
      if (mounted) {
        setState(() {
          _sentToEmail = email;
          _requestSent = true;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot Password')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_requestSent) ...[
              Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 15,
                    color: colors.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: 'Reset link sent to '),
                    TextSpan(
                      text: _sentToEmail,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: colors.onSurface,
                      ),
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _goToLogin,
                  child: const Text('Go to login page'),
                ),
              ),
            ] else ...[
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  hintText: 'Email',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _send,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Send reset email'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
