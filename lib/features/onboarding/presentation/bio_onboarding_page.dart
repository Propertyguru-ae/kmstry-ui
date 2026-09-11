import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/theme/app_colors.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import 'package:kmstry_frontend/core/network/api_exception.dart';
import 'package:kmstry_frontend/core/ui/primary_button.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

/// Kişisel onboarding: isteğe bağlı bio (Skip veya Continue).
/// Metinler ürün dili: İngilizce.
class BioOnboardingPage extends StatefulWidget {
  final String? initialBio;

  /// Opsiyonel — çok adımlı onboarding akışında bir sonraki adıma ilerlemek için
  /// çağrılır. Null ise klasik authGate yönlendirmesi yapılır.
  final VoidCallback? onContinue;

  const BioOnboardingPage({super.key, this.initialBio, this.onContinue});

  static const int maxLength = 150;

  @override
  State<BioOnboardingPage> createState() => _BioOnboardingPageState();
}

class _BioOnboardingPageState extends State<BioOnboardingPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _loading = false;

  static const _darkBg = AppColors.darkBg;
  static const _darkSheet = AppColors.darkSurface;
  static const _teal = AppColors.teal;
  static const _blue = AppColors.blue;
  static const _blueBright = AppColors.blueDark;
  static const _magenta = AppColors.magenta;
  static const _orange = AppColors.orange;
  static const _purple = AppColors.brandLight;
  static const _darkMuted = Color(0xFFA6B3D2);
  static const _darkMutedDim = Color(0xFF7F91B2);
  static const _lightBg = Color(0xFFF7FAFF);
  static const _lightSheet = Colors.white;
  static const _lightField = Color(0xFFF2F7FF);
  static const _lightBorder = Color(0xFFD9E5F4);

  static const List<String> _inspirationChips = [
    'Good coffee, better conversations',
    'Always chasing good music',
    'Definitely a night owl',
    'Planning my next adventure',
    //'Collecting moments, not things',
  ];

  static const List<String> _chipEmojis = ['☕', '🎶', '🌙', '✈️', '📸'];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBio ?? '');
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() {});
  }

  /// Kaydetme sonrası: akış içindeyse bir sonraki adıma, değilse authGate'e.
  void _advance() {
    if (widget.onContinue != null) {
      setState(() => _loading = false);
      widget.onContinue!();
    } else {
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    }
  }

  Future<void> _continue() async {
    if (_loading) return;
    final text = _controller.text.trim();
    if (text.characters.length > BioOnboardingPage.maxLength) return;

    setState(() => _loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({'bio': text});
      if (!mounted) return;
      _advance();
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showPremiumErrorDialog(
        context,
        message: publicTextErrorMessage(
          error,
          fallback: 'Could not save your profile. Please try again.',
        ),
      );
    }
  }

  /// Backend `skipBio` / `bioOnboardingSkipped` ile adımı ilerletir; yoksa boş bio ile dene.
  Future<void> _skip() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({
        'skipBio': true,
        'bioOnboardingSkipped': true,
      });
      if (!mounted) return;
      _advance();
    } catch (_) {
      try {
        await AuthRepository().upsertPersonalProfile({'bio': ''});
        if (!mounted) return;
        _advance();
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
        await showPremiumErrorDialog(context, message: 'Something went wrong');
      }
    }
  }

  bool _isInspirationSelected(String value) {
    return _bioParts.contains(value);
  }

  List<String> get _bioParts {
    return _controller.text
        .split(' • ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  void _toggleInspiration(String value) {
    if (_loading) return;
    final parts = _bioParts;
    if (parts.contains(value)) {
      parts.remove(value);
    } else {
      final next = [...parts, value].join(' • ');
      if (next.characters.length > BioOnboardingPage.maxLength) return;
      parts.add(value);
    }

    final updated = parts.join(' • ');
    _controller.text = updated;
    _controller.selection = TextSelection.collapsed(offset: updated.length);
    setState(() {});
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final background = isDark ? _darkBg : _lightBg;
    final sheetColor = isDark ? _darkSheet : _lightSheet;
    final sheetBorder = isDark ? const Color(0xFF172445) : _lightBorder;
    final fieldFill = isDark ? const Color(0xFF0F1C35) : _lightField;
    final fieldBorder = isDark ? const Color(0xFF1A3060) : _lightBorder;
    final textPrimary = isDark
        ? const Color(0xFFF4F6FF)
        : AppColors.lightTextPrimary;
    final heroPrimary = isDark ? Colors.white : AppColors.lightTextPrimary;
    final textSecondary = isDark ? _darkMuted : AppColors.lightTextSecondary;
    final labelColor = _orange;
    final fieldLabelColor = isDark ? _blueBright : _blue;
    final handleColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : AppColors.lightTextPrimary.withValues(alpha: 0.12);
    final len = _controller.text.characters.length;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: background,
        body: Stack(
          children: [
            Positioned(
              top: -90,
              left: 0,
              right: 0,
              child: Center(
                child: _glow(
                  320,
                  280,
                  _blue.withValues(alpha: isDark ? 0.14 : 0.18),
                ),
              ),
            ),
            Positioned(
              bottom: 56,
              right: -64,
              child: _glow(
                220,
                220,
                _magenta.withValues(alpha: isDark ? 0.10 : 0.13),
              ),
            ),
            Positioned(
              top: 206,
              left: -78,
              child: _glow(
                190,
                190,
                _purple.withValues(alpha: isDark ? 0.12 : 0.10),
              ),
            ),
            SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        if (Navigator.canPop(context))
                          _circleIconButton(
                            onTap: () => Navigator.of(context).pop(),
                            isDark: isDark,
                          )
                        else
                          const SizedBox(width: 38),
                        const Spacer(),
                        TextButton(
                          onPressed: _loading ? null : _skip,
                          style: TextButton.styleFrom(
                            foregroundColor: labelColor,
                          ),
                          child: const Text(
                            'Skip',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 22),
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
                              'ABOUT YOU',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 2,
                                color: _orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Make your',
                          style: TextStyle(
                            fontSize: 30,
                            height: 1.12,
                            letterSpacing: -0.7,
                            fontWeight: FontWeight.w800,
                            color: heroPrimary,
                          ),
                        ),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [_orange, _magenta],
                          ).createShader(bounds),
                          child: const Text(
                            'first impression.',
                            style: TextStyle(
                              fontSize: 30,
                              height: 1.12,
                              letterSpacing: -0.7,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Add a few words that make your presence unforgettable.',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.5,
                            fontWeight: FontWeight.w500,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: sheetColor,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(26),
                        ),
                        border: Border(top: BorderSide(color: sheetBorder)),
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
                                  color: handleColor,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            _fieldLabel(
                              Icons.edit_outlined,
                              'BIO',
                              fieldLabelColor,
                            ),
                            const SizedBox(height: 8),
                            _buildBioField(
                              isDark: isDark,
                              fillColor: fieldFill,
                              borderColor: fieldBorder,
                              textPrimary: textPrimary,
                              textSecondary: textSecondary,
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Can be changed anytime from your profile.',
                                    style: TextStyle(
                                      color: textSecondary,
                                      fontSize: 11.5,
                                      height: 1.35,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$len / ${BioOnboardingPage.maxLength}',
                                  style: TextStyle(
                                    color: textSecondary,
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              'NEED INSPIRATION?',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.8,
                                color: isDark
                                    ? _darkMutedDim
                                    : AppColors.lightTextSecondary,
                              ),
                            ),
                            const SizedBox(height: 11),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (
                                  var i = 0;
                                  i < _inspirationChips.length;
                                  i++
                                )
                                  _inspirationChip(
                                    emoji: _chipEmojis[i],
                                    label: _inspirationChips[i],
                                    selected: _isInspirationSelected(
                                      _inspirationChips[i],
                                    ),
                                    isDark: isDark,
                                    onTap: () => _toggleInspiration(
                                      _inspirationChips[i],
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            PrimaryButton(
                              label: 'Continue',
                              onPressed: _continue,
                              loading: _loading,
                              trailingArrow: true,
                            ),
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

  Widget _glow(double width, double height, Color color) {
    return IgnorePointer(
      child: Container(
        width: width,
        height: height,
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

  Widget _circleIconButton({
    required VoidCallback onTap,
    required bool isDark,
  }) {
    final border = isDark
        ? Colors.white.withValues(alpha: 0.09)
        : AppColors.lightTextPrimary.withValues(alpha: 0.10);
    final fill = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.white.withValues(alpha: 0.78);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: fill,
          border: Border.all(color: border),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 22,
          color: isDark
              ? const Color(0xFF7D88A8)
              : AppColors.lightTextSecondary,
        ),
      ),
    );
  }

  Widget _fieldLabel(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildBioField({
    required bool isDark,
    required Color fillColor,
    required Color borderColor,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isFocused = _focusNode.hasFocus;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isFocused ? (isDark ? _blueBright : _blue) : borderColor,
          width: isFocused ? 1.6 : 1.4,
        ),
        boxShadow: [
          if (isFocused)
            BoxShadow(
              color: _blue.withValues(alpha: isDark ? 0.16 : 0.12),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
        ],
      ),
      child: TextField(
        focusNode: _focusNode,
        controller: _controller,
        onChanged: (_) => setState(() {}),
        contextMenuBuilder: (context, editableTextState) {
          return AdaptiveTextSelectionToolbar.editableText(
            editableTextState: editableTextState,
          );
        },
        maxLines: 5,
        minLines: 5,
        cursorColor: _blue,
        inputFormatters: [
          LengthLimitingTextInputFormatter(BioOnboardingPage.maxLength),
        ],
        style: TextStyle(
          color: textPrimary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
          height: 1.5,
        ),
        decoration: InputDecoration(
          hintText: 'Confident energy, good coffee, great conversations...',
          hintStyle: TextStyle(
            color: isDark
                ? const Color(0xFF33486A)
                : textSecondary.withValues(alpha: 0.68),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
        ),
      ),
    );
  }

  Widget _inspirationChip({
    required String emoji,
    required String label,
    required bool selected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    final border = selected
        ? _teal.withValues(alpha: isDark ? 0.55 : 0.42)
        : (isDark ? const Color(0xFF1E3060) : _lightBorder);
    final fill = selected
        ? _teal.withValues(alpha: isDark ? 0.13 : 0.10)
        : (isDark ? const Color(0xFF0F1C35) : _lightField);
    final text = selected
        ? (isDark ? Colors.white : AppColors.lightTextPrimary)
        : (isDark ? _darkMuted : AppColors.lightTextSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: fill,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 12.5)),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: text,
                fontSize: 11.8,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
