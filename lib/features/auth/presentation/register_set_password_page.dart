import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/config/app_config.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';
import 'package:kmstry_frontend/features/venue/presentation/venue_context_onboarding_page.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/auth_repository.dart';

class RegisterSetPasswordPage extends StatefulWidget {
  final String email;
  final String otpProof;
  /// true ise kayit sonrasi venue claim akisina yonlendirilir.
  final bool isVenueSignup;

  const RegisterSetPasswordPage({
    super.key,
    required this.email,
    required this.otpProof,
    this.isVenueSignup = false,
  });

  @override
  State<RegisterSetPasswordPage> createState() =>
      _RegisterSetPasswordPageState();
}

class _RegisterSetPasswordPageState extends State<RegisterSetPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool marketingEmailOptIn = false;
  bool _legalConsent = false;
  bool _loadingLegalVersions = true;
  String? _termsVersionId;
  String? _privacyVersionId;
  String? _legalVersionsError;
  String? _legalConsentError;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(_onFormChanged);
    _confirmCtrl.addListener(_onFormChanged);
    _loadLegalVersions();
  }

  void _onFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _passwordCtrl.removeListener(_onFormChanged);
    _confirmCtrl.removeListener(_onFormChanged);
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
      if (code == 'LEGAL_CONSENT_REQUIRED') {
        return 'You must accept Terms and Privacy to create an account.';
      }
      if (code == 'LEGAL_VERSION_INVALID') {
        return 'Legal policy version is invalid. Please refresh and try again.';
      }
      if (code == 'LEGAL_VERSION_INACTIVE') {
        return 'Legal policies were updated. Please review and try again.';
      }
      if (code == 'LEGAL_VERSION_TYPE_MISMATCH') {
        return 'Legal policy mismatch detected. Please refresh and try again.';
      }
      if (code == 'LEGAL_CONSENT_SOURCE_INVALID') {
        return 'Invalid consent source. Please update the app and try again.';
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

  bool get _isPasswordReady =>
      _passwordCtrl.text.trim().length >= 8 &&
      _confirmCtrl.text.trim().isNotEmpty &&
      _confirmCtrl.text == _passwordCtrl.text;

  bool get _canSubmit =>
      !_loading &&
      !_loadingLegalVersions &&
      _legalVersionsError == null &&
      _legalConsent &&
      _isPasswordReady;

  Future<void> _loadLegalVersions() async {
    setState(() {
      _loadingLegalVersions = true;
      _legalVersionsError = null;
    });
    try {
      final versions = await AuthRepository().getActiveLegalVersions();
      if (!mounted) return;
      setState(() {
        _termsVersionId = versions.termsVersionId;
        _privacyVersionId = versions.privacyVersionId;
        _loadingLegalVersions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingLegalVersions = false;
        _legalVersionsError =
            'Policies could not be loaded. Check /legal/active-versions response shape and try again.';
      });
    }
  }

  Future<void> _openPolicy(String path) async {
    final uri = Uri.parse('${AppConfig.baseUrl}$path');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      await showPremiumErrorDialog(
        context,
        message: 'Unable to open policy link.',
      );
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_legalConsent) {
      setState(() {
        _legalConsentError =
            'You must agree to Terms of Service and Privacy Policy.';
      });
      return;
    }
    if (_termsVersionId == null || _privacyVersionId == null) {
      setState(() {
        _legalVersionsError = 'Policies could not be loaded. Please try again.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
      _legalConsentError = null;
    });

    try {
      await AuthRepository().registerAndAutoLogin(
        widget.email,
        _passwordCtrl.text,
        widget.otpProof,
        marketingEmailOptIn: marketingEmailOptIn,
        consentGiven: true,
        termsVersionId: _termsVersionId!,
        privacyVersionId: _privacyVersionId!,
        consentSource: 'MOBILE',
      );

      if (widget.isVenueSignup) {
        // Venue akisi: switchContext cagrilmaz — context'i claimVenue set edecek.
        // (activeVenueId olmadan VENUE context'e gecmek backend hatasina yol acar)
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const VenueContextOnboardingPage(),
          ),
        );
      } else {
        // Kisisel akis: context PERSONAL, kullanici adi adimina git
        await AuthRepository().switchContext(lastActiveContext: 'PERSONAL');
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AuthRoutes.onboardingUsername);
      }
    } catch (e) {
      if (!mounted) return;

      // Kayit onceki denemede basarili olmus ama sonraki adim hata vermis olabilir.
      // Token storage'da hala gecerli session varsa devam et.
      if (e is ApiException) {
        final code = e.data['errorCode']?.toString();
        if (code == 'EMAIL_ALREADY_IN_USE' || code == 'AUTH_EMAIL_IN_USE') {
          final isLoggedIn = await AuthRepository().restoreSession();
          if (!mounted) return;
          if (isLoggedIn) {
            if (widget.isVenueSignup) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const VenueContextOnboardingPage(),
                ),
              );
            } else {
              Navigator.of(context)
                  .pushReplacementNamed(AuthRoutes.onboardingUsername);
            }
            return;
          }
        }
      }

      setState(() => _error = _friendlySignupError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('Create Account')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.7),
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
                          value: marketingEmailOptIn,
                          onChanged: (v) =>
                              setState(() => marketingEmailOptIn = v ?? false),
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
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _legalConsent,
                          onChanged: _loadingLegalVersions
                              ? null
                              : (v) => setState(() {
                                  _legalConsent = v ?? false;
                                  _legalConsentError = null;
                                }),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Wrap(
                              children: [
                                const Text(
                                  'I agree to the ',
                                  style: TextStyle(fontSize: 13),
                                ),
                                InkWell(
                                  onTap: () => _openPolicy('/legal/terms'),
                                  child: Text(
                                    'Terms of Service',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text(
                                  ' and ',
                                  style: TextStyle(fontSize: 13),
                                ),
                                InkWell(
                                  onTap: () => _openPolicy('/legal/privacy'),
                                  child: Text(
                                    'Privacy Policy',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: colors.primary,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                                const Text('.', style: TextStyle(fontSize: 13)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_loadingLegalVersions)
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: LinearProgressIndicator(),
                      ),
                    if (_legalVersionsError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _legalVersionsError!,
                                style: TextStyle(color: colors.error),
                              ),
                            ),
                            TextButton(
                              onPressed: _loadLegalVersions,
                              child: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    if (_legalConsentError != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          _legalConsentError!,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    if (_error != null) ...[
                      const SizedBox(height: 6),
                      Text(_error!, style: TextStyle(color: colors.error)),
                    ],
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _canSubmit ? _register : null,
                        child: _loading
                            ? CircularProgressIndicator(color: colors.onPrimary)
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
