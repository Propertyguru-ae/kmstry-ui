import 'dart:async';

import 'package:flutter/material.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import 'package:kmstry_frontend/features/auth/data/auth_repository.dart';
import 'package:kmstry_frontend/features/auth/presentation/auth_routes.dart';

class UsernameOnboardingPage extends StatefulWidget {
  final String? initialUsername;

  /// Opsiyonel — "Maybe later" basıldığında çağrılır. Null ise authGate'e yönlendirilir.
  final VoidCallback? onCancel;

  /// Opsiyonel — "Maybe later" basıldığında bu route'a gidilir. onCancel'a göre önceliklidir.
  final String? cancelRoute;

  /// Opsiyonel — çok adımlı onboarding akışı içinde kullanıldığında, kaydetme
  /// başarılı olunca authGate'e gitmek yerine bir sonraki adıma ilerlemek için
  /// çağrılır. Null ise klasik authGate yönlendirmesi yapılır.
  final VoidCallback? onContinue;

  const UsernameOnboardingPage({
    super.key,
    this.initialUsername,
    this.onCancel,
    this.cancelRoute,
    this.onContinue,
  });

  @override
  State<UsernameOnboardingPage> createState() => _UsernameOnboardingPageState();
}

class _UsernameOnboardingPageState extends State<UsernameOnboardingPage> {
  late final TextEditingController _usernameController;
  Timer? _suggestionDebounce;
  bool _loading = false;
  bool _loadingSuggestions = false;
  String? _error;
  String? _suggestionError;
  List<String> _suggestions = const [];

  static final RegExp _usernameRegex = RegExp(r'^[a-z0-9._]{3,30}$');

