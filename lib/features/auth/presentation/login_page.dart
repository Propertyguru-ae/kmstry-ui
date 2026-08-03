import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/venue/data/venue_invite_repository.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_invite_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../data/auth_repository.dart';
import 'auth_routes.dart';
import 'dart:io' show Platform;

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

  bool _isConsentRequiredError(ApiException error) {
    final code = error.data['errorCode']?.toString().toUpperCase();
    final message = _extractBackendMessage(error.data).toLowerCase();
    return code == 'CONSENT_REQUIRED_FOR_SOCIAL_LOGIN' ||
        code == 'LEGAL_CONSENT_REQUIRED' ||
        message.contains('consent is required for first-time social login');
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.siteBaseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await showPremiumErrorDialog(
        context,
        message: 'Unable to open policy link.',
      );
    }
  }

  Future<bool?> _showGoogleConsentSheet() {
    bool consent = false;
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Consent Required',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text('Please agree to continue with Google sign in.'),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: consent,
                          onChanged: (v) =>
                              setSheetState(() => consent = v ?? false),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              children: [
                                const Text('I agree to the '),
                                InkWell(
                                  onTap: () => _openPolicy('/terms'),
                                  child: Text(
                                    'Terms of Service',
                                    style: TextStyle(
                                      color: colors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(' and '),
                                InkWell(
                                  onTap: () => _openPolicy('/privacy'),
                                  child: Text(
                                    'Privacy Policy',
                                    style: TextStyle(
                                      color: colors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text('.'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: consent
                            ? () => Navigator.of(sheetContext).pop(true)
                            : null,
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool> _loginWithGoogleWithConsentFlow() async {
    final authRepository = AuthRepository();
    try {
      return await authRepository.loginWithGoogle();
    } on ApiException catch (e) {
      if (!_isConsentRequiredError(e)) rethrow;
      final versions = await authRepository.getActiveLegalVersions();
      if (!mounted) return false;
      final consent = await _showGoogleConsentSheet();
      if (consent != true) return false;
      return authRepository.loginWithGoogle(
        consentGiven: true,
        termsVersionId: versions.termsVersionId,
        privacyVersionId: versions.privacyVersionId,
        consentSource: 'MOBILE',
      );
    }
  }

  Future<bool> _loginWithAppleWithConsentFlow() async {
    final authRepository = AuthRepository();
    try {
      return await authRepository.loginWithApple();
    } on ApiException catch (e) {
      if (!_isConsentRequiredError(e)) rethrow;
      final versions = await authRepository.getActiveLegalVersions();
      if (!mounted) return false;
      final consent = await _showGoogleConsentSheet();
      if (consent != true) return false;
      return authRepository.loginWithApple(
        consentGiven: true,
        termsVersionId: versions.termsVersionId,
        privacyVersionId: versions.privacyVersionId,
        consentSource: 'MOBILE',
      );
    }
  }

  String _friendlyLoginError(Object error) {
    if (error is ApiException) {
      final status = error.statusCode;
      final code = error.data['errorCode']?.toString();
      final message = _extractBackendMessage(error.data);

      if (code == 'ACCOUNT_BANNED') {
        return message.isNotEmpty
            ? message
            : 'Your account has been suspended. Please contact support if you believe this is a mistake.';
      }
      if (code == 'INVALID_CREDENTIALS' || code == 'AUTH_INVALID_CREDENTIALS') {
        return 'The email or password you entered is incorrect.';
      }
      if (code == 'EMAIL_NOT_VERIFIED') {
        return 'Please verify your email address before signing in.';
      }
      if (status == 429) {
        return 'Too many attempts. Please wait a moment and try again.';
      }
      if (status >= 500) {
        return 'We are unable to sign you in right now. Please try again shortly.';
      }
      if (message.isNotEmpty) {
        return message;
      }
    }

    final raw = error.toString().toLowerCase();
    if (raw.contains('timeout')) {
      return 'The request timed out. Please check your connection and try again.';
    }
    if (raw.contains('socketexception') || raw.contains('failed host lookup')) {
      return 'No internet connection. Please check your network and try again.';
    }
    return 'We could not sign you in. Please try again.';
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
                    final navigator = Navigator.of(context);
                    try {
                      final success = await _loginWithGoogleWithConsentFlow();
                      if (!context.mounted) return;
                      if (success) {
                        navigator.pop();
                        navigator.pushReplacementNamed(AuthRoutes.authGate);
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      await showPremiumErrorDialog(
                        context,
                        message: _friendlyLoginError(e),
                      );
                    }
                  },
                  child: const Text('Continue with Google'),
                ),

              if (providers.contains('apple') && Platform.isIOS)
                ElevatedButton(
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    try {
                      final success = await _loginWithAppleWithConsentFlow();
                      if (!context.mounted) return;
                      if (success) {
                        navigator.pop();
                        navigator.pushReplacementNamed(AuthRoutes.authGate);
                      }
                    } catch (e) {
                      if (!context.mounted) return;
                      await showPremiumErrorDialog(
                        context,
                        message: _friendlyLoginError(e),
                      );
                    }
                  },
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
      await AuthRepository().login(
        _emailCtrl.text.trim().toLowerCase(),
        _passCtrl.text,
      );
      if (!mounted) return;

      final pendingInvite = await VenueInviteRepository().getPendingInvite();
      if (!mounted) return;
      if (pendingInvite != null) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => VenueInvitePage(token: pendingInvite.token),
          ),
          (route) => false,
        );
        return;
      }

      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (e) {
      if (e is ApiException) {
        final code = e.data['errorCode'];

        if (code == 'SOCIAL_LOGIN_ONLY') {
          setState(() => _loading = false);
          _handleSocialLoginOnly(e.data);
          return;
        }
      }
      setState(() => _error = _friendlyLoginError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final outerBackground = isDark
        ? theme.scaffoldBackgroundColor
        : Colors.white;
    final bottomSheetRadius = BorderRadius.circular(24);

    return Scaffold(
      backgroundColor: outerBackground,
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
                        color: isDark
                            ? colors.surface
                            : const Color(0xFFF8FBFD),
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

                              // Email veya kullanıcı adı
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.text,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.person_outline),
                                  hintText: 'Email or username',
                                  border: OutlineInputBorder(),
                                ),
                                validator: (v) {
                                  final x = (v ?? '').trim();
                                  if (x.isEmpty)
                                    return 'Please enter your email or username.';
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
                                  if ((v ?? '').isEmpty) {
                                    return 'Please enter your password.';
                                  }
                                  return null;
                                },
                              ),

                              const SizedBox(height: 14),

                              if (_error != null)
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: colors.error),
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
                              Center(
                                child: Text(
                                  'Or',
                                  style: TextStyle(
                                    color: colors.onSurface.withValues(
                                      alpha: 0.7,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Center(
                                child: Text(
                                  'Sign in with',
                                  style: TextStyle(
                                    color: colors.onSurface.withValues(
                                      alpha: 0.8,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _SocialCircle(
                                    label: 'G',
                                    onTap: () async {
                                      final navigator = Navigator.of(context);
                                      try {
                                        final success =
                                            await _loginWithGoogleWithConsentFlow();
                                        if (!mounted) return;

                                        if (success) {
                                          navigator.pushReplacementNamed(
                                            AuthRoutes.authGate,
                                          );
                                        }
                                      } catch (e) {
                                        if (!mounted) return;
                                        await showPremiumErrorDialog(
                                          context,
                                          message: _friendlyLoginError(e),
                                        );
                                      }
                                    },
                                  ),

                                  if (Platform.isIOS) ...[
                                    const SizedBox(width: 14),
                                    _SocialCircle(
                                      label: '',
                                      onTap: () async {
                                        final navigator = Navigator.of(context);
                                        try {
                                          final success =
                                              await _loginWithAppleWithConsentFlow();
                                          if (!mounted) return;
                                          if (success) {
                                            navigator.pushReplacementNamed(
                                              AuthRoutes.authGate,
                                            );
                                          }
                                        } catch (e) {
                                          if (!mounted) return;
                                          await showPremiumErrorDialog(
                                            context,
                                            message: _friendlyLoginError(e),
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ],
                              ),

                              const SizedBox(height: 24),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    "Don’t have an account? ",
                                    style: TextStyle(
                                      color: colors.onSurface.withValues(
                                        alpha: 0.85,
                                      ),
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: () {
                                      Navigator.pushNamed(
                                        context,
                                        AuthRoutes.contextChoice,
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
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: theme.brightness == Brightness.dark
              ? colors.surface.withValues(alpha: 0.8)
              : colors.surface.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(999),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colors.onSurface,
          ),
        ),
      ),
    );
  }
}
