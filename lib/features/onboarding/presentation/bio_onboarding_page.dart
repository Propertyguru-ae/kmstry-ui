import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kmstry_frontend/core/ui/premium_feedback.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/presentation/auth_routes.dart';

/// Kişisel onboarding: isteğe bağlı bio (Skip veya Continue).
/// Metinler ürün dili: İngilizce.
class BioOnboardingPage extends StatefulWidget {
  final String? initialBio;

  const BioOnboardingPage({super.key, this.initialBio});

  static const int maxLength = 150;

  @override
  State<BioOnboardingPage> createState() => _BioOnboardingPageState();
}

class _BioOnboardingPageState extends State<BioOnboardingPage> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  bool _loading = false;
  bool _buttonPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialBio ?? '');
    _focusNode = FocusNode()..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    if (_loading) return;
    final text = _controller.text.trim();
    if (text.characters.length > BioOnboardingPage.maxLength) return;

    setState(() => _loading = true);
    try {
      await AuthRepository().upsertPersonalProfile({'bio': text});
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      await showPremiumErrorDialog(context, message: 'Something went wrong');
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
      Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
    } catch (_) {
      try {
        await AuthRepository().upsertPersonalProfile({'bio': ''});
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AuthRoutes.authGate);
      } catch (_) {
        if (!mounted) return;
        setState(() => _loading = false);
        await showPremiumErrorDialog(context, message: 'Something went wrong');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final surfaceBorder = isDark
        ? const Color(0xFF252D3D)
        : theme.colorScheme.outline.withValues(alpha: 0.28);
    const accent = Color.fromARGB(255, 11, 162, 237);
    final textPrimary = isDark
        ? const Color(0xFFF3F6FF)
        : theme.colorScheme.onSurface;
    final textSecondary = isDark
        ? const Color(0xFF98A3BC)
        : theme.colorScheme.onSurface.withValues(alpha: 0.68);
    final isFocused = _focusNode.hasFocus;
    final len = _controller.text.characters.length;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('About you'),
        automaticallyImplyLeading: false,
        backgroundColor: Colors.transparent,
        foregroundColor: textPrimary,
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _loading ? null : _skip,
            child: Text(
              'Skip',
              style: TextStyle(
                color: textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 112, 24, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Make your first impression',
                    style: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.4,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Add a few words that make your presence unforgettable.',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(height: 28),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isDark
                            ? const [Color(0xFF161C28), Color(0xFF1A2233)]
                            : [
                                theme.colorScheme.surface,
                                theme.colorScheme.surface.withValues(
                                  alpha: 0.95,
                                ),
                              ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isFocused ? accent : surfaceBorder,
                        width: isFocused ? 1.3 : 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: isFocused
                              ? accent.withValues(alpha: 0.10)
                              : Colors.black.withValues(
                                  alpha: isDark ? 0.10 : 0.05,
                                ),
                          blurRadius: isFocused ? 24 : 12,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: TextField(
                        focusNode: _focusNode,
                        controller: _controller,
                        onChanged: (_) => setState(() {}),
                        maxLines: 5,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(
                            BioOnboardingPage.maxLength,
                          ),
                        ],
                        style: TextStyle(
                          color: textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          height: 1.45,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Confident energy, good coffee, great conversations...',
                          hintStyle: TextStyle(color: textSecondary),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.fromLTRB(18, 18, 18, 16),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'This can be changed anytime from your profile.',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                      ),
                      Text(
                        '$len / ${BioOnboardingPage.maxLength}',
                        style: TextStyle(
                          color: textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            minimum: EdgeInsets.fromLTRB(
              24,
              12,
              24,
              MediaQuery.of(context).padding.bottom + 12,
            ),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 120),
              scale: _buttonPressed ? 0.985 : 1,
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: Listener(
                  onPointerDown: (_) => setState(() => _buttonPressed = true),
                  onPointerCancel: (_) =>
                      setState(() => _buttonPressed = false),
                  onPointerUp: (_) => setState(() => _buttonPressed = false),
                  child: ElevatedButton(
                    onPressed: _loading ? null : _continue,
                    child: _loading
                        ? SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isDark ? Colors.black : Colors.white,
                            ),
                          )
                        : const Text('Continue'),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