  @override
  void initState() {
    super.initState();
    _usernameController = TextEditingController(
      text: widget.initialUsername?.toLowerCase().trim() ?? '',
    );
  }

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    _usernameController.dispose();
    super.dispose();
  }

  String get _normalizedUsername =>
      _usernameController.text.trim().toLowerCase();

  bool get _isValid => _usernameRegex.hasMatch(_normalizedUsername);

  // ── Kural durumları (canlı doğrulama) ──────────────────────────────────
  bool get _okLength {
    final len = _normalizedUsername.length;
    return len >= 3 && len <= 30;
  }

  bool get _okChars {
    final v = _normalizedUsername;
    return v.isNotEmpty && RegExp(r'^[a-z0-9._]*$').hasMatch(v);
  }

  bool get _hasDotOrUnderscore =>
      _normalizedUsername.contains('.') || _normalizedUsername.contains('_');

  String _friendlyError(Object error) {
    if (error is ApiException) {
      final code = error.data['errorCode']?.toString().toUpperCase();
      final message = _extractBackendMessage(error.data);
      if (code == 'USERNAME_ALREADY_IN_USE') {
        return 'This username is already taken. Try another one.';
      }
      if (error.statusCode == 409 &&
          message.toLowerCase().contains('username already in use')) {
        return 'This username is already taken. Try another one.';
      }
      if (message.isNotEmpty) return message;
    }
    return 'Could not save username. Please try again.';
  }

  String _extractBackendMessage(Map<String, dynamic> data) {
    final raw = data['message'];
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first?.toString().trim() ?? '';
      if (first.isNotEmpty) return first;
    }
    return '';
  }

  Future<void> _continue() async {
    if (!_isValid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await AuthRepository().upsertPersonalProfile({
        'username': _normalizedUsername,
      });
      if (!mounted) return;
      if (widget.onContinue != null) {
        setState(() => _loading = false);
        widget.onContinue!();
      } else {
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _friendlyError(e);
      });
    }
  }

  void _onUsernameChanged() {
    if (!mounted) return;
    setState(() {
      _error = null;
      _suggestionError = null;
    });

    _suggestionDebounce?.cancel();
    final base = _normalizedUsername;
    if (base.length < 3) {
      setState(() {
        _loadingSuggestions = false;
        _suggestions = const [];
      });
      return;
    }
    _suggestionDebounce = Timer(const Duration(milliseconds: 300), () {
      _loadSuggestions(base);
    });
  }

  Future<void> _loadSuggestions(String base) async {
    if (!mounted) return;
    setState(() {
      _loadingSuggestions = true;
      _suggestionError = null;
    });
    try {
      final result = await AuthRepository().getUsernameSuggestions(base);
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestions = result.where((v) => v != _normalizedUsername).toList();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingSuggestions = false;
        _suggestions = const [];
        _suggestionError = 'Could not load suggestions.';
      });
    }
  }

  void _onCancel() {
    if (widget.cancelRoute != null) {
      Navigator.of(context).pushReplacementNamed(widget.cancelRoute!);
    } else if (widget.onCancel != null) {
      widget.onCancel!();
    } else {
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    }
  }

  // ── Marka renkleri (logo paleti — her iki temada aynı) ───────────────────
  static const _teal = AppColors.teal; // #1FD9A8
  static const _blue = AppColors.blue; // #1A9FE8
  static const _blueBright = AppColors.blueDark; // #4EC8FF
  static const _magenta = AppColors.magenta; // #E020D8
  static const _orange = AppColors.orange; // #F08838
  static const _purple = AppColors.brandLight; // #5B21B6
  static const _muted = Color(0xFFA6B3D2);
  static const _mutedDim = Color(0xFF7F91B2);

  // ── Tema-duyarlı yüzey/metin renkleri ────────────────────────────────────
  bool _isDark = true;
  Color get _bg => _isDark ? AppColors.darkBg : const Color(0xFFF7FAFF);
  Color get _sheet => _isDark ? AppColors.darkSurface : Colors.white;
  Color get _sheetBorder =>
      _isDark ? const Color(0xFF172445) : const Color(0xFFD9E5F4);
  Color get _fieldFill =>
      _isDark ? const Color(0xFF0F1C35) : const Color(0xFFF2F7FF);
  Color get _chipBorder =>
      _isDark ? const Color(0xFF3A2A6E) : const Color(0xFFD9E5F4);
  Color get _textPrimary =>
      _isDark ? const Color(0xFFEEF2FF) : AppColors.lightTextPrimary;
  Color get _textSecondary => _isDark ? _muted : AppColors.lightTextSecondary;
  Color get _hint =>
      _isDark ? const Color(0xFF33486A) : const Color(0xFF95A8C2);
  Color get _handle => _isDark
      ? Colors.white.withValues(alpha: 0.10)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);
  Color get _iconBtnBg => _isDark
      ? Colors.white.withValues(alpha: 0.05)
      : AppColors.lightTextPrimary.withValues(alpha: 0.05);
  Color get _iconBtnBorder => _isDark
      ? Colors.white.withValues(alpha: 0.09)
      : AppColors.lightTextPrimary.withValues(alpha: 0.12);

  @override
  Widget build(BuildContext context) {
    _isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: _bg,
        body: Stack(
          children: [
            // ── Marka ışıltıları (blue + magenta = app hero gradient) ────────
            Positioned(
              top: -80,
              left: 0,
              right: 0,
              child: Center(
                child: _glow(320, 280, _blue.withValues(alpha: 0.14)),
              ),
            ),
            Positioned(
              bottom: 40,
              right: -60,
              child: _glow(220, 220, _magenta.withValues(alpha: 0.10)),
            ),
            Positioned(
              top: 200,
              left: -70,
              child: _glow(190, 190, _purple.withValues(alpha: 0.12)),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Topbar ─────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        // Yalnızca dönülecek gerçek bir önceki ekran varsa geri
                        // tuşunu göster. Kayıt akışında stack temizlendiği için
                        // (pushNamedAndRemoveUntil) burada canPop=false olur ve
                        // kullanıcı bayat email/OTP sayfalarına düşmez.
                        if (Navigator.canPop(context))
                          _circleIconButton(
                            Icons.chevron_left_rounded,
                            () => Navigator.of(context).pop(),
                          )
                        else
                          const SizedBox(width: 38),
                        const Spacer(),
                        // "Maybe later" yalnızca dönülecek gerçek bir hedef
                        // varken gösterilir (ör. venue kullanıcısı personal hesap
                        // ekleyip vazgeçtiğinde venue home'a döner). Yeni kayıtta
                        // onCancel/cancelRoute null olur; username zorunlu adım
                        // olduğu için buton gizlenir.
                        if (widget.onCancel != null ||
                            widget.cancelRoute != null)
                          TextButton(
                            onPressed: _onCancel,
                            style: TextButton.styleFrom(
                              foregroundColor: _blueBright,
                            ),
                            child: const Text(
                              'Maybe later',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // ── Hero ───────────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 18,
                              height: 2,
                              decoration: BoxDecoration(
                                color: _orange,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'ALMOST THERE',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                                color: _orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Choose your',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: _textPrimary,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_orange, _magenta],
                          ).createShader(bounds),
                          child: const Text(
                            'username.',
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.12,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 9),
                        Text(
                          'This will be your unique identity on KMSTRY.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: _textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Sheet ──────────────────────────────────────────────
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _sheet,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        border: Border(top: BorderSide(color: _sheetBorder)),
                      ),
                      child: SingleChildScrollView(
                        padding: EdgeInsets.only(
                          left: 20,
                          right: 20,
                          top: 8,
                          bottom: bottomInset + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Center(
                              child: Container(
                                width: 34,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 22),
                                decoration: BoxDecoration(
                                  color: _handle,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const Text(
                              'USERNAME',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1,
                                color: _blueBright,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildInput(),
                            const SizedBox(height: 14),
                            _buildRule(_okLength, '3–30 characters'),
                            const SizedBox(height: 6),
                            _buildRule(
                              _okChars,
                              'Lowercase letters & numbers only',
                            ),
                            const SizedBox(height: 6),
                            _buildRule(
                              _hasDotOrUnderscore,
                              'Can contain . and _',
                              informational: true,
                            ),
                            if (_usernameController.text.isNotEmpty &&
                                !_isValid)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  'Invalid username format.',
                                  style: TextStyle(
                                    color: _magenta.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (_error != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: _magenta.withValues(alpha: 0.9),
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            if (_loadingSuggestions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: LinearProgressIndicator(
                                  color: _blue,
                                  backgroundColor: _fieldFill,
                                ),
                              ),
                            if (_suggestions.isNotEmpty) ...[
                              const Text(
                                'SUGGESTIONS',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.8,
                                  color: _mutedDim,
                                ),
                              ),
                              const SizedBox(height: 11),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _suggestions
                                    .take(4)
                                    .map(_buildChip)
                                    .toList(),
                              ),
                              const SizedBox(height: 22),
                            ],
                            if (_suggestionError != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: Text(
                                  _suggestionError!,
                                  style: const TextStyle(
                                    color: AppColors.orange,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            _buildContinueButton(),
                            const SizedBox(height: 14),
                            _buildPrivacyNote(),
                          ],
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

  Widget _glow(double w, double h, Color color) {
    return IgnorePointer(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0.0, 0.65],
          ),
        ),
      ),
    );
  }

  Widget _circleIconButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _iconBtnBg,
          border: Border.all(color: _iconBtnBorder),
        ),
        child: Icon(
          icon,
          size: 22,
          color: _isDark
              ? const Color(0xFF7D88A8)
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _buildInput() {
    return TextField(
      controller: _usernameController,
      autofocus: true,
      onSubmitted: (_) => _continue(),
      autocorrect: false,
      enableSuggestions: false,
      textInputAction: TextInputAction.done,
      onChanged: (_) => _onUsernameChanged(),
      cursorColor: _blue,
      style: TextStyle(color: _textPrimary, fontSize: 15, letterSpacing: -0.2),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: _fieldFill,
        hintText: 'kmstry.user',
        hintStyle: TextStyle(color: _hint),
        contentPadding: const EdgeInsets.symmetric(vertical: 15),
        prefixIcon: const Padding(
          padding: EdgeInsets.only(left: 16, right: 6),
          child: Text(
            '@',
            style: TextStyle(
              color: _blue,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: _isValid
            ? Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: _teal,
                  ),
                  child: Icon(Icons.check_rounded, size: 14, color: _bg),
                ),
              )
            : null,
        suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _blue, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _blueBright, width: 1.6),
        ),
      ),
    );
  }

  Widget _buildRule(bool ok, String text, {bool informational = false}) {
    final color = ok ? _teal : _mutedDim;
    return Row(
      children: [
        Icon(
          ok
              ? Icons.check_circle_rounded
              : (informational
                    ? Icons.radio_button_unchecked_rounded
                    : Icons.circle_outlined),
          size: 15,
          color: color,
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(fontSize: 11.5, color: color)),
      ],
    );
  }

  Widget _buildChip(String s) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () {
        setState(() {
          _usernameController.text = s;
          _usernameController.selection = TextSelection.collapsed(
            offset: s.length,
          );
          _error = null;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          color: _fieldFill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _chipBorder),
        ),
        child: Text(
          s,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _blueBright,
          ),
        ),
      ),
    );
  }

  Widget _buildContinueButton() {
    return PrimaryButton(
      label: 'Continue',
      onPressed: _isValid ? _continue : null,
      loading: _loading,
      trailingArrow: true,
    );
  }

  Widget _buildPrivacyNote() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _blue.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline_rounded, size: 15, color: _blue),
          const SizedBox(width: 9),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(
                  fontSize: 11,
                  height: 1.5,
                  fontWeight: FontWeight.w500,
                  color: _textSecondary,
                ),
                children: const [
                  TextSpan(text: 'Your username is '),
                  TextSpan(
                    text: 'public',
                    style: TextStyle(
                      color: _blueBright,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(
                    text:
                        ' and visible to other users. You can change it later.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
