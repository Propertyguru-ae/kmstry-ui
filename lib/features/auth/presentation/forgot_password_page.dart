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
  /// Backend may include this when email is not sent (e.g. dev/test).
  String? _testResetUrl;

  /// Başarılı istek ama test linki yok: e-posta alanı yerinde onay + girişe git.
  bool get _prodEmailSentNoTestLink =>
      _requestSent && _testResetUrl == null;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  /// Reads reset link fields from the response (`resetUrl`, nested `data`, etc.).
  String? _parseResetUrlFromResponse(Map<String, dynamic> response) {
    const keys = [
      'resetUrl',
      'reset_url',
      'passwordResetUrl',
      'password_reset_url',
      'url',
      'link',
    ];
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

  String? _extractTokenFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final token = uri.queryParameters['token']?.trim();
      if (token != null && token.isNotEmpty) return token;
      return null;
    } catch (_) {
      return null;
    }
  }

  void _openResetPasswordFromTestUrl() {
    final rawUrl = _testResetUrl;
    if (rawUrl == null || rawUrl.trim().isEmpty) return;

    final token = _extractTokenFromUrl(rawUrl);
    if (token == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Invalid reset link (missing token).'),
        ),
      );
      return;
    }

    Navigator.of(context).pushNamed(
      AuthRoutes.resetPassword,
      arguments: token,
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AuthRoutes.login,
      (route) => false,
    );
  }

  Future<void> _send() async {
    setState(() {
      _loading = true;
      _requestSent = false;
      _testResetUrl = null;
    });

    try {
      final response = await AuthRepository().forgotPassword(
        _emailCtrl.text.trim(),
      );

      if (!mounted) return;

      final testUrl = _parseResetUrlFromResponse(response);

      setState(() {
        _requestSent = true;
        _testResetUrl = testUrl;
      });

      if (testUrl != null) {
        return;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requestSent = true;
        _testResetUrl = null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
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
            if (_prodEmailSentNoTestLink) ...[
              Text(
                'Reset link sent to your email.',
                style: TextStyle(
                  fontSize: 15,
                  color: colors.onSurfaceVariant,
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
            if (_requestSent && _testResetUrl != null) ...[
              const SizedBox(height: 16),
              Text(
                'Reset link sent to your email.',
                style: TextStyle(
                  fontSize: 14,
                  color: colors.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Test mode: tap the button below to reset your password.',
                style: TextStyle(
                  fontSize: 13,
                  color: colors.primary,
                  fontStyle: FontStyle.normal,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: OutlinedButton(
                  onPressed: _openResetPasswordFromTestUrl,
                  child: const Text('Continue to reset password'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
